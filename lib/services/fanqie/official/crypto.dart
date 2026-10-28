// 纯 Dart 的 MD5 与 AES-128-CBC 实现。
//
// 本项目刻意不引入 crypto/pointycastle：一旦改动 pubspec 就要重新联网
// `pub get`，而 epubx 不在离线缓存里，会把能构建的工程搞坏。这里只实现
// 番茄签名链真正用到的那一点算法（MD5 摘要、AES-128 单块 + CBC），
// 逐项对着 Python 侧参考实现对拍。
import 'dart:typed_data';

/// PKCS#7 填充到 [blockSize] 的整数倍。
Uint8List pkcs7Pad(Uint8List data, [int blockSize = 16]) {
  final pad = blockSize - data.length % blockSize;
  final out = Uint8List(data.length + pad);
  out.setRange(0, data.length, data);
  for (var i = data.length; i < out.length; i++) {
    out[i] = pad;
  }
  return out;
}

/// 去掉 PKCS#7 填充；格式不合法时原样返回（调用方自行判断）。
Uint8List pkcs7Unpad(Uint8List data) {
  if (data.isEmpty) return data;
  final n = data[data.length - 1];
  if (n < 1 || n > 16 || n > data.length) return data;
  for (var i = data.length - n; i < data.length; i++) {
    if (data[i] != n) return data;
  }
  return Uint8List.sublistView(data, 0, data.length - n);
}

// --------------------------------------------------------------------- MD5

const List<int> _md5S = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

const List<int> _md5K = [
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
  0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
  0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
  0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
  0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
  0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

/// 标准 MD5，返回 16 字节摘要。
Uint8List md5(List<int> input) {
  final data = Uint8List.fromList(input);
  final bitLen = data.length * 8;
  // padding: 0x80, zeros, then 64-bit LE length
  var padLen = 64 - ((data.length + 9) % 64);
  if (padLen == 64) padLen = 0;
  final buf = Uint8List(data.length + 1 + padLen + 8);
  buf.setRange(0, data.length, data);
  buf[data.length] = 0x80;
  final bd = ByteData.sublistView(buf);
  bd.setUint32(buf.length - 8, bitLen & 0xFFFFFFFF, Endian.little);
  bd.setUint32(buf.length - 4, (bitLen ~/ 0x100000000) & 0xFFFFFFFF, Endian.little);

  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

  final m = Uint32List(16);
  for (var off = 0; off < buf.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      m[i] = bd.getUint32(off + i * 4, Endian.little);
    }
    var a = a0, b = b0, c = c0, d = d0;
    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }
      f = (f + a + _md5K[i] + m[g]) & 0xFFFFFFFF;
      a = d;
      d = c;
      c = b;
      b = (b + _rotl32(f, _md5S[i])) & 0xFFFFFFFF;
    }
    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  final out = Uint8List(16);
  final obd = ByteData.sublistView(out);
  obd.setUint32(0, a0, Endian.little);
  obd.setUint32(4, b0, Endian.little);
  obd.setUint32(8, c0, Endian.little);
  obd.setUint32(12, d0, Endian.little);
  return out;
}

// --------------------------------------------------------------------- AES

const List<int> _sbox = [
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b,
  0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
  0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26,
  0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2,
  0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
  0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed,
  0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f,
  0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
  0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec,
  0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14,
  0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
  0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d,
  0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f,
  0x4b, 0xbd, 0x8b, 0x8a, 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
  0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11,
  0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f,
  0xb0, 0x54, 0xbb, 0x16,
];

final List<int> _invSbox = () {
  final inv = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    inv[_sbox[i]] = i;
  }
  return inv;
}();

int _xtime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xFF;

int _gmul(int a, int b) {
  var p = 0;
  for (var i = 0; i < 8; i++) {
    if ((b & 1) != 0) p ^= a;
    a = _xtime(a);
    b >>= 1;
  }
  return p & 0xFF;
}

/// AES-128 分组实现（仅需 128 位密钥；番茄两处都用 AES-128）。
class Aes128 {
  final Uint8List _rk = Uint8List(176);

  Aes128(List<int> key) {
    if (key.length != 16) {
      throw ArgumentError('AES-128 requires a 16-byte key');
    }
    _rk.setRange(0, 16, key);
    var rcon = 1;
    for (var i = 16; i < 176; i += 4) {
      var t0 = _rk[i - 4], t1 = _rk[i - 3], t2 = _rk[i - 2], t3 = _rk[i - 1];
      if (i % 16 == 0) {
        final tmp = t0;
        t0 = _sbox[t1] ^ rcon;
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[tmp];
        rcon = _xtime(rcon);
      }
      _rk[i] = _rk[i - 16] ^ t0;
      _rk[i + 1] = _rk[i - 15] ^ t1;
      _rk[i + 2] = _rk[i - 14] ^ t2;
      _rk[i + 3] = _rk[i - 13] ^ t3;
    }
  }

