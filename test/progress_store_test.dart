import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_reader/models/book.dart';
import 'package:novel_reader/services/progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProgressStore', () {
    const bookId = 'book_test_1';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('无存档时 load 返回 empty', () async {
      final progress = await ProgressStore.load(bookId);
      expect(progress, ReadingProgress.empty);
      expect(progress.chapterIndex, 0);
      expect(progress.pageIndex, 0);
    });

    test('save 后 load 能恢复进度', () async {
      const progress = ReadingProgress(chapterIndex: 3, pageIndex: 12);
      await ProgressStore.save(bookId, progress);

      final restored = await ProgressStore.load(bookId);
      expect(restored.chapterIndex, 3);
      expect(restored.pageIndex, 12);
    });

    test('不同书互不影响', () async {
      await ProgressStore.save('book_a', const ReadingProgress(chapterIndex: 1, pageIndex: 2));
      await ProgressStore.save('book_b', const ReadingProgress(chapterIndex: 5, pageIndex: 6));

      final a = await ProgressStore.load('book_a');
      final b = await ProgressStore.load('book_b');
      expect(a.chapterIndex, 1);
      expect(b.chapterIndex, 5);
    });

    test('save 覆盖已有进度', () async {
      await ProgressStore.save(bookId, const ReadingProgress(chapterIndex: 1, pageIndex: 1));
      await ProgressStore.save(bookId, const ReadingProgress(chapterIndex: 9, pageIndex: 99));

      final restored = await ProgressStore.load(bookId);
      expect(restored.chapterIndex, 9);
      expect(restored.pageIndex, 99);
    });

    test('clear 移除指定书进度', () async {
      await ProgressStore.save('book_a', const ReadingProgress(chapterIndex: 1, pageIndex: 1));
      await ProgressStore.save('book_b', const ReadingProgress(chapterIndex: 2, pageIndex: 2));

      await ProgressStore.clear('book_a');

      final a = await ProgressStore.load('book_a');
      expect(a, ReadingProgress.empty);
      // book_b 不受影响
      final b = await ProgressStore.load('book_b');
      expect(b.chapterIndex, 2);
    });

    test('loadAll 返回所有书进度', () async {
      await ProgressStore.save('book_a', const ReadingProgress(chapterIndex: 1, pageIndex: 1));
      await ProgressStore.save('book_b', const ReadingProgress(chapterIndex: 2, pageIndex: 2));

      final all = await ProgressStore.loadAll();
      expect(all.length, 2);
      expect(all['book_a']!.chapterIndex, 1);
      expect(all['book_b']!.pageIndex, 2);
    });

    test('loadAll 在损坏 JSON 时返回空 map(不抛异常)', () async {
      SharedPreferences.setMockInitialValues({
        'reading_progress_v1': '### 损坏数据 ###',
      });
      final all = await ProgressStore.loadAll();
      expect(all, isEmpty);
    });

    test('底层存储是 JSON 结构', () async {
      await ProgressStore.save(bookId, const ReadingProgress(chapterIndex: 2, pageIndex: 7));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('reading_progress_v1');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded[bookId], {'chapter': 2, 'page': 7});
    });
  });
}
