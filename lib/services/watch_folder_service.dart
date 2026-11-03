import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'epub_service.dart';
import 'txt_importer.dart';
import '../models/book.dart';

/// 一次自动扫描的结果。
class WatchScanResult {
  const WatchScanResult({
    required this.found,
    required this.imported,
    required this.skipped,
    required this.failed,
    required this.importedTitles,
    required this.failedNames,
    required this.duration,
  });

  /// 目录里识别到的 epub / txt 总数。
  final int found;

  /// 本次新入架的本数。
  final int imported;

  /// 已在架或与架上书重复而跳过的本数。
  final int skipped;

  final int failed;
  final List<String> importedTitles;
  final List<String> failedNames;
  final Duration duration;

  /// 一行摘要,用于 toast。
  String get summary {
    if (found == 0) return '目录里没有 epub / txt 文件';
    final parts = <String>['新导入 $imported 本'];
    if (skipped > 0) parts.add('已在架 $skipped');
    if (failed > 0) {
      parts.add('失败 $failed');
      final names = failedNames.take(3).join('、');
      parts.add('($names${failedNames.length > 3 ? ' 等' : ''})');
    }
    return parts.join(' · ');
  }
}

/// 自动导入目录:记住一个本地文件夹,每次启动静默扫描,新书自动入库。
///
/// macOS 沙盒的限制是这里唯一的技术难点:NSOpenPanel 授予的访问权限只属于
/// 当前进程,进程退出即失效。所以选目录必须经过原生层把它存成
/// security-scoped bookmark,下次启动解析回 URL 并重新申请访问权限,
/// 否则重启后读目录会被系统直接拒绝(表现为"扫描不到任何文件")。
///
/// 非 macOS 平台(桌面 Linux / Windows 无沙盒)走纯 Dart 路径,直接记住路径。
class WatchFolderService {
  WatchFolderService._();

  static const MethodChannel _channel =
      MethodChannel('com.reader.novelReader/watchfolder');

  static const String _pathPref = 'watch_folder_path';
  static const String _lastScanPref = 'watch_folder_last_scan';
  static const String _lastImportedPref = 'watch_folder_last_imported';

  /// 当前可用路径(已恢复访问权限),null 表示未配置或授权失效。
  static String? _activePath;

  /// 扫描进行中标记,避免启动扫描与手动扫描叠加。
  static bool _scanning = false;

  static bool get isScanning => _scanning;

  /// 已配置的目录路径(仅在恢复授权后才有值)。
  static String? get activePath => _activePath;

  /// 恢复已保存目录的访问权限,返回可读路径。
  ///
  /// 进入 App 时先调一次;配置失效(目录被删/被移动/授权丢失)返回 null 并清掉配置。
  static Future<String?> restoreAccess() async {
    final cached = _activePath;
    if (cached != null && await Directory(cached).exists()) return cached;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pathPref);
    if (saved == null || saved.isEmpty) {
      _activePath = null;
      return null;
    }

    var candidate = saved;
    if (Platform.isMacOS) {
      try {
        final resolved = await _channel.invokeMethod<String>('restore');
        if (resolved != null && resolved.isNotEmpty) candidate = resolved;
      } on MissingPluginException {
        // 原生通道未注册(例如跑单元测试),退回纯路径判断
      } on PlatformException {
        // 解析失败同样退回纯路径判断,由下面的 exists 决定是否可用
      }
    }

    if (await Directory(candidate).exists()) {
      _activePath = candidate;
      return candidate;
    }

