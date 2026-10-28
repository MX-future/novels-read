// 国密 SM3 摘要（纯 Dart）。番茄用它算 X-Argus 的 bodyHash / queryHash。
import 'dart:typed_data';

int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

int _p0(int x) => (x ^ _rotl32(x, 9) ^ _rotl32(x, 17)) & 0xFFFFFFFF;
int _p1(int x) => (x ^ _rotl32(x, 15) ^ _rotl32(x, 23)) & 0xFFFFFFFF;

int _ff(int j, int x, int y, int z) =>
    j < 16 ? (x ^ y ^ z) : ((x & y) | (x & z) | (y & z));
int _gg(int j, int x, int y, int z) =>
    j < 16 ? (x ^ y ^ z) : ((x & y) | (~x & z) & 0xFFFFFFFF);

const List<int> _iv = [
  0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
  0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
];

/// 返回 32 字节摘要。
Uint8List sm3(List<int> input) {
  final data = Uint8List.fromList(input);
  final bitLen = data.length * 8;
  var padLen = 64 - ((data.length + 9) % 64);
  if (padLen == 64) padLen = 0;
  final buf = Uint8List(data.length + 1 + padLen + 8);
  buf.setRange(0, data.length, data);
  buf[data.length] = 0x80;
  final bd = ByteData.sublistView(buf);
  bd.setUint32(buf.length - 8, (bitLen ~/ 0x100000000) & 0xFFFFFFFF, Endian.big);
  bd.setUint32(buf.length - 4, bitLen & 0xFFFFFFFF, Endian.big);

  final v = List<int>.from(_iv);
  final w = List<int>.filled(68, 0);
  final w1 = List<int>.filled(64, 0);

  for (var off = 0; off < buf.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(off + i * 4, Endian.big);
    }
    for (var j = 16; j < 68; j++) {
      final x = w[j - 16] ^ w[j - 9] ^ _rotl32(w[j - 3], 15);
      w[j] = (_p1(x) ^ _rotl32(w[j - 13], 7) ^ w[j - 6]) & 0xFFFFFFFF;
    }
    for (var j = 0; j < 64; j++) {
      w1[j] = (w[j] ^ w[j + 4]) & 0xFFFFFFFF;
    }

    var a = v[0], b = v[1], c = v[2], d = v[3];
    var e = v[4], f = v[5], g = v[6], h = v[7];

    for (var j = 0; j < 64; j++) {
      final tj = j < 16 ? 0x79cc4519 : 0x7a879d8a;
      final ss1 = _rotl32((_rotl32(a, 12) + e + _rotl32(tj, j % 32)) & 0xFFFFFFFF, 7);
      final ss2 = (ss1 ^ _rotl32(a, 12)) & 0xFFFFFFFF;
      final tt1 = (_ff(j, a, b, c) + d + ss2 + w1[j]) & 0xFFFFFFFF;
      final tt2 = (_gg(j, e, f, g) + h + ss1 + w[j]) & 0xFFFFFFFF;
      d = c;
      c = _rotl32(b, 9);
      b = a;
      a = tt1;
      h = g;
      g = _rotl32(f, 19);
      f = e;
      e = _p0(tt2);
    }

    v[0] ^= a;
    v[1] ^= b;
    v[2] ^= c;
    v[3] ^= d;
    v[4] ^= e;
    v[5] ^= f;
    v[6] ^= g;
    v[7] ^= h;
  }

  final out = Uint8List(32);
  final obd = ByteData.sublistView(out);
  for (var i = 0; i < 8; i++) {
    obd.setUint32(i * 4, v[i] & 0xFFFFFFFF, Endian.big);
  }
  return out;
}
