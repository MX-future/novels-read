import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/utils/html_text.dart';

void main() {
  group('HtmlText.convert', () {
    test('空字符串返回空', () {
      expect(HtmlText.convert(''), '');
    });

    test('纯文本原样返回', () {
      expect(HtmlText.convert('纯文本内容'), '纯文本内容');
    });

    test('段落之间换行', () {
      expect(
        HtmlText.convert('<p>第一段</p><p>第二段</p>'),
        '第一段\n第二段',
      );
    });

    test('div 也作为块级换行', () {
      expect(
        HtmlText.convert('<div>甲</div><div>乙</div>'),
        '甲\n乙',
      );
    });

    test('br 产生换行', () {
      expect(
        HtmlText.convert('<p>第一行<br>第二行</p>'),
        '第一行\n第二行',
      );
    });

    test('移除 h1-h6 标题(避免与 UI 重复)', () {
      final result = HtmlText.convert('<h1>大标题</h1><p>正文</p>');
      expect(result, isNot(contains('大标题')));
      expect(result, contains('正文'));
    });

    test('移除行内格式标签保留文字', () {
      final result = HtmlText.convert('<p><b>加粗</b>和<i>斜体</i>和<u>下划线</u></p>');
      expect(result, '加粗和斜体和下划线');
    });

    test('折叠行内多余空白', () {
      expect(HtmlText.convert('<p>有  多个    空格</p>'), '有 多个 空格');
    });

    test('移除空白行', () {
      final result = HtmlText.convert('<p>第一段</p><p>  </p><p>第三段</p>');
      expect(result, '第一段\n第三段');
    });

    test('处理 &nbsp; 不换行空格', () {
      expect(HtmlText.convert('<p>a&nbsp;&nbsp;b</p>'), 'a b');
    });

    test('列表项各自成行', () {
      final result = HtmlText.convert('<ul><li>苹果</li><li>香蕉</li></ul>');
      expect(result, '苹果\n香蕉');
    });

    test('嵌套标签递归处理', () {
      final result = HtmlText.convert(
        '<div><p>外层<b>加粗</b></p><p>内层</p></div>',
      );
      expect(result, contains('外层加粗'));
      expect(result, contains('内层'));
    });

    test('script/style 内容不应出现', () {
      final result = HtmlText.convert(
        '<p>正文</p><script>var x = 1;</script><style>p { color: red; }</style>',
      );
      expect(result, contains('正文'));
      expect(result, isNot(contains('var x')));
      expect(result, isNot(contains('color: red')));
    });

    test('多个块级标签不产生多余空行', () {
      final result = HtmlText.convert('<p>甲</p><p>乙</p><p>丙</p>');
      expect(result, '甲\n乙\n丙');
    });

    test('行内标签包裹的文本合并到一行', () {
      final result = HtmlText.convert('<p>这是<span>内联</span>内容</p>');
      expect(result, '这是内联内容');
    });
  });
}
