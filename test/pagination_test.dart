import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/utils/pagination.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextPaginator', () {
    const style = TextStyle(fontSize: 14, height: 1.5);

    test('短文本单页放得下', () {
      final pages = TextPaginator.paginate(
        text: '这是一段简短的文字。',
        maxWidth: 300,
        maxHeight: 300,
        style: style,
      );
      expect(pages.length, 1);
      expect(pages.first, '这是一段简短的文字。');
    });

    test('空文本返回单个空页', () {
      final pages = TextPaginator.paginate(
        text: '',
        maxWidth: 300,
        maxHeight: 300,
        style: style,
      );
      expect(pages.length, 1);
      expect(pages.first, '');
    });

    test('宽高为 0 时返回原文(不拆分)', () {
      final text = '不管多长的文本';
      final pages = TextPaginator.paginate(
        text: text,
        maxWidth: 0,
        maxHeight: 0,
        style: style,
      );
      expect(pages.length, 1);
      expect(pages.first, text);
    });

    test('超长文本分成多页,拼接后可完整还原', () {
      final text = List.generate(2000, (i) => '第$i行内容。').join('\n');
      final pages = TextPaginator.paginate(
        text: text,
        maxWidth: 300,
        maxHeight: 200,
        style: style,
      );
      expect(pages.length, greaterThan(1));
      // 逐页拼接不丢字、不增字
      final reassembled = pages.join();
      expect(reassembled, text);
    });

    test('分页不截断任何字符', () {
      final text = List.generate(500, (i) => '测试字符$i').join('');
      final pages = TextPaginator.paginate(
        text: text,
        maxWidth: 250,
        maxHeight: 150,
        style: style,
      );
      expect(pages.join(), text);
    });

    test('极窄容器产生更多页', () {
      final text = List.generate(100, (i) => '行$i').join('\n');
      final narrow = TextPaginator.paginate(
        text: text,
        maxWidth: 100,
        maxHeight: 100,
        style: style,
      );
      final wide = TextPaginator.paginate(
        text: text,
        maxWidth: 800,
        maxHeight: 100,
        style: style,
      );
      expect(narrow.length, greaterThanOrEqualTo(wide.length));
    });

    test('每页内容不超过容器高度(逻辑验证)', () {
      final text = List.generate(1000, (i) => '内容$i').join('\n');
      final pages = TextPaginator.paginate(
        text: text,
        maxWidth: 300,
        maxHeight: 120,
        style: style,
      );
      for (final page in pages) {
        final painter = TextPainter(
          text: TextSpan(text: page, style: style),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: 300);
        // 每页高度应不超过容器高度(允许少量误差:最后一行可能略超)
        expect(painter.height, lessThanOrEqualTo(120 + 30));
        painter.dispose();
      }
    });

    test('连续换行/空行也能正确处理', () {
      final text = '第一段\n\n\n第二段\n第三段';
      final pages = TextPaginator.paginate(
        text: text,
        maxWidth: 300,
        maxHeight: 500,
        style: style,
      );
      // 单页放得下时原样返回
      expect(pages.length, 1);
      expect(pages.first, text);
    });
  });
}
