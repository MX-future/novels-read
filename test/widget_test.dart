import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/utils/pagination.dart';
import 'package:novel_reader/utils/html_text.dart';

void main() {
  group('TextPaginator', () {
    test('short text fits in a single page', () {
      final pages = TextPaginator.paginate(
        text: '这是一段简短的文字。',
        maxWidth: 300,
        maxHeight: 300,
        style: const TextStyle(fontSize: 14),
      );
      expect(pages.length, 1);
      expect(pages.first, '这是一段简短的文字。');
    });

    test('long text is split into multiple pages', () {
      final text = List.generate(2000, (i) => '第$i行内容。').join('\n');
      final pages = TextPaginator.paginate(
        text: text,
        maxWidth: 300,
        maxHeight: 200,
        style: const TextStyle(fontSize: 14, height: 1.5),
      );
      expect(pages.length, greaterThan(1));
      final reassembled = pages.join();
      expect(reassembled, text);
    });

    test('empty text returns single empty page', () {
      final pages = TextPaginator.paginate(
        text: '',
        maxWidth: 300,
        maxHeight: 300,
        style: const TextStyle(fontSize: 14),
      );
      expect(pages.length, 1);
    });
  });

  group('HtmlText', () {
    test('converts simple paragraph html to plain text', () {
      final result = HtmlText.convert('<p>第一段</p><p>第二段</p>');
      expect(result, '第一段\n第二段');
    });

    test('strips inline formatting tags', () {
      final result = HtmlText.convert('<p>这<b>是</b>带<i>格式</i>的文本</p>');
      expect(result, '这是带格式的文本');
    });

    test('handles headings and breaks', () {
      final result = HtmlText.convert('<h1>标题</h1><p>内容一</p><br/><p>内容二</p>');
      expect(result, contains('标题'));
      expect(result, contains('内容一'));
      expect(result, contains('内容二'));
    });
  });
}
