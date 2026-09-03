import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/services/fanqie/fanqie_map.dart';

void main() {
  group('FanqieMap.puaToChar', () {
    test('表非空且含 362 项', () {
      expect(FanqieMap.puaToChar.length, 362);
    });

    test('键为 PUA 区段内码位(十进制 E000..F8FF)', () {
      for (final key in FanqieMap.puaToChar.keys) {
        expect(key, inInclusiveRange(0xE000, 0xF8FF));
      }
    });

    test('值均非空且不为 PUA', () {
      for (final v in FanqieMap.puaToChar.values) {
        expect(v, isNotEmpty);
        final cp = v.codeUnitAt(0);
        expect(cp < 0xE000 || cp > 0xF8FF, isTrue,
            reason: '值不应仍是 PUA 字符: $v');
      }
    });
  });

  group('FanqieMap.decodeText', () {
    test('空串原样返回', () {
      expect(FanqieMap.decodeText(''), '');
    });

    test('无 PUA 的普通文本不变', () {
      expect(FanqieMap.decodeText('这是一段普通文本。'), '这是一段普通文本。');
    });

    test('已知 PUA 码位被替换为对应汉字', () {
      // 58344 => 'D'(ASCII),58345 => '在'(该映射来自番茄全局字体表)
      expect(FanqieMap.decodeText('\uE3E8'), FanqieMap.puaToChar[0xE3E8]);
    });

    test('PUA 逐字解码后无残留(输出长度不变)', () {
      final raw = '山\uE42C水\uE531间';
      final out = FanqieMap.decodeText(raw);
      expect(out, isNot(contains(RegExp(r'[\uE000-\uF8FF]'))));
      expect(out.length, raw.length);
      // 前缀/后缀普通文字应保持原位
      expect(out.startsWith('山'), isTrue);
      expect(out.endsWith('间'), isTrue);
    });

    test('表中不存在的 PUA 码位原样保留', () {
      // 0xF8FF 不在 362 项表中,应原样输出不崩溃
      expect(FanqieMap.decodeText('a\uf8ffb'), 'a\uf8ffb');
    });
  });

  group('FanqieMap.decodeChapterHtml', () {
    test('空串返回空', () {
      expect(FanqieMap.decodeChapterHtml(''), '');
    });

    test('HTML 转纯文本并保留段落换行', () {
      expect(FanqieMap.decodeChapterHtml('<p>第一段</p><p>第二段</p>'),
          '第一段\n第二段');
    });

    test('解码后再去标签:正文可读', () {
      final html = '<p>\uE42C\uE531抬\uE428擂台\uE3F0。</p>'
          '<p>演武\uE4F3氛围久久未恢复。</p>';
      final out = FanqieMap.decodeChapterHtml(html);
      expect(out, isNot(contains('<'))); // 标签已剥离
      expect(out, isNot(contains(RegExp(r'[\uE000-\uF8FF]')))); // PUA 已解码
      expect(out.split('\n'), hasLength(2));
    });
  });
}