  void _addRoundKey(Uint8List s, int round) {
    for (var i = 0; i < 16; i++) {
      s[i] ^= _rk[round * 16 + i];
    }
  }

  void _encryptBlock(Uint8List s) {
    _addRoundKey(s, 0);
    final t = Uint8List(16);
    for (var round = 1; round <= 10; round++) {
      // SubBytes + ShiftRows
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          t[c * 4 + r] = _sbox[s[((c + r) % 4) * 4 + r]];
        }
      }
      if (round != 10) {
        for (var c = 0; c < 4; c++) {
          final a0 = t[c * 4], a1 = t[c * 4 + 1], a2 = t[c * 4 + 2], a3 = t[c * 4 + 3];
          s[c * 4] = _gmul(a0, 2) ^ _gmul(a1, 3) ^ a2 ^ a3;
          s[c * 4 + 1] = a0 ^ _gmul(a1, 2) ^ _gmul(a2, 3) ^ a3;
          s[c * 4 + 2] = a0 ^ a1 ^ _gmul(a2, 2) ^ _gmul(a3, 3);
          s[c * 4 + 3] = _gmul(a0, 3) ^ a1 ^ a2 ^ _gmul(a3, 2);
        }
      } else {
        s.setRange(0, 16, t);
      }
      _addRoundKey(s, round);
    }
  }

  void _decryptBlock(Uint8List s) {
    _addRoundKey(s, 10);
    final t = Uint8List(16);
    for (var round = 9; round >= 0; round--) {
      // InvShiftRows + InvSubBytes
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          t[((c + r) % 4) * 4 + r] = _invSbox[s[c * 4 + r]];
        }
      }
      _addRoundKey(t, round);
      if (round != 0) {
        for (var c = 0; c < 4; c++) {
          final a0 = t[c * 4], a1 = t[c * 4 + 1], a2 = t[c * 4 + 2], a3 = t[c * 4 + 3];
          s[c * 4] = _gmul(a0, 14) ^ _gmul(a1, 11) ^ _gmul(a2, 13) ^ _gmul(a3, 9);
          s[c * 4 + 1] = _gmul(a0, 9) ^ _gmul(a1, 14) ^ _gmul(a2, 11) ^ _gmul(a3, 13);
          s[c * 4 + 2] = _gmul(a0, 13) ^ _gmul(a1, 9) ^ _gmul(a2, 14) ^ _gmul(a3, 11);
          s[c * 4 + 3] = _gmul(a0, 11) ^ _gmul(a1, 13) ^ _gmul(a2, 9) ^ _gmul(a3, 14);
        }
      } else {
        s.setRange(0, 16, t);
      }
    }
  }

  /// CBC 加密；[iv] 必须 16 字节，明文按 PKCS#7 填充。
  Uint8List cbcEncrypt(List<int> plain, List<int> iv) {
    final input = pkcs7Pad(Uint8List.fromList(plain));
    final out = Uint8List(input.length);
    var prev = Uint8List.fromList(iv);
    final block = Uint8List(16);
    for (var off = 0; off < input.length; off += 16) {
      for (var i = 0; i < 16; i++) {
        block[i] = input[off + i] ^ prev[i];
      }
      _encryptBlock(block);
      out.setRange(off, off + 16, block);
      prev = Uint8List.fromList(block);
    }
    return out;
  }

  /// CBC 解密，返回去除 PKCS#7 填充后的明文。
  Uint8List cbcDecrypt(List<int> cipher, List<int> iv) {
    if (cipher.length % 16 != 0) {
      throw ArgumentError('cipher length not a multiple of 16');
    }
    final out = Uint8List(cipher.length);
    var prev = Uint8List.fromList(iv);
    final block = Uint8List(16);
    for (var off = 0; off < cipher.length; off += 16) {
      block.setRange(0, 16, cipher, off);
      final keep = Uint8List.fromList(block);
      _decryptBlock(block);
      for (var i = 0; i < 16; i++) {
        out[off + i] = block[i] ^ prev[i];
      }
      prev = keep;
    }
    return pkcs7Unpad(out);
  }
}
