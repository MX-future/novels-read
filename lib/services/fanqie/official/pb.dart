// 极简 protobuf 写入器，只覆盖 X-Argus 用到的四种取值：
//   int          -> varint
//   String       -> length-delimited(utf8)
//   List<int>    -> length-delimited(bytes)
//   Map<int,...> -> length-delimited(嵌套 message)
// 字段按 key 升序输出（与参考实现一致），保证逐字节可复现。
import 'dart:convert';
import 'dart:typed_data';

void _writeVarint(BytesBuilder out, int value) {
  var v = value;
  // 负数按 64 位补码发 10 字节，与 protobuf 规范一致
  if (v < 0) {
    for (var i = 0; i < 9; i++) {
      out.addByte((v & 0x7F) | 0x80);
      v = v >>> 7;
    }
    out.addByte(v & 0x7F);
    return;
  }
  while (v >= 0x80) {
    out.addByte((v & 0x7F) | 0x80);
    v = v >>> 7;
  }
  out.addByte(v);
}

void _writeTag(BytesBuilder out, int field, int wireType) {
  _writeVarint(out, (field << 3) | wireType);
}

void _writeBytesField(BytesBuilder out, int field, List<int> data) {
  _writeTag(out, field, 2);
  _writeVarint(out, data.length);
  out.add(data);
}

/// 编码一个 message。
Uint8List pbEncode(Map<int, dynamic> fields) {
  final out = BytesBuilder();
  final keys = fields.keys.toList()..sort();
  for (final k in keys) {
    final v = fields[k];
    if (v == null) continue;
    if (v is Map<int, dynamic>) {
      _writeBytesField(out, k, pbEncode(v));
    } else if (v is String) {
      _writeBytesField(out, k, utf8.encode(v));
    } else if (v is Uint8List) {
      _writeBytesField(out, k, v);
    } else if (v is List<int>) {
      _writeBytesField(out, k, v);
    } else if (v is bool) {
      _writeTag(out, k, 0);
      _writeVarint(out, v ? 1 : 0);
    } else if (v is num) {
      _writeTag(out, k, 0);
      _writeVarint(out, v.toInt());
    } else {
      throw ArgumentError('unsupported protobuf value type: ${v.runtimeType}');
    }
  }
  return out.toBytes();
}
