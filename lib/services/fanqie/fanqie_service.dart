import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/book.dart';
import '../epub_service.dart';
import 'fanqie_map.dart';

/// 番茄小说在线下载服务(无后端,Flutter 直连官方网页接口)。
///
/// 已验证的可行链路(2026-09-03 实测):
///  1. 目录 `GET /api/reader/directory/detail?bookId=` 匿名可用,含卷/章与 VIP 标记;
///  2. 书页 `/page/{bookId}` SSR 内含书名/作者/封面;
///  3. 正文只有阅读页 `/reader/{itemId}` SSR 内嵌,且为字体混淆文本,
///     但其 PUA 码位十进制 == 番茄全局字形编号,用 [FanqieMap] 静态表即可还原,
///     无需下载/解析 woff 字体。
/// 关键词搜索被官方安全 SDK(secsdk/captcha)风控,无后端不可匿名使用,故暂不支持。
class FanqieService {
  FanqieService._();

  static const String host = 'https://fanqienovel.com';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// 两次章节请求之间的最小间隔(秒),避免被限流。
  static const Duration requestInterval = Duration(milliseconds: 350);

  /// 每次落盘间隔(章节数),保证取消/失败后已下载部分仍可入架续传。
  static const int _persistEvery = 10;

  /// 单章请求超时。
  static const Duration _timeout = Duration(seconds: 20);

  /// 单章失败重试次数。
  static const int _maxRetry = 2;

