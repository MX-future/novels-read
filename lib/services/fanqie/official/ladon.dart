// X-Ladon / X-Helios 签名。
//
// 明文固定为 "<khronos>-<licenseId>-3019"（3019 是二进制里写死的常量，
// 不是 aid），密钥由 md5(随机4字节 || str(aid)) 派生，34 轮 Feistel 式
// 混合，输出 base64(随机4字节 || 密文)。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'crypto.dart';

const int _aid = 1967;
const int _licenseId = 1611921764;
const String _saltTail = '3019';

int _ror64(int v, int n) => (v << (64 - n)) | (v >>> n);

/// 生成 34 张 64 位轮表：前 32 字节放 md5，其余由递推填充。
Int64List _buildHashTable(Uint8List md5hex) {
  final table = ByteData(272 + 16);
  final bytes = table.buffer.asUint8List();
  bytes.setRange(0, 32, md5hex);

  var b0 = table.getUint64(0, Endian.little);
  var b8 = table.getUint64(8, Endian.little);
  final temp = <int>[
    table.getUint64(16, Endian.little),
    table.getUint64(24, Endian.little),
  ];

  for (var i = 0; i < 0x22; i++) {
    final x9 = b0;
    var x8 = b8;
    x8 = _ror64(x8, 8);
    x8 = x8 + x9;
    x8 = x8 ^ i;
    temp.add(x8);
    x8 = x8 ^ _ror64(x9, 61);
    table.setUint64((i + 1) * 8, x8, Endian.little);
    b0 = x8;
    b8 = temp.removeAt(0);
  }

  final out = Int64List(0x22);
  for (var i = 0; i < 0x22; i++) {
    out[i] = table.getUint64(i * 8, Endian.little);
  }
  return out;
}

Uint8List _encryptBlock(Int64List table, Uint8List block) {
  final bd = ByteData.sublistView(block);
  var d0 = bd.getUint64(0, Endian.little);
  var d1 = bd.getUint64(8, Endian.little);

  for (var i = 0; i < 0x22; i++) {
    d1 = table[i] ^ (d0 + _ror64(d1, 8));
    d0 = d1 ^ _ror64(d0, 61);
  }

  final out = Uint8List(16);
  final obd = ByteData.sublistView(out);
  obd.setUint64(0, d0, Endian.little);
  obd.setUint64(8, d1, Endian.little);
  return out;
}

/// 对 [data] 做 16 字节对齐填充后按 Ladon 混合，返回密文。
Uint8List _encryptLadon(Uint8List md5hex, Uint8List data) {
  final table = _buildHashTable(md5hex);

  // padding_size(): 已对齐时不再补块（参考实现的行为，非标准 PKCS#7）
  final mod = data.length % 16;
  final newSize = mod == 0 ? data.length : data.length + (16 - mod);
  final input = Uint8List(newSize)..setRange(0, data.length, data);
  if (newSize > data.length) {
    // pkcs7_padding_pad_buffer：尾部填 pad 字节数
    final padByte = newSize - data.length;
    for (var i = data.length; i < newSize; i++) {
      input[i] = padByte;
    }
  }

  final out = Uint8List(newSize);
  for (var off = 0; off < newSize; off += 16) {
    out.setRange(off, off + 16,
        _encryptBlock(table, Uint8List.sublistView(input, off, off + 16)));
  }
  return out;
}

/// 生成 X-Ladon 头。[randomBytes] 可注入以便测试复现。
String makeLadon(
  int khronos, {
  int aid = _aid,
  int licenseId = _licenseId,
  Uint8List? randomBytes,
}) {
  final rb = randomBytes ?? _random4();
  final data = utf8.encode('$khronos-$licenseId-$_saltTail');
  final keygen = Uint8List.fromList([...rb, ...utf8.encode('$aid')]);
  final md5hex = utf8.encode(_hex(md5(keygen)));

  final body = _encryptLadon(
      Uint8List.fromList(md5hex), Uint8List.fromList(data));

  final out = BytesBuilder()
    ..add(rb)
    ..add(body);
  return base64.encode(out.toBytes());
}

Uint8List _random4() {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(4, (_) => r.nextInt(256)));
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 仅供单元测试：用固定随机数复现，并与 Python 侧对拍。
class LadonDebug {
  static Uint8List encryptLadon(Uint8List md5hex, Uint8List data) =>
      _encryptLadon(md5hex, data);
}
