import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

/// 阅读进度存储(基于 SharedPreferences)。
class ProgressStore {
  static const _key = 'reading_progress_v1';

  static Future<Map<String, ReadingProgress>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, ReadingProgress.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Future<ReadingProgress> load(String bookId) async {
    final all = await loadAll();
    return all[bookId] ?? ReadingProgress.empty;
  }

  static Future<void> save(String bookId, ReadingProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    all[bookId] = progress;
    await prefs.setString(
      _key,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  static Future<void> clear(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    all.remove(bookId);
    await prefs.setString(
      _key,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}