  static Future<http.Response> _get(String url,
      {String? referer, String? cookie}) async {
    final headers = <String, String>{
      'User-Agent': _ua,
      'Accept': '*/*',
      'Referer': ?referer,
      'Cookie': ?cookie,
    };
    final resp = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_timeout);
    return resp;
  }

  /// 归一化用户粘贴的 Cookie:容忍整行 `Cookie: a=b; c=d` 或纯 `a=b; c=d`。
  static String? normalizeCookie(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase().startsWith('cookie:')) {
      s = s.substring('cookie:'.length).trim();
    }
    return s.isEmpty ? null : s;
  }

  static String _body(http.Response resp) =>
      utf8.decode(resp.bodyBytes, allowMalformed: true);

  /// 归一化封面 URL:thumbUri 常为无 scheme 的 `//...`,需补 `https:`。
  static String? _normalizeUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var url = raw.trim();
    if (url.startsWith('//')) url = 'https:$url';
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    return url;
  }

  /// 从 链接 / 纯数字 中提取番茄书籍 ID;解析失败返回 null。
  static String? parseBookId(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    final m = RegExp(r'\d{10,30}').firstMatch(input);
    if (m == null) return null;
    final id = input.substring(m.start, m.end);
    // 纯数字时仍要求 10 位以上(番茄书 ID 均为长数字)。
    return id.length >= 10 ? id : null;
  }

  /// 单卷章节信息(公开以便单测复用;入参为目录响应中的 data 对象)。
  static List<FanqieChapterItem> parseChapters(Map<String, dynamic> data) {
    final rawVolumes = data['chapterListWithVolume'];
    final items = <FanqieChapterItem>[];
    if (rawVolumes is! List) return items;
    var order = 0;
    for (final volume in rawVolumes) {
      if (volume is! List) continue;
      for (final raw in volume) {
        if (raw is! Map) continue;
        order += 1;
        final needPay = _asInt(raw['needPay']);
        final locked = needPay > 0 ||
            raw['isChapterLock'] == true ||
            raw['isPaidStory'] == true ||
            raw['isPaidPublication'] == true;
        items.add(FanqieChapterItem(
          itemId: raw['itemId']?.toString() ?? '',
          title: raw['title']?.toString() ?? '第$order章',
          volumeName: raw['volume_name']?.toString() ?? '',
          order: order,
          locked: locked,
        ));
      }
    }
    return items;
  }

  /// 拉取书籍元信息 + 完整目录(两次 GET,均匿名可用)。
  static Future<FanqieBookMeta> fetchBookMeta(String bookId) async {
    // 1) 目录(轻量):章节数据在顶层 data.chapterListWithVolume 下
    final dirUrl = '$host/api/reader/directory/detail?bookId=$bookId';
    final dirResp = await _get(dirUrl, referer: '$host/page/$bookId');
    if (dirResp.statusCode != 200) {
      throw FanqieException('获取目录失败(HTTP ${dirResp.statusCode})');
    }
    final decoded = jsonDecode(_body(dirResp));
    final data =
        decoded is Map<String, dynamic> ? decoded['data'] : null;
    if (data is! Map<String, dynamic>) {
      throw FanqieException('目录格式异常');
    }
    final chapters = parseChapters(data);
    if (chapters.isEmpty) {
      throw FanqieException('未获取到章节,请确认书籍 ID 正确');
    }

    // 2) 书页元信息(书名/作者/封面)
    var title = '';
    var author = '';
    String? coverUrl;
    var wordCount = 0;
    try {
      final pageResp = await _get('$host/page/$bookId',
          referer: '$host/page/$bookId');
      if (pageResp.statusCode == 200) {
        final page = extractObjectWithKey(_body(pageResp), 'page',
            has: 'bookName');
        if (page != null) {
          title = page['bookName']?.toString() ?? '';
          author = _parseAuthor(page);
          coverUrl = _normalizeUrl(page['thumbUri']?.toString());
          wordCount = _asInt(page['wordNumber']);
        }
      }
    } catch (_) {
      // 元信息失败不阻断:用占位信息继续
    }
    if (title.isEmpty) title = bookId;
    if (author.isEmpty) author = '未知作者';

    return FanqieBookMeta(
      bookId: bookId,
      title: title,
      author: author,
      coverUrl: coverUrl,
      wordCount: wordCount,
      chapters: chapters,
    );
  }

  static String _parseAuthor(Map<String, dynamic> page) {
    final direct = page['authorName']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final oa = page['originalAuthors'];
    if (oa is List) {
      for (final e in oa) {
        if (e is Map) {
          final name = e['AuthorName']?.toString();
          if (name != null && name.isNotEmpty) return name;
        }
      }
    }
    final author = page['author'];
    if (author is String) return author;
    return '';
  }

  /// 抓取并解码单章正文。
  ///
  /// [cookie] 为可选登录态(浏览器登录番茄后复制)。匿名时 VIP/付费章服务端
  /// 只返回约 200 字符试读;带有效登录 Cookie 且账号具备阅读权限时才返回全文。
  /// 返回 null 表示该章无正文;返回结果的 [FanqieChapterFetch.preview] 为 true
  /// 表示只拿到试读片段(权限不足),不应入库。
  static Future<FanqieChapterFetch?> fetchChapterContent(
    String itemId, {
    String? cookie,
  }) async {
    final ck = normalizeCookie(cookie);
    // 1) 阅读页 SSR(匿名/登录均可请求)
    final resp = await _get('$host/reader/$itemId',
        referer: '$host/reader/$itemId', cookie: ck);
    if (resp.statusCode != 200) {
      throw FanqieException('HTTP ${resp.statusCode}');
    }
    final body = _body(resp);
    final chapter = extractObjectWithKey(body, 'chapterData', has: 'content');
    final content = chapter?['content']?.toString() ?? '';
    final wordNumber = _asInt(chapter?['chapterWordNumber']);
    final lockedMark = hasLockedMark(chapter);
    var text = _decodeOrNull(content);
    var preview = isPreviewText(text, wordNumber, lockedMark);

    // 2) SSR 只给试读/空、但带了 Cookie 时,再试正文 JSON 接口一次。
    //    部分场景完整正文只在该接口按登录态返回。
    if ((preview || text == null) && ck != null) {
      try {
        final alt = await _fetchFullApi(itemId, ck);
        if (alt != null) {
          final altText = _decodeOrNull(alt.$1);
          final altWord = alt.$2;
          if (!isPreviewText(altText, altWord, lockedMark) &&
              (altText?.length ?? 0) > (text?.length ?? 0)) {
            text = altText;
            preview = false;
          }
        }
      } catch (_) {
        // JSON 接口失败不阻断:保留 SSR 结果
      }
    }

    if (text == null || text.trim().isEmpty) return null;
    return FanqieChapterFetch(text: text, preview: preview);
  }

  /// 正文 JSON 接口:返回 (content, chapterWordNumber),匿名多为空 body。
  static Future<(String, int)?> _fetchFullApi(String itemId, String cookie) async {
    final resp = await _get('$host/api/reader/full?itemId=$itemId',
        referer: '$host/reader/$itemId', cookie: cookie);
    if (resp.statusCode != 200) return null;
    final body = _body(resp).trim();
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      final root = decoded is Map<String, dynamic> ? decoded : null;
      final data = root?['data'];
      final cd = data is Map<String, dynamic>
          ? (data['chapterData'] is Map<String, dynamic>
              ? data['chapterData'] as Map<String, dynamic>
              : data)
          : null;
      final content = cd?['content']?.toString() ?? '';
      if (content.trim().isEmpty) return null;
      return (content, _asInt(cd?['chapterWordNumber']));
    } catch (_) {
      return null;
    }
  }

  static String? _decodeOrNull(String htmlContent) {
    if (htmlContent.trim().isEmpty) return null;
    final t = FanqieMap.decodeChapterHtml(htmlContent);
    return t.trim().isEmpty ? null : t;
  }

  /// 试读判定:已知真实字数且正文明显短于它(番茄试读固定约 1/15),视为试读。
  /// 字数未知时退回长度阈值(试读固定约 200 HTML 字符/150+ 明文)。
  /// 公开以便单测覆盖。
  static bool isPreviewText(String? text, int wordNumber, bool lockedMark) {
    if (text == null) return false;
    final len = text.trim().length;
    if (wordNumber > 0) {
      if (len < wordNumber * 0.5) return true; // 已知字数:短于一半即试读
      return false;
    }
    // 未知字数:锁定章按明显试读长度判;非锁定章信任正文
    return lockedMark && len < 400;
  }

  /// chapterData 是否携带锁定/付费标记(公开便于单测)。
  static bool hasLockedMark(Map<String, dynamic>? chapter) {
    if (chapter == null) return false;
    return _asInt(chapter['needPay']) > 0 ||
        chapter['isChapterLock'] == true ||
        chapter['isPaidStory'] == true ||
        chapter['isPaidPublication'] == true;
  }

  /// 从 HTML/JSON 源码中定位第一个包含指定键的 JSON 对象值并解码。
  static Map<String, dynamic>? extractObjectWithKey(
      String source, String key,
      {String has = ''}) {
    var from = 0;
    while (true) {
      final hit = source.indexOf('"$key"', from);
      if (hit < 0) return null;
      final brace = source.indexOf('{', hit + key.length + 2);
      if (brace < 0) return null;
      final obj = readJsonObject(source, brace);
      if (obj != null) {
        final map = obj is Map<String, dynamic> ? obj : null;
        if (map != null && (has.isEmpty || map.containsKey(has))) {
          return map;
        }
      }
      from = brace + 1;
    }
  }

  /// 从 [start]('{'处)开始做平衡括号扫描,返回该 JSON 对象。
  static Object? readJsonObject(String source, int start) {
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < source.length; i++) {
      final c = source[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth += 1;
      } else if (c == '}') {
        depth -= 1;
        if (depth == 0) {
          try {
            return jsonDecode(source.substring(start, i + 1));
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// 下载选中的章节范围并入架。
  ///
  /// [catalog] 为全本目录(顺序即阅读顺序);[startOrder]/[endOrder] 为 1-based
  /// 范围(含端点),null 表示不限。重复下载同名书时自动续传:已成功下载的章节
  /// 跳过,与既有章节合并保存。
  ///
  /// [cookie] 为可选登录态。无 Cookie 时 VIP/付费章自动跳过;带 Cookie 时会
  /// 尝试抓取 VIP 章,仅当服务端返回全文(非试读)才入库,否则按无权限跳过。
  static Future<FanqieDownloadStats> downloadBook({
    required String bookId,
    required FanqieBookMeta meta,
    required List<FanqieChapterItem> catalog,
    int? startOrder,
    int? endOrder,
    String? cookie,
    void Function(FanqieDownloadStats)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final ck = normalizeCookie(cookie);
    final oursId = 'fanqie_$bookId';

    // 封面(可选,失败不阻断)
    String? coverPath;
    if (meta.coverUrl != null && meta.coverUrl!.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse(meta.coverUrl!),
                headers: const {'User-Agent': _ua, 'Accept': 'image/jpeg'})
            .timeout(_timeout);
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final magic = resp.bodyBytes;
          final isPng = magic.isNotEmpty && magic[0] == 0x89;
          final isJpeg = magic.isNotEmpty && magic[0] == 0xFF;
          if (isPng || isJpeg) {
            coverPath = await EpubService.saveCover(oursId, magic);
          }
        }
      } catch (_) {}
    }

    // 续传:读已入库章节(title -> 正文)
    final existing = <String, String>{};
    final oldBook = await EpubService.loadBook(oursId);
    for (final ch in oldBook?.chapters ?? const <Chapter>[]) {
      if (ch.content.isNotEmpty) existing[ch.title] = ch.content;
    }

    final inRange = <FanqieChapterItem>[];
    for (final c in catalog) {
      if (startOrder != null && c.order < startOrder) continue;
      if (endOrder != null && c.order > endOrder) continue;
      inRange.add(c);
    }

    final newContent = <String, String>{...existing};
    var lockedSkip = 0;
    var already = 0;
    var failed = 0;
    var fetchedOk = 0;
    final total = inRange.length;

    Future<void> persistPartial() async {
      await _persistBook(oursId, meta, coverPath, catalog, newContent);
    }

    void report({String? currentTitle}) {
      onProgress?.call(FanqieDownloadStats(
        total: total,
        fetched: fetchedOk,
        already: already,
        lockedSkipped: lockedSkip,
        failed: failed,
        currentTitle: currentTitle,
      ));
    }

    var sinceLastSave = 0;
    for (final ch in inRange) {
      // 已下载过(含上次会话落盘):计入 already,保留既有正文
      if (newContent.containsKey(ch.title) &&
          newContent[ch.title]!.isNotEmpty) {
        already += 1;
        continue;
      }
      // 锁定章:无 Cookie 一律跳过;有 Cookie 才进入下方抓取尝试
      if (ch.locked && ck == null) {
        lockedSkip += 1;
        continue;
      }
      if (isCancelled != null && await isCancelled()) {
        break;
      }
      report(currentTitle: ch.title);

      FanqieChapterFetch? result;
      for (var attempt = 0; attempt <= _maxRetry; attempt++) {
        try {
          result = await fetchChapterContent(ch.itemId, cookie: ck);
          break;
        } catch (_) {
          if (attempt == _maxRetry) {
            result = null;
          } else {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }

      if (result == null || result.preview) {
        // 无正文或只拿到试读片段:锁定章记跳过,普通章记失败
        if (ch.locked) {
          lockedSkip += 1;
        } else {
          failed += 1;
        }
      } else {
        newContent[ch.title] = result.text;
        fetchedOk += 1;
        sinceLastSave += 1;
        if (sinceLastSave >= _persistEvery) {
          await persistPartial();
          sinceLastSave = 0;
        }
      }
      report();
      if (isCancelled != null && await isCancelled()) {
        break;
      }
      await Future<void>.delayed(requestInterval);
    }

    if (fetchedOk + already > 0) {
      await persistPartial();
    }

    final stats = FanqieDownloadStats(
      total: total,
      fetched: fetchedOk,
      already: already,
      lockedSkipped: lockedSkip,
      failed: failed,
      currentTitle: null,
    );
    return stats;
  }

  static Future<void> _persistBook(
    String oursId,
    FanqieBookMeta meta,
    String? coverPath,
    List<FanqieChapterItem> catalog,
    Map<String, String> contentByTitle,
  ) async {
    final chapters = <Chapter>[];
    for (final c in catalog) {
      final content = contentByTitle[c.title];
      if (content != null && content.isNotEmpty) {
        chapters.add(Chapter(title: c.title, content: content));
      }
    }
    final book = Book(
      id: oursId,
      title: meta.title,
      author: meta.author,
      coverPath: coverPath,
      sourcePath: 'fanqie://${meta.bookId}',
      chapters: chapters,
    );
    await EpubService.saveBook(book);
  }
}

class FanqieException implements Exception {
  final String message;
  const FanqieException(this.message);

  @override
  String toString() => message;
}

/// 单卷章节(目录项)。
class FanqieChapterItem {
  final String itemId;
  final String title;
  final String volumeName;
  final int order;
  final bool locked;

  const FanqieChapterItem({
    required this.itemId,
    required this.title,
    required this.volumeName,
    required this.order,
    required this.locked,
  });
}

/// 书籍元信息 + 完整目录。
class FanqieBookMeta {
  final String bookId;
  final String title;
  final String author;
  final String? coverUrl;
  final int wordCount;
  final List<FanqieChapterItem> chapters;

  const FanqieBookMeta({
    required this.bookId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.wordCount,
    required this.chapters,
  });

  int get lockedCount => chapters.where((c) => c.locked).length;
}

/// 单章抓取结果:[text] 为解码后正文;[preview] 为 true 表示只拿到试读片段
/// (服务端未按登录态放行全文),不应入库。
class FanqieChapterFetch {
  final String text;
  final bool preview;

  const FanqieChapterFetch({required this.text, required this.preview});
}

/// 下载进度统计。
class FanqieDownloadStats {
  final int total;
  final int fetched;
  final int already;
  final int lockedSkipped;
  final int failed;
  final String? currentTitle;

  const FanqieDownloadStats({
    required this.total,
    required this.fetched,
    required this.already,
    required this.lockedSkipped,
    required this.failed,
    this.currentTitle,
  });
}
