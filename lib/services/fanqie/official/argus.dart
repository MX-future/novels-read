// X-Argus 签名（番茄/TikTok 系）。流程：
//   protobuf 编码 -> PKCS#7 -> SIMON-72 分组加密 -> 首 8 字节异或 + 整体反转
//   -> 前缀/后缀拼接 -> AES-128-CBC(md5(key16) 作 key, md5(key[16:]) 作 IV)
//   -> base64
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'crypto.dart';
import 'pb.dart';
import 'simon.dart';
import 'sm3.dart';

/// 固定签名密钥（32 字节），从二进制 .rodata 提取。
final Uint8List _signKey = Uint8List.fromList(const [
  0xac, 0x1a, 0xda, 0xae, 0x95, 0xa7, 0xaf, 0x94,
  0xa5, 0x11, 0x4a, 0xb3, 0xb3, 0xa9, 0x7d, 0xd8,
  0x00, 0x50, 0xaa, 0x0a, 0x39, 0x31, 0x4c, 0x40,
  0x52, 0x8c, 0xae, 0xc9, 0x52, 0x56, 0xc2, 0x8c,
]);

const int _licenseId = 1611921764;
const String _sdkVersionStr = 'v04.04.05-ov-android';
const int _sdkVersionInt = 134744640; // '0x08080A40'

/// sm3(sign_key || f2 81 61 6f || sign_key)[0:32] —— 参考实现里的常量，
/// 这里运行时算出（并可由单元测试与常量比对）。
late final Uint8List _sm3Output = () {
  final buf = BytesBuilder()
    ..add(_signKey)
    ..add(const [0xf2, 0x81, 0x61, 0x6f])
    ..add(_signKey);
  return sm3(buf.toBytes());
}();

/// 首 8 字节异或后整体反转。
Uint8List _xorAndReverse(Uint8List data, int length) {
  final out = Uint8List.fromList(data);
  final key = Uint8List.fromList(out.sublist(0, 8));
  for (var i = 8; i < length; i++) {
    out[i] ^= key[i % 8];
  }
  return Uint8List.fromList(out.reversed.toList());
}

int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

/// 加密封装：bean 为 protobuf 字段表，返回 base64 字符串。
String argusEncrypt(Map<int, dynamic> bean) {
  final protobuf = pkcs7Pad(pbEncode(bean), 16);
  final newLen = protobuf.length;

  final key = Uint8List.fromList(_sm3Output.sublist(0, 32));
  final kbd = ByteData.sublistView(key);
  final keyWords = <int>[
    kbd.getUint64(0, Endian.little),
    kbd.getUint64(8, Endian.little),
    kbd.getUint64(16, Endian.little),
    kbd.getUint64(24, Endian.little),
  ];

  final encPb = simonEncryptBytes(protobuf, keyWords, rounds: 72);

  final pre = Uint8List(8 + newLen);
  pre.setRange(0, 8, const [0xf2, 0xf7, 0xfc, 0xff, 0xf2, 0xf7, 0xfc, 0xff]);
  pre.setRange(8, 8 + newLen, encPb);
  final scrambled = _xorAndReverse(pre, newLen + 8);

  final buffer = BytesBuilder()
    ..add(const [0xa6, 0x6e, 0xad, 0x9f, 0x77, 0x01, 0xd0, 0x0c, 0x18])
    ..add(scrambled)
    ..add(const [0x61, 0x6f]);

  final cipher = Aes128(md5(_signKey.sublist(0, 16)));
  final ct = cipher.cbcEncrypt(buffer.toBytes(), md5(_signKey.sublist(16, 32)));

  final out = BytesBuilder()
    ..add(const [0xf2, 0x81])
    ..add(ct);
  return base64.encode(out.toBytes());
}

Uint8List _bodyHash(Uint8List body) {
  // 参考实现：body 为空 -> sm3(16 个 0 字节)；非空 -> sm3(md5(body))
  final input = body.isEmpty ? Uint8List(16) : md5(body);
  return Uint8List.fromList(sm3(input).sublist(0, 6));
}

Uint8List _queryHash(String query) {
  final input = query.isEmpty ? Uint8List(16) : Uint8List.fromList(utf8.encode(query));
  return Uint8List.fromList(sm3(input).sublist(0, 6));
}

/// 从 query string 取参数（取第一个值），等价于 Python 的 parse_qs。
Map<String, String> _parseQuery(String query) {
  final map = <String, String>{};
  for (final part in query.split('&')) {
    if (part.isEmpty) continue;
    final i = part.indexOf('=');
    if (i < 0) continue;
    final k = part.substring(0, i);
    final v = Uri.decodeQueryComponent(part.substring(i + 1));
    map.putIfAbsent(k, () => v);
  }
  return map;
}

/// 生成 X-Argus 头。
///
/// [query] 为完整 query string（不含 '?'），[body] 传空表示用 nil body 签名
/// （registerkey 与 batch_full 都是这样）。
String makeArgus(
  String query, {
  Uint8List? body,
  int? aid,
  int? timestamp,
  int? licenseId,
  String sdkVersion = _sdkVersionStr,
  int sdkVersionInt = _sdkVersionInt,
  int platform = 0,
  String secDeviceId = '',
}) {
  final params = _parseQuery(query);
  final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final rand = Random().nextInt(0x7FFFFFFF);

  return argusEncrypt({
    1: 0x20200929 << 1,
    2: 2,
    3: rand,
    4: '${aid ?? 1967}',
    5: params['device_id'] ?? '',
    6: '${licenseId ?? _licenseId}',
    7: params['version_name'] ?? '',
    8: sdkVersion,
    9: sdkVersionInt,
    10: Uint8List(8),
    11: platform,
    12: ts << 1,
    13: _bodyHash(body ?? Uint8List(0)),
    14: _queryHash(query),
    15: {1: 1, 2: 1, 3: 1, 7: 3348294860},
    16: secDeviceId,
    20: 'none',
    21: 738,
    23: {1: 'NX551J', 2: 8196, 4: 2162219008},
    25: 2,
  });
}

/// 仅供单元测试：暴露中间量做对拍。
class ArgusDebug {
  static Uint8List get signKey => _signKey;
  static Uint8List get sm3Output => Uint8List.fromList(_sm3Output);
  static Uint8List bodyHash(Uint8List b) => _bodyHash(b);
  static Uint8List queryHash(String q) => _queryHash(q);
  static int rotl32(int x, int n) => _rotl32(x, n);
}
