import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../utils/book_id.dart';
import 'gbk_table.dart';

/// 本地 txt 小说导入。
///
/// 支持的编码:UTF-8(含 BOM)、UTF-16 LE/BE(含 BOM)、GBK/GB18030 双字节。
/// 章节识别:按「第 X 章 / 节 / 回 / 卷」行切分;识别不到时按长度兜底分节。
class TxtImporter {
  /// 章节标题行,例如:第一章 少年、第123章、第十七回 大闹天宫、第3卷
  ///
  /// 标题正文部分限制在 30 字内且不允许出现句读标点(。!?;,.、:：),
  /// 否则「第二章正文开始。剧情继续……」这类以「第 X 章」开头的正文句子
  /// 会被误判成标题 —— 这是纯文本按行启发式切分最主要的坑。
  static final RegExp _headingRe = RegExp(
    r'^[ \t\u3000]*(第[0-9零〇一二三四五六七八九十百千万两]{1,12}[章节回卷集部篇][^\n。!?;，,、:：]{0,30})[ \t\u3000]*$',
    multiLine: true,
  );

  /// 作者行,例如:作者:烽火戏诸侯 / 作 者 : xxx
  static final RegExp _authorRe = RegExp(r'作\s*者\s*[:：]\s*(\S{1,20})');

  /// 单章目标字数(仅在识别不到章节标题时用于兜底切分)
  static const int _fallbackChunkSize = 3000;

  /// 解析一个 txt 文件,返回 Book(不落盘,由调用方决定是否入架)。
  static Future<Book> parseFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('文件为空');
    }
    final text = decodeBytes(bytes);
    if (text.trim().isEmpty) {
      throw const FormatException('文件内容为空或编码无法识别');
    }

    final fallbackTitle = p.basenameWithoutExtension(filePath);
    final bookTitle = _guessTitle(text) ?? fallbackTitle;
    final author = _authorRe.firstMatch(_head(text, 4000))?.group(1) ?? '未知作者';
    final chapters = splitChapters(text, bookTitle: bookTitle);
    if (chapters.isEmpty) {
      throw const FormatException('没有解析出任何正文');
    }

    return Book(
      id: makeBookId(bookTitle, author),
      title: bookTitle,
      author: author,
      coverPath: null,
      sourcePath: filePath,
      chapters: chapters,
    );
  }

  /// 按字节探测编码并解码为字符串。
  static String decodeBytes(Uint8List bytes) {
    // 1) BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }

    // 2) 严格 UTF-8:能解通就认为不是 GBK
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      // 落到 GBK
    }

    // 3) 无 BOM 的 UTF-16(大量 0x00 交替出现)
    final utf16 = _sniffUtf16(bytes);
    if (utf16 != null) return utf16;

    // 4) GBK
    return decodeGbk(bytes);
  }

  /// 逐字节解码 GBK(GB18030 双字节部分)。
  static String decodeGbk(Uint8List bytes) {
    final buf = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x80) {
        // ASCII:合并连续字节一次性 append,减少调用开销
        var j = i;
        while (j < bytes.length && bytes[j] < 0x80) {
          j++;
        }
        buf.write(String.fromCharCodes(bytes, i, j));
        i = j;
        continue;
      }
      if (b == 0x80) {
        buf.write('\u20AC'); // GBK 0x80 = 欧元符号
        i += 1;
        continue;
      }
      if (i + 1 < bytes.length) {
        final code = gbkLookup(b, bytes[i + 1]);
        if (code != null) {
          buf.writeCharCode(code);
          i += 2;
          continue;
        }
      }
      buf.write('\uFFFD');
      i += 1;
    }
    return buf.toString();
  }

  static String _decodeUtf16(Uint8List bytes,
      {required bool littleEndian}) {
    final len = bytes.length ~/ 2;
    final units = Uint16List(len);
    for (var i = 0; i < len; i++) {
      final a = bytes[i * 2];
      final b = bytes[i * 2 + 1];
      units[i] = littleEndian ? (b << 8) | a : (a << 8) | b;
    }
    return String.fromCharCodes(units);
  }

  /// 无 BOM 时靠 0x00 分布判断 UTF-16;不像则返回 null。
  static String? _sniffUtf16(Uint8List bytes) {
    final n = bytes.length < 400 ? bytes.length : 400;
    if (n < 4) return null;
    var evenZero = 0;
    var oddZero = 0;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) {
        if (i.isEven) {
          evenZero++;
        } else {
          oddZero++;
        }
      }
    }
    final half = n / 2;
    if (oddZero > half * 0.7 && evenZero < half * 0.2) {
      return _decodeUtf16(bytes, littleEndian: true);
    }
    if (evenZero > half * 0.7 && oddZero < half * 0.2) {
      return _decodeUtf16(bytes, littleEndian: false);
    }
    return null;
  }

  static String _head(String text, int n) =>
      text.length <= n ? text : text.substring(0, n);

  /// 从正文开头猜书名(《XXX》),猜不到返回 null。
  static String? _guessTitle(String text) {
    final head = _head(text, 2000);
    final m = RegExp(r'《([^》]{1,40})》').firstMatch(head);
    return m?.group(1)?.trim();
  }

  /// 按章节标题切分;无法识别时按长度兜底分节。
  static List<Chapter> splitChapters(String text, {required String bookTitle}) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u0000', '');

    final matches = _headingRe.allMatches(normalized).toList();
    if (matches.length >= 2) {
      final chapters = <Chapter>[];
      // 第一个标题之前的内容作为前言(内容太短则丢弃,通常只是书名/作者页)
      final preface = normalized.substring(0, matches.first.start).trim();
      if (preface.length >= 60) {
        chapters.add(Chapter(title: '前言', content: _tidy(preface)));
      }
      for (var i = 0; i < matches.length; i++) {
        final title = matches[i].group(1)!.trim();
        final start = matches[i].end;
        final end = i + 1 < matches.length ? matches[i + 1].start : normalized.length;
        final body = _tidy(normalized.substring(start, end));
        if (body.isEmpty) continue;
        chapters.add(Chapter(title: title, content: body));
      }
      if (chapters.isNotEmpty) return chapters;
    }

    // 兜底:按段落累积到目标字数切一节
    final paragraphs = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return const [];

    final chapters = <Chapter>[];
    var buf = StringBuffer();
    var idx = 0;
    void flush() {
      final body = buf.toString().trim();
      buf = StringBuffer();
      if (body.isEmpty) return;
      idx += 1;
      chapters.add(Chapter(title: '第 $idx 节', content: body));
    }

    for (final para in paragraphs) {
      buf.writeln(para);
      if (buf.length >= _fallbackChunkSize) flush();
    }
    flush();
    return chapters;
  }

  /// 压缩连续空行,去掉首尾空白。
  static String _tidy(String s) {
    return s
        .replaceAll(RegExp(r'[ \t\u3000]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