    // 目录确实不可用了,清掉配置,让界面回到"未设置"
    await prefs.remove(_pathPref);
    _activePath = null;
    return null;
  }

  /// 让用户选择目录,成功后立刻持久化授权。
  static Future<String?> pick() async {
    String? path;
    if (Platform.isMacOS) {
      try {
        path = await _channel.invokeMethod<String>('pick');
      } on MissingPluginException {
        // 原生通道未注册时退回 file_picker,功能仍可用(只是重启后可能失去授权)
        path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择自动导入目录',
        );
      } on PlatformException catch (e) {
        throw WatchFolderException(e.message ?? '选择目录失败');
      }
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择自动导入目录',
      );
    }
    if (path == null || path.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathPref, path);
    _activePath = path;
    return path;
  }

  /// 关闭自动导入并释放目录授权。
  static Future<void> clear() async {
    _activePath = null;
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod<void>('clear');
      } on MissingPluginException {
        // 忽略:没有原生层时只需清掉偏好
      } on PlatformException {
        // 同上
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pathPref);
    await prefs.remove(_lastScanPref);
    await prefs.remove(_lastImportedPref);
  }

  /// 上次扫描完成时间;从未扫描过返回 null。
  static Future<DateTime?> lastScanAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastScanPref);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 扫描目录并导入新书。未配置目录或授权失效返回 null。
  ///
  /// [existing] 传入调用方已加载的书架列表,省掉一次全量读盘(启动时已有数据)。
  /// [onProgress] 用于界面展示进度(当前文件名 / 已处理数),静默扫描可不传。
  static Future<WatchScanResult?> scan({
    List<BookMeta>? existing,
    void Function(int done, int total, String current)? onProgress,
  }) async {
    if (_scanning) return null;

    final dirPath = await restoreAccess();
    if (dirPath == null) return null;

    _scanning = true;
    final started = DateTime.now();
    try {
      final files = <String>[];
      await for (final entity
          in Directory(dirPath).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.epub') || lower.endsWith('.txt')) {
          files.add(entity.path);
        }
      }
      files.sort();

      // 已在架的判断依据:同一个源文件,或同书名同作者
      final metas = existing ?? await EpubService.listBooks();
      final sources = <String>{for (final b in metas) b.sourcePath};
      final keys = <String>{for (final b in metas) '${b.title}|${b.author}'};

      var imported = 0;
      var skipped = 0;
      var failed = 0;
      final importedTitles = <String>[];
      final failedNames = <String>[];

      for (var i = 0; i < files.length; i++) {
        final path = files[i];
        final name = p.basename(path);

        // 源文件已导入过,不必解析,直接跳过(启动扫描绝大多数走这条)
        if (sources.contains(path)) {
          skipped += 1;
          onProgress?.call(i + 1, files.length, name);
          continue;
        }

        onProgress?.call(i, files.length, name);
        try {
          final lower = path.toLowerCase();
          final book = lower.endsWith('.txt')
              ? await TxtImporter.parseFile(path)
              : await EpubService.importFromFile(path);
          if (lower.endsWith('.txt')) {
            // parseFile 只解析不落盘,与手动导入保持一致
            await EpubService.saveBook(book);
          }

          final key = '${book.title}|${book.author}';
          if (keys.contains(key)) {
            // 内容相同的另一份文件,删掉刚写入的副本
            await EpubService.deleteBook(book.id);
            skipped += 1;
          } else {
            keys.add(key);
            sources.add(path);
            imported += 1;
            importedTitles.add(book.title);
          }
        } catch (e) {
          failed += 1;
          failedNames.add(name);
          debugPrint('[watch-folder] 导入失败 $name: $e');
        }
        onProgress?.call(i + 1, files.length, name);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastScanPref, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_lastImportedPref, imported);

      return WatchScanResult(
        found: files.length,
        imported: imported,
        skipped: skipped,
        failed: failed,
        importedTitles: importedTitles,
        failedNames: failedNames,
        duration: DateTime.now().difference(started),
      );
    } on FileSystemException catch (e) {
      // 沙盒授权失效时最典型的现象:目录存在但无权列出
      throw WatchFolderException('无法读取目录:${e.message}');
    } finally {
      _scanning = false;
    }
  }
}

/// 自动导入目录相关的可预期错误,用于界面提示。
class WatchFolderException implements Exception {
  WatchFolderException(this.message);

  final String message;

  @override
  String toString() => message;
}
