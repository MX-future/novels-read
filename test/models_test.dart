import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/models/book.dart';

void main() {
  group('Chapter', () {
    test('toJson/fromJson 往返一致', () {
      const chapter = Chapter(title: '第一章', content: '正文内容');
      final json = chapter.toJson();
      final restored = Chapter.fromJson(json);
      expect(restored.title, '第一章');
      expect(restored.content, '正文内容');
    });

    test('fromJson 缺失字段时使用默认值', () {
      final chapter = Chapter.fromJson(const {});
      expect(chapter.title, '');
      expect(chapter.content, '');
    });
  });

  group('Book', () {
    const book = Book(
      id: 'book_1',
      title: '测试书籍',
      author: '作者甲',
      coverPath: '/tmp/cover.jpg',
      sourcePath: '/tmp/book.epub',
      chapters: [
        Chapter(title: '第一章', content: '内容1'),
        Chapter(title: '第二章', content: '内容2'),
      ],
    );

    test('toJson/fromJson 往返一致', () {
      final json = book.toJson();
      final restored = Book.fromJson(json);
      expect(restored.id, 'book_1');
      expect(restored.title, '测试书籍');
      expect(restored.author, '作者甲');
      expect(restored.coverPath, '/tmp/cover.jpg');
      expect(restored.sourcePath, '/tmp/book.epub');
      expect(restored.chapters.length, 2);
      expect(restored.chapters.first.title, '第一章');
      expect(restored.chapters.last.content, '内容2');
    });

    test('fromJson 缺失可选字段时使用默认值', () {
      final restored = Book.fromJson(const {
        'id': 'book_2',
        'title': '标题',
      });
      expect(restored.author, '未知作者');
      expect(restored.coverPath, isNull);
      expect(restored.sourcePath, '');
      expect(restored.chapters, isEmpty);
    });

    test('fromJson 缺少 id 会抛错(必需字段)', () {
      expect(
        () => Book.fromJson(const {'title': '无id'}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('BookMeta', () {
    test('fromBook 正确提取元信息', () {
      const book = Book(
        id: 'book_1',
        title: '测试书籍',
        author: '作者甲',
        coverPath: null,
        sourcePath: '/tmp/book.epub',
        chapters: [
          Chapter(title: '第一章', content: '内容1'),
          Chapter(title: '第二章', content: '内容2'),
          Chapter(title: '第三章', content: '内容3'),
        ],
      );
      final meta = BookMeta.fromBook(book);
      expect(meta.id, 'book_1');
      expect(meta.title, '测试书籍');
      expect(meta.author, '作者甲');
      expect(meta.chapterCount, 3);
      expect(meta.sourcePath, '/tmp/book.epub');
      expect(meta.coverPath, isNull);
    });
  });

  group('ReadingProgress', () {
    test('toJson/fromJson 往返一致', () {
      const progress = ReadingProgress(chapterIndex: 2, pageIndex: 10);
      final json = progress.toJson();
      expect(json['chapter'], 2);
      expect(json['page'], 10);

      final restored = ReadingProgress.fromJson(json);
      expect(restored.chapterIndex, 2);
      expect(restored.pageIndex, 10);
    });

    test('fromJson 缺失字段时使用 0', () {
      final progress = ReadingProgress.fromJson(const {});
      expect(progress.chapterIndex, 0);
      expect(progress.pageIndex, 0);
    });

    test('empty 常量是 (0, 0)', () {
      expect(ReadingProgress.empty.chapterIndex, 0);
      expect(ReadingProgress.empty.pageIndex, 0);
    });
  });
}
