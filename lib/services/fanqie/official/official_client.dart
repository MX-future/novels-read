// 番茄 App 通道客户端（官方协议，2026-10-28 全链路验证通过）。
//
// 链路：
//   device_register  -> 自建 device_id / install_id（服务端按 cdid 分配身份）
//   registerkey      -> data.key（b64: IV16 || AES-128-CBC(固定密钥, pkcs7(seed))）
//   seed             -> 16 字节，直接作正文 AES-128 的 key（无 KDF）
//   batch_full       -> item.content（b64: IV16 || AES-128-CBC(seed, pkcs7(gzip(xhtml)))）
//   gunzip           -> XHTML 正文
//
// 与 web 通道相比，这条通道解锁 VIP 章节（web 匿名只给 ~200 字试读）。
// 全部密码学原语为本项目纯 Dart 实现，见 crypto.dart / sm3.dart / simon.dart /
// argus.dart / ladon.dart，不引入新依赖。
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../fanqie_map.dart';
import 'argus.dart';
import 'crypto.dart';
import 'ladon.dart';

/// 番茄 App 通道网关。
const String fanqieBase = 'https://api5-normal-sinfonlinec.fqnovel.com';

/// 番茄 App 的 aid（与签名 bean 里的 msAppID 一致）。
const int fanqieAid = 1967;

/// 注册密钥（32 位 hex，硬编码在二进制 .rodata，用于 registerkey 双向加解密）。
final Uint8List fanqieRegisterKey =
    Uint8List.fromList(_hexToBytes('ac25c67ddd8f38c1b37a2348828e222e'));

const String fanqieUserAgent =
    'com.dragon.read/72332 (Linux; U; Android 11; zh_CN; MI 9; '
    'Build/RKQ1.200826.002; Cronet/TTNetVersion:c9c2b6a0 2026-05-21)';

const String _deviceRegisterUrl = 'https://log.snssdk.com/service/2/device_register/';

const String _deviceRegisterUa =
    'com.dragon.read/72332 (Linux; U; Android 11; zh_CN; MI 9; '
    'Build/RKQ1.200826.002; Cronet/TTNetVersion:06fd67e6 2022-11-16)';

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 标准 v4 UUID 字符串（device_register 的 cdid 取值形态）。
String _uuidV4(Random rand) {
  final bytes = Uint8List.fromList(List<int>.generate(16, (_) => rand.nextInt(256)));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// 严格等价于 Python `urllib.parse.quote(v, safe='')`：只保留
/// `A-Za-z0-9-_.~`，其余全部百分号编码。
///
/// 不能用 [Uri.encodeComponent]：它会放过 `!*'()`，与参考实现不一致
/// （例如 `resolution=1280*720` 会被它原样输出）。虽然服务端两边都能解码，
/// 但签名用的是同一份 qs，保持一致可以少一层不确定性。
String _quote(String value) {
  const hex = '0123456789ABCDEF';
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final ok = (byte >= 0x30 && byte <= 0x39) || // 0-9
        (byte >= 0x41 && byte <= 0x5A) || // A-Z
        (byte >= 0x61 && byte <= 0x7A) || // a-z
        byte == 0x2D || // -
        byte == 0x2E || // .
        byte == 0x5F || // _
        byte == 0x7E; // ~
    if (ok) {
      out.writeCharCode(byte);
    } else {
      out.write('%${hex[byte >> 4]}${hex[byte & 0x0F]}');
    }
  }
  return out.toString();
}

/// 把 `key=value` 列表拼成 query string（value 一律严格 quote）。
String _buildQuery(List<String> params) {
  return params.map((p) {
    final i = p.indexOf('=');
    if (i < 0) return p;
    return '${p.substring(0, i)}=${_quote(p.substring(i + 1))}';
  }).join('&');
}

/// 设备身份。`deviceId` 是 registerkey 唯一校验的字段；`cdid` 决定服务端把
/// 新注册归到哪个身份上，因此每台设备/每次自建都应重新生成。
class FanqieDeviceProfile {
  final String deviceId;
  final String installId;
  final String cdid;
  final String openudid;
  final String deviceType;
  final String deviceBrand;
  final String osVersion;
  final String osApi;
  final String versionCode;
  final String versionName;
  final String channel;
  final String hostAbi;
  final String resolution;
  final String dpi;
  final String romVersion;

