// SIMON 分组密码的番茄变体（72 轮，非标准 44 轮）。
//
// 参考实现的 `c == 0` 分支里 f 是 `rotl(x,1) & rotl(x,8)`（按位与），
// 轮密钥扩展用 `~k[i-4] ^ tmp ^ bit(0x3DC94C3A046D678B, (i-4)%62) ^ 3`。
// Dart 的 int 是 64 位二进制补码，`<<` 自然溢出、`>>>` 为逻辑右移，
// 因此不需要额外掩码即可复现 uint64 行为。
import 'dart:typed_data';

int _rotl64(int v, int n) => (v << n) | (v >>> (64 - n));

int _rotr64(int v, int n) => (v << (64 - n)) | (v >>> n);

const int _c64 = 0x3DC94C3A046D678B;

Int64List _keyExpansion(Int64List k, int rounds) {
  final key = Int64List(rounds);
  key.setRange(0, 4, k);
  for (var i = 4; i < rounds; i++) {
    var tmp = _rotr64(key[i - 1], 3);
    tmp ^= key[i - 3];
    tmp ^= _rotr64(tmp, 1);
    final bit = (_c64 & (1 << ((i - 4) % 62))) != 0 ? 1 : 0;
    key[i] = (~key[i - 4]) ^ tmp ^ bit ^ 3;
  }
  return key;
}

/// 加密一个 16 字节分组：[pt] 为两个 uint64（小端序解释）。
Int64List simonEncrypt(Int64List pt, Int64List k, {int c = 0, int rounds = 72}) {
  final key = _keyExpansion(k, rounds);
  var x = pt[0];
  var y = pt[1];
  for (var i = 0; i < rounds; i++) {
    final tmp = y;
    final f = c == 1 ? _rotl64(y, 1) : (_rotl64(y, 1) & _rotl64(y, 8));
    y = x ^ f ^ _rotl64(y, 2) ^ key[i];
    x = tmp;
  }
  return Int64List.fromList([x, y]);
}

Int64List simonDecrypt(Int64List ct, Int64List k,
    {int c = 0, int rounds = 72}) {
  final key = _keyExpansion(k, rounds);
  var x = ct[0];
  var y = ct[1];
  for (var i = rounds - 1; i >= 0; i--) {
    final tmp = x;
    final f = c == 1 ? _rotl64(x, 1) : (_rotl64(x, 1) & _rotl64(x, 8));
    x = y ^ f ^ _rotl64(x, 2) ^ key[i];
    y = tmp;
  }
  return Int64List.fromList([x, y]);
}

/// 把 [bytes] 按 16 字节一组就地加密，返回新缓冲。
Uint8List simonEncryptBytes(Uint8List bytes, List<int> keyWords,
    {int c = 0, int rounds = 72}) {
  final k = Int64List.fromList(keyWords);
  final out = Uint8List(bytes.length);
  final bdIn = ByteData.sublistView(bytes);
  final bdOut = ByteData.sublistView(out);
  for (var off = 0; off < bytes.length; off += 16) {
    final pt = Int64List.fromList([
      bdIn.getUint64(off, Endian.little),
      bdIn.getUint64(off + 8, Endian.little),
    ]);
    final ct = simonEncrypt(pt, k, c: c, rounds: rounds);
    bdOut.setUint64(off, ct[0], Endian.little);
    bdOut.setUint64(off + 8, ct[1], Endian.little);
  }
  return out;
}
