// 对拍脚本：把 Dart 侧的加密实现与 Python 参考实现（pycryptodome + 逆向结果）
// 逐项比较。运行：dart run tool/verify_crypto.dart
//
// 全部向量由 Python 侧生成，硬编码在下面，任何一项不符即以非零码退出。
import 'dart:convert';
import 'dart:typed_data';

import '../lib/services/fanqie/official/argus.dart';
import '../lib/services/fanqie/official/crypto.dart';
import '../lib/services/fanqie/official/ladon.dart';
import '../lib/services/fanqie/official/pb.dart';
import '../lib/services/fanqie/official/simon.dart';
import '../lib/services/fanqie/official/sm3.dart';

int _fail = 0;

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);

void check(String name, String got, String want) {
  final ok = got == want;
  if (!ok) _fail++;
  print('${ok ? "PASS" : "FAIL"}  $name');
  if (!ok) {
    print('        got : $got');
    print('        want: $want');
  }
}

void main() {
  // ---- MD5
  check('md5("")', _hex(md5(const [])), 'd41d8cd98f00b204e9800998ecf8427e');
  check('md5("abc")', _hex(md5(utf8.encode('abc'))),
      '900150983cd24fb0d6963f7d28e17f72');

  // ---- SM3
  check('sm3("")', _hex(sm3(const [])),
      '1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b');
  check('sm3("abc")', _hex(sm3(utf8.encode('abc'))),
      '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0');
  check('sm3(16 zeros)', _hex(sm3(Uint8List(16))),
      '106e34a2b8c7bb13156cfdd0d91379dcc47543dcf9787c68ae5eb582620ae6e8');

  // ---- hash 截断（Argus 用的 6 字节）
  check('queryHash', _hex(ArgusDebug.queryHash(
          'aid=1967&device_id=1096638923807993&iid=0')),
      '615bff4b2f5b');
  check('bodyHash(empty)', _hex(ArgusDebug.bodyHash(Uint8List(0))),
      '106e34a2b8c7');

  // ---- AES-128-CBC
  final key = _unhex('ac25c67ddd8f38c1b37a2348828e222e');
  final iv = _unhex('000102030405060708090a0b0c0d0e0f');
  final pt2 = _unhex('00112233445566778899aabbccddeeff'
      'ffeeddccbbaa99887766554433221100');
  final aes = Aes128(key);
  check('AES cbc encrypt',
      _hex(aes.cbcEncrypt(pt2, iv)),
      'f634917d3cf1f030920a90b53daf68c0'
          '9826e554a16cbb81d317ad369bf73b40'
          'd74df59e1900565cd1bb41207161e3a2');
  check('AES cbc decrypt', _hex(aes.cbcDecrypt(
          _unhex('f634917d3cf1f030920a90b53daf68c0'
              '9826e554a16cbb81d317ad369bf73b40'
              'd74df59e1900565cd1bb41207161e3a2'), iv)),
      _hex(pt2));

  // ---- SIMON 72 轮
  final sPt = Int64List.fromList([0x0123456789abcdef, -0x0123456789abcdf0]);
  final sKey = Int64List.fromList([
    0x1111111111111111,
    0x2222222222222222,
    0x3333333333333333,
    0x4444444444444444,
  ]);
  final ct = simonEncrypt(sPt, sKey);
  String u64(int v) => BigInt.from(v).toUnsigned(64).toRadixString(16);
  check('SIMON ct[0]', u64(ct[0]), 'c1b73b35be123a0a');
  check('SIMON ct[1]', u64(ct[1]), 'd1b2a1f3d0b9a4c3');
  final back = simonDecrypt(ct, sKey);
  check('SIMON roundtrip',
      (back[0] == sPt[0] && back[1] == sPt[1]) ? 'ok' : 'bad', 'ok');

  // ---- protobuf
  final bean = {
    1: 0x20200929 << 1,
    2: 2,
    3: 123456789,
    4: '1967',
    5: '1096638923807993',
    6: '1611921764',
    7: '7.2.3.32',
    8: 'v04.04.05-ov-android',
    9: 134744640,
    10: Uint8List(8),
    11: 0,
    12: 1700000000 << 1,
    13: _unhex('106e34a2b8c7'),
    14: _unhex('615bff4b2f5b'),
    15: {1: 1, 2: 1, 3: 1, 7: 3348294860},
    16: '',
    20: 'none',
    21: 738,
    23: {1: 'NX551J', 2: 8196, 4: 2162219008},
    25: 2,
  };
  check('pbEncode', _hex(pbEncode(bean)),
      '08d2a4808204100218959aef3a2204313936372a1031303936363338393233383037393933320a31'
      '3631313932313736343a08372e322e332e333242147630342e30342e30352d6f762d616e64726f69'
      '6448c094a0405208000000000000000058006080c49fd50c6a06106e34a2b8c77206615bff4b2f5b'
      '7a0c08011001180138ccd9cbbc0c820100a201046e6f6e65a801e205ba01110a064e583535314a1084'
      '402080b0838708c80102');

  // ---- Argus 整体（epb -> SIMON -> 反转 -> AES）
  check('X-Argus', argusEncrypt(bean),
      '8oGwZRLe2V38m+1gfqIeLa2MoV9ZBWosW5Y0NXKHAB2aEX8Sy3XkKahnaeRieievkKLOdGQgARPbbEQitP0ddfWUSjq/j9lnR5jY23PpRcgpw6k+PKERHo8BgRVBN6+exmhxtovFYZs+UngTKh4NJhqvf/3Ik1RkFAU/mZpzNPedvy2MtYBJrvkrhguKU0lnJUejg2nuMB0qQ3PCCvGVQW45CVLxLPlrTTIDNm38BsanX+tBfF3ka2SGC+3PSoMD/7/1nzK361vaJI2KFlq3cFIj');

  // ---- Ladon（固定随机数）
  check('X-Ladon',
      makeLadon(1700000000, randomBytes: _unhex('deadbeef')),
      '3q2+7/6PK4T/ZqM1zu2AIWFdXW2+/PrD34fqGRaHEfKmF7J3');

  print(_fail == 0 ? '\nALL PASS' : '\n$_fail FAILURE(S)');
  if (_fail != 0) throw StateError('crypto verification failed');
}