  const FanqieDeviceProfile({
    required this.deviceId,
    required this.installId,
    this.cdid = '',
    this.openudid = '',
    this.deviceType = 'MI 9',
    this.deviceBrand = 'Xiaomi',
    this.osVersion = '11',
    this.osApi = '29',
    this.versionCode = '72332',
    this.versionName = '7.2.3.32',
    this.channel = '43536163a',
    this.hostAbi = 'armeabi-v7a',
    this.resolution = '1280*720',
    this.dpi = '240',
    this.romVersion = 'L8E1.226024.33956602+release-keys',
  });

  /// 尚未注册时的占位身份。
  static const FanqieDeviceProfile empty = FanqieDeviceProfile(
    deviceId: '0',
    installId: '0',
  );

  bool get isEmpty => deviceId.isEmpty || deviceId == '0';

  FanqieDeviceProfile copyWith({
    String? deviceId,
    String? installId,
    String? cdid,
    String? openudid,
  }) {
    return FanqieDeviceProfile(
      deviceId: deviceId ?? this.deviceId,
      installId: installId ?? this.installId,
      cdid: cdid ?? this.cdid,
      openudid: openudid ?? this.openudid,
      deviceType: deviceType,
      deviceBrand: deviceBrand,
      osVersion: osVersion,
      osApi: osApi,
      versionCode: versionCode,
      versionName: versionName,
      channel: channel,
      hostAbi: hostAbi,
      resolution: resolution,
      dpi: dpi,
      romVersion: romVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'install_id': installId,
        'cdid': cdid,
        'openudid': openudid,
        'device_type': deviceType,
        'device_brand': deviceBrand,
        'os_version': osVersion,
        'os_api': osApi,
        'version_code': versionCode,
        'version_name': versionName,
        'channel': channel,
        'host_abi': hostAbi,
        'resolution': resolution,
        'dpi': dpi,
        'rom_version': romVersion,
      };

  factory FanqieDeviceProfile.fromJson(Map<String, dynamic> json) {
    String s(String k, String d) => json[k]?.toString() ?? d;
    return FanqieDeviceProfile(
      deviceId: s('device_id', '0'),
      installId: s('install_id', '0'),
      cdid: s('cdid', ''),
      openudid: s('openudid', ''),
      deviceType: s('device_type', 'MI 9'),
      deviceBrand: s('device_brand', 'Xiaomi'),
      osVersion: s('os_version', '11'),
      osApi: s('os_api', '29'),
      versionCode: s('version_code', '72332'),
      versionName: s('version_name', '7.2.3.32'),
      channel: s('channel', '43536163a'),
      hostAbi: s('host_abi', 'armeabi-v7a'),
      resolution: s('resolution', '1280*720'),
      dpi: s('dpi', '240'),
      romVersion: s('rom_version', ''),
    );
  }

  /// 向 `log.snssdk.com` 注册一台"新设备"，返回服务端分配的 device_id。
  ///
  /// 请求体只有三键：`magic_tag` / `header`(22 字段) / `_gen_time`；体内不含
  /// device_id，由服务端分配。cdid 若复用，服务端会返回同一台设备，
  /// 所以每次调用都生成新的 cdid + openudid。
  static Future<FanqieDeviceProfile> provision({
    FanqieDeviceProfile? template,
    http.Client? client,
  }) async {
    final base = template ?? empty;
    final rand = Random.secure();
    final cdid = _uuidV4(rand);
    final openudid = List.generate(16, (_) => rand.nextInt(16).toRadixString(16))
        .join();
    final now = DateTime.now().millisecondsSinceEpoch;

    final header = <String, dynamic>{
      'display_name': base.deviceType,
      'update_version_code': int.tryParse(base.versionCode) ?? 72332,
      'manifest_version_code': int.tryParse(base.versionCode) ?? 72332,
      'aid': fanqieAid,
      'channel': base.channel,
      'package': 'com.dragon.read',
      'app_name': 'novel',
      'version_code': int.tryParse(base.versionCode) ?? 72332,
      'version_name': base.versionName,
      'device_model': base.deviceType,
      'device_brand': base.deviceBrand,
      'device_manufacturer': base.deviceBrand,
      'os_version': base.osVersion,
      'os_api': int.tryParse(base.osApi) ?? 29,
      'device_platform': 'android',
      'language': 'zh',
      'region': 'CN',
      'resolution': base.resolution,
      'dpi': int.tryParse(base.dpi) ?? 240,
      'rom_version': base.romVersion,
      'cdid': cdid,
      'openudid': openudid,
    };
    final body = jsonEncode({
      'magic_tag': 'ss_app_log',
      'header': header,
      '_gen_time': now,
    });

    final qs = _buildQuery([
      'aid=$fanqieAid',
      'app_name=novel',
      'device_platform=android',
      'os_version=${base.osVersion}',
      'os_api=${base.osApi}',
      'channel=${base.channel}',
      'device_type=${base.deviceType}',
      'device_brand=${base.deviceBrand}',
    ]);

    final client0 = client ?? http.Client();
    try {
      final resp = await client0
          .post(
            Uri.parse('$_deviceRegisterUrl?$qs'),
            headers: {
              'User-Agent': _deviceRegisterUa,
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: utf8.encode(body),
          )
          .timeout(const Duration(seconds: 25));
      final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw FanqieOfficialException('device_register 返回异常：$text');
      }
      final did = decoded['device_id']?.toString() ?? '';
      final iid = decoded['install_id']?.toString() ?? '';
      if (did.isEmpty || iid.isEmpty || did == '0') {
        throw FanqieOfficialException('device_register 未返回身份：$text');
      }
      return base.copyWith(
        deviceId: did,
        installId: iid,
        cdid: cdid,
        openudid: openudid,
      );
    } finally {
      if (client == null) client0.close();
    }
  }
}

/// 官方通道异常。[code] 为业务 code（如 500002 verify fail）。
class FanqieOfficialException implements Exception {
  final String message;
  final int? code;

  const FanqieOfficialException(this.message, {this.code});

  @override
  String toString() => 'FanqieOfficialException($message${code == null ? '' : ', code=$code'})';
}

/// 单章正文结果。
class FanqieOfficialChapter {
  final String itemId;
  final String title;

  /// 已清洗为带段落换行的纯文本（VIP 章节同样有全文）。
  final String text;

  /// 失败原因；成功时为 null。
  final String? error;

  const FanqieOfficialChapter({
    required this.itemId,
    required this.title,
    required this.text,
    this.error,
  });

  bool get ok => text.trim().isNotEmpty;
}

/// 番茄官方（App 通道）客户端。
///
/// 典型用法：
/// ```dart
/// final client = await FanqieOfficialClient.create();   // 无身份时自动注册
/// await client.register();                             // 取 seed
/// final items = await client.directory(bookId);
/// final ch = await client.chapter(items.first['item_id']);
/// ```
class FanqieOfficialClient {
  FanqieDeviceProfile profile;
  final http.Client _http;

  Uint8List? _seed;
  int _keyTs = 0;

  FanqieOfficialClient({
    required this.profile,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// seed 是否已取到。
  bool get hasSeed => _seed != null;

  /// 已注册设备身份 + 已取到 seed 的客户端。
  static Future<FanqieOfficialClient> create({
    FanqieDeviceProfile? profile,
    http.Client? httpClient,
  }) async {
    final client = FanqieOfficialClient(
      profile: profile ?? FanqieDeviceProfile.empty,
      httpClient: httpClient,
    );
    await client.register();
    return client;
  }

  void close() => _http.close();

  // ------------------------------------------------------------- 请求基础设施

  /// 公共业务参数（顺序与参考实现逐项一致，便于对拍）。
  List<String> _common() {
    final p = profile;
    return [
      'aid=$fanqieAid',
      'app_name=novel',
      'device_platform=android',
      'os_api=${p.osApi}',
      'os_version=${p.osVersion}',
      'version_code=${p.versionCode}',
      'version_name=${p.versionName}',
      'iid=${p.installId}',
      'device_id=${p.deviceId}',
      'cdid=${p.cdid}',
      'channel=${p.channel}',
      'host_abi=${p.hostAbi}',
      'resolution=${p.resolution}',
      'dpi=${p.dpi}',
      'rom_version=${p.romVersion}',
      'device_type=${p.deviceType}',
      'device_brand=${p.deviceBrand}',
      'manifest_version_code=${p.versionCode}',
      'is_android_pad_screen=1',
      'sdk-version=2',
      'passport-sdk-version=v04.04.05-ov-android',
      'x-tt-store-region=50564',
      'x-tt-store-region-src=cn-zj',
      'x-vc-bdturing-sdk-version=v04.04.05-ov-android',
      'use_correct=1',
      'group_id=0',
      'applanguage_rticket=zh-CN',
      'compliance_status=0',
      'screen_brightness=100',
      'battery_pct=100',
      'cold_start_session_id=0',
    ];
  }

  Map<String, String> _headers(String qs, Uint8List? body) {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final h = <String, String>{
      'User-Agent': fanqieUserAgent,
      'Accept-Encoding': 'gzip',
      'Accept': 'application/json; charset=utf-8',
      'Authorization': '',
      'X-Argus': makeArgus(qs, body: body),
      'X-Ladon': makeLadon(ts),
      'X-Helios': makeLadon(ts),
      'X-Khronos': '$ts',
      'x-ss-req-ticket': '${ts * 1000}',
      'x-tt-store-region': '50564',
      'x-tt-store-region-src': 'cn-zj',
      'x-reading-request': '1',
      'x-xs-from-web': '0',
      'x-vc-bdturing-sdk-version': 'v04.04.05-ov-android',
      'sdk-version': '2',
      'passport-sdk-version': 'v04.04.05-ov-android',
    };
    if (body != null && body.isNotEmpty) {
      h['Content-Type'] = 'application/json';
    }
    return h;
  }

  /// 发一次签名请求，返回原始响应字节（自动解 gzip）。
  Future<Uint8List> _request(
    String path,
    List<String> params, {
    String method = 'GET',
    Uint8List? body,
  }) async {
    final qs = _buildQuery(params);
    final uri = Uri.parse('$fanqieBase$path?$qs');
    final headers = _headers(qs, body);

    final http.Response resp;
    if (method == 'POST') {
      resp = await _http
          .post(uri, headers: headers, body: body ?? Uint8List(0))
          .timeout(const Duration(seconds: 25));
    } else {
      resp = await _http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    }

    var raw = resp.bodyBytes;
    if (raw.length >= 2 && raw[0] == 0x1F && raw[1] == 0x8B) {
      raw = Uint8List.fromList(GZipDecoder().decodeBytes(raw));
    }
    return raw;
  }

  Map<String, dynamic> _decodeJson(Uint8List raw, {required String stage}) {
    if (raw.isEmpty) {
      throw FanqieOfficialException('$stage 返回空 body');
    }
    final text = utf8.decode(raw, allowMalformed: true);
    try {
      final d = jsonDecode(text);
      if (d is Map<String, dynamic>) return d;
      throw FanqieOfficialException('$stage 返回非对象：$text');
    } on FormatException {
      throw FanqieOfficialException('$stage 返回非 JSON：${text.substring(0, min(200, text.length))}');
    }
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  // ------------------------------------------------------------ 1. 设备 / seed

  /// 确保有 device_id：没有就现场注册一台新设备。
  Future<void> ensureIdentity() async {
    if (profile.isEmpty) {
      profile = await FanqieDeviceProfile.provision(template: profile);
    }
  }

  /// 取 seed（正文解密密钥）。有效期约 30 分钟，过期后重新调用即可。
  Future<void> register() async {
    await ensureIdentity();

    // 明文 = LE64(device_id) || 8 x 0x00 —— 不是时间戳。
    final plain = Uint8List(16);
    ByteData.sublistView(plain).setUint64(
      0,
      int.parse(profile.deviceId),
      Endian.little,
    );
    final iv = _randomBytes(16);
    final ct = Aes128(fanqieRegisterKey).cbcEncrypt(plain, iv);
    final content = base64.encode(Uint8List.fromList([...iv, ...ct]));
    final body = Uint8List.fromList(
      utf8.encode(jsonEncode({'content': content, 'keyver': 1})),
    );

    final raw = await _request(
      '/reading/crypt/registerkey',
      _common(),
      method: 'POST',
      body: body,
    );
    final json = _decodeJson(raw, stage: 'registerkey');
    final code = json['code'] is int ? json['code'] as int : -1;
    if (code != 0) {
      throw FanqieOfficialException(
        'registerkey 失败：${json['message'] ?? raw.length}',
        code: code,
      );
    }

    final data = json['data'];
    if (data is! Map) {
      throw FanqieOfficialException('registerkey 未返回 data');
    }
    final blob = base64.decode(data['key'].toString());
    if (blob.length < 32) {
      throw FanqieOfficialException('registerkey key 长度异常：${blob.length}');
    }
    final seed = Aes128(fanqieRegisterKey)
        .cbcDecrypt(blob.sublist(16), blob.sublist(0, 16));
    if (seed.length != 16) {
      throw FanqieOfficialException('seed 长度异常：${seed.length}');
    }
    _seed = Uint8List.fromList(seed);
    _keyTs = DateTime.now().millisecondsSinceEpoch;
  }

  /// seed 超过 [maxAge] 视为过期（默认 25 分钟，服务端约 30 分钟）。
  Future<void> _ensureSeed([Duration maxAge = const Duration(minutes: 25)]) async {
    final age = DateTime.now().millisecondsSinceEpoch - _keyTs;
    if (_seed == null || age > maxAge.inMilliseconds) {
      await register();
    }
  }

  // ------------------------------------------------------------ 2. 书籍元信息

  /// 书籍详情（书名/作者/字数/连载状态/封面）。
  Future<Map<String, dynamic>> detail(String bookId) async {
    final raw = await _request(
      '/reading/bookapi/detail/v',
      ['book_id=$bookId', ..._common()],
    );
    final json = _decodeJson(raw, stage: 'detail');
    final data = json['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// 完整目录（含 VIP 章节），返回 `item_data_list`。
  Future<List<Map<String, dynamic>>> directory(String bookId) async {
    final raw = await _request(
      '/reading/bookapi/directory/all_items/v',
      ['book_id=$bookId', ..._common()],
    );
    final json = _decodeJson(raw, stage: 'directory');
    final data = json['data'];
    if (data is! Map) return const [];
    final list = data['item_data_list'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  // ------------------------------------------------------------ 3. 正文

  /// 批量取正文原始 JSON（[itemIds] 建议 ≤ 5，单条最稳）。
  Future<Map<String, dynamic>> _batch(String bookId, List<String> itemIds) async {
    final raw = await _request(
      '/reading/reader/batch_full/v',
      [
        'item_ids=${itemIds.join(',')}',
        'req_type=1',
        'book_id=$bookId',
        'key_register_ts=$_keyTs',
        'compress_status=2',
        'update_version_code=${profile.versionCode}',
        'device_platform=android',
        'from_rs=1',
        'groupId=0',
        'key_len=16',
        ..._common(),
      ],
    );
    // 0 字节 body = 滑动窗口软限流（HTTP 仍是 200），由调用方退避重试。
    if (raw.isEmpty) {
      throw FanqieOfficialException('batch_full 空 body（限流）');
    }
    final json = _decodeJson(raw, stage: 'batch_full');
    final data = json['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// 取单章正文。
  Future<FanqieOfficialChapter> chapter(String bookId, String itemId) async {
    await _ensureSeed();
    final data = await _batch(bookId, [itemId]);
    final one = (data[itemId] is Map)
        ? (data[itemId] as Map).cast<String, dynamic>()
        : (data.isNotEmpty && data.values.first is Map)
            ? (data.values.first as Map).cast<String, dynamic>()
            : <String, dynamic>{};
    final title = one['title']?.toString() ?? '';
    final content = one['content']?.toString() ?? '';
    if (content.isEmpty) {
      return FanqieOfficialChapter(
        itemId: itemId,
        title: title,
        text: '',
        error: one['message']?.toString() ?? 'empty',
      );
    }
    try {
      final xhtml = rawXhtml(content);
      return FanqieOfficialChapter(
        itemId: itemId,
        title: title,
        text: FanqieMap.decodeChapterHtml(xhtml),
      );
    } catch (e) {
      return FanqieOfficialChapter(
        itemId: itemId,
        title: title,
        text: '',
        error: '解密失败：$e',
      );
    }
  }

  /// 解密 + 解压，还原出章节 XHTML。
  ///
  /// `compress_status`：1=gzip，2=zlib，3=zstd，0=不压缩；实测均为 1，
  /// 这里按 gzip / zlib / raw-deflate 依次尝试，失败则当明文处理。
  String rawXhtml(String contentB64) {
    final seed = _seed;
    if (seed == null) {
      throw FanqieOfficialException('尚未取得 seed，请先 register()');
    }
    final blob = base64.decode(contentB64);
    if (blob.length < 32) {
      throw FanqieOfficialException('正文密文过短：${blob.length}');
    }
    final iv = blob.sublist(0, 16);
    final cipher = blob.sublist(16);
    final plain = Aes128(seed).cbcDecrypt(cipher, iv);

    Uint8List body = Uint8List.fromList(plain);
    try {
      if (body.length > 2 && body[0] == 0x1F && body[1] == 0x8B) {
        body = Uint8List.fromList(GZipDecoder().decodeBytes(body));
      } else if (body.length > 2 && body[0] == 0x78) {
        body = Uint8List.fromList(ZLibDecoder().decodeBytes(body));
      } else {
        // 裸 deflate 兜底（无 zlib 头）
        body = Uint8List.fromList(
          Inflate.buffer(InputStream(body)).getBytes(),
        );
      }
    } catch (_) {
      // 未压缩（compress_status=0）：原样当 UTF-8
    }
    return utf8.decode(body, allowMalformed: true);
  }
}
