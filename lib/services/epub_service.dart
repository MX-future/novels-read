import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../models/book.dart';
import '../utils/html_text.dart';

/// 解析 EPUB 文件并写入本地存储。
class EpubService {
  /// 从 [filePath] 导入一本 epub,返回保存后的 Book。
  static Future<Book> importFromFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final epub = await EpubReader.readBook(bytes);

    final title = (epub.Title?.trim().isNotEmpty ?? false)
        ? epub.Title!.trim()
        : p.basenameWithoutExtension(filePath);
    final author = (epub.Author?.trim().isNotEmpty ?? false)
        ? epub.Author!.trim()
        : '未知作者';

    final bookId = _generateId(title, author);

    // 先尝试用 epubx 提取;若 epubx 的 Images map 为空,再用 ZIP 兜底。
    String? coverPath = await _extractCover(epub, bookId);
    coverPath ??= await _extractCoverFromZip(bytes, bookId);

    // 提取章节(嵌套子章节扁平化)
    final chapters = <Chapter>[];
    void walk(EpubChapter ch) {
      final html = ch.HtmlContent ?? '';
      final text = HtmlText.convert(html);
      final chTitle = (ch.Title?.trim().isNotEmpty ?? false)
          ? ch.Title!.trim()
          : '未命名章节';
      if (text.trim().isNotEmpty) {
        chapters.add(Chapter(title: chTitle, content: text));
      }
      ch.SubChapters?.forEach(walk);
    }

    epub.Chapters?.forEach(walk);

    // 兜底:没有结构化章节时,直接遍历 HTML 文件
    if (chapters.isEmpty) {
      final htmlFiles = epub.Content?.Html ?? const {};
      final keys = htmlFiles.keys.toList()..sort();
      for (final key in keys) {
        final f = htmlFiles[key]!;
        final text = HtmlText.convert(f.Content ?? '');
        if (text.trim().isNotEmpty) {
          final rawName = f.FileName ?? key;
          final name = p.basenameWithoutExtension(rawName);
          chapters.add(Chapter(title: name, content: text));
        }
      }
    }

    final book = Book(
      id: bookId,
      title: title,
      author: author,
      coverPath: coverPath,
      sourcePath: filePath,
      chapters: chapters,
    );

    await _writeBookFile(book);
    return book;
  }

  /// 多策略封面提取,兼容 EPUB 2 (meta name="cover") 与 EPUB 3
  /// (properties="cover-image")。直接保存原始字节,避免解码失败。
  static Future<String?> _extractCover(EpubBook epub, String bookId) async {
    final dir = await _booksDir();
    final images = epub.Content?.Images ?? const {};

    // 1) 优先按 manifest properties="cover-image"(EPUB 3)
    final manifest = epub.Schema?.Package?.Manifest?.Items ?? const [];
    for (final item in manifest) {
      final props = item.Properties?.toLowerCase() ?? '';
      if (props.contains('cover-image') && item.Href != null) {
        final file = images[item.Href];
        if (file?.Content != null) {
          return _writeImage(dir, bookId, file!);
        }
      }
    }

    // 2) meta name="cover" → manifest id(EPUB 2)
    final metaItems = epub.Schema?.Package?.Metadata?.MetaItems ?? const [];
    String? coverMetaContent;
    for (final m in metaItems) {
      if (m.Name?.toLowerCase() == 'cover' && m.Content != null) {
        coverMetaContent = m.Content!.toLowerCase();
        break;
      }
    }
    if (coverMetaContent != null) {
      for (final item in manifest) {
        if (item.Id?.toLowerCase() == coverMetaContent && item.Href != null) {
          final file = images[item.Href];
          if (file?.Content != null) {
            return _writeImage(dir, bookId, file!);
          }
        }
      }
    }

    // 3) 图片 href/文件名包含 "cover"
    for (final entry in images.entries) {
      final key = entry.key.toLowerCase();
      final name = (entry.value.FileName ?? '').toLowerCase();
      if (key.contains('cover') || name.contains('cover')) {
        if (entry.value.Content != null) {
          return _writeImage(dir, bookId, entry.value);
        }
      }
    }

    // 4) 兜底:第一张图片
    if (images.isNotEmpty) {
      final first = images.values.first;
      if (first.Content != null) {
        return _writeImage(dir, bookId, first);
      }
    }

    return null;
  }

  /// 当 epubx 没有正确加载 Images 时,直接把 epub 当 zip 读,解析 OPF 找封面。
  static Future<String?> _extractCoverFromZip(
      Uint8List bytes, String bookId) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final containerXml = archive.findFile('META-INF/container.xml')?.content;
      if (containerXml == null) return null;

      final rootfile = XmlDocument.parse(String.fromCharCodes(containerXml))
          .findAllElements('rootfile')
          .firstOrNull;
      final opfPath = rootfile?.getAttribute('full-path');
      if (opfPath == null) return null;

      final opfBytes = archive.findFile(opfPath)?.content;
      if (opfBytes == null) return null;
      final opfDoc = XmlDocument.parse(String.fromCharCodes(opfBytes));
      final manifest = opfDoc.findAllElements('manifest').firstOrNull;
      if (manifest == null) return null;

      String? coverHref;

      // EPUB 3: properties="cover-image"
      for (final item in manifest.findAllElements('item')) {
        final props = (item.getAttribute('properties') ?? '').toLowerCase();
        if (props.contains('cover-image')) {
          coverHref = item.getAttribute('href');
          break;
        }
      }

      // EPUB 2: meta name="cover" content="cover-id"
      if (coverHref == null) {
        final package = opfDoc.findAllElements('package').firstOrNull;
        final metadata = package?.findElements('metadata').firstOrNull;
        String? coverId;
        for (final meta in metadata?.findElements('meta') ?? const []) {
          if ((meta.getAttribute('name') ?? '').toLowerCase() == 'cover') {
            coverId = meta.getAttribute('content');
            break;
          }
        }
        if (coverId != null) {
          for (final item in manifest.findAllElements('item')) {
            if ((item.getAttribute('id') ?? '') == coverId) {
              coverHref = item.getAttribute('href');
              break;
            }
          }
        }
      }

      // 路径可能是相对 OPF 目录的,需要转换
      if (coverHref != null) {
        final opfDir = p.dirname(opfPath);
        final resolved = opfDir == '.' ? coverHref : '$opfDir/$coverHref';
        final file = archive.findFile(resolved);
        if (file?.content != null) {
          final dir = await _booksDir();
          return _writeBytes(dir, bookId, file!.content);
        }
      }

      // 兜底:在 archive 中找任何带 cover 字样的图片
      for (final f in archive.files) {
        final name = f.name.toLowerCase();
        if (name.contains('cover') &&
            (name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png'))) {
          final dir = await _booksDir();
          return _writeBytes(dir, bookId, f.content);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _writeImage(
      Directory dir, String bookId, EpubByteContentFile file) async {
    final isPng = (file.ContentMimeType ?? '').toLowerCase().contains('png');
    final ext = isPng ? 'png' : 'jpg';
    final path = p.join(dir.path, '$bookId.$ext');
    await File(path).writeAsBytes(file.Content!);
    return path;
  }

  static Future<String> _writeBytes(
      Directory dir, String bookId, List<int> bytes) async {
    final magic = bytes.isNotEmpty ? bytes[0] : 0;
    // PNG magic: 0x89, JPEG magic: 0xFF
    final ext = magic == 0x89 ? 'png' : 'jpg';
    final path = p.join(dir.path, '$bookId.$ext');
    await File(path).writeAsBytes(bytes);
    return path;
  }

  static String _generateId(String title, String author) {
    final raw = '$title|$author';
    final hash = raw.hashCode.toRadixString(16);
    return 'book_${hash}_${DateTime.now().millisecondsSinceEpoch}';
  }

  static Future<Directory> _booksDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'novel_reader_books'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _bookFile(String bookId) async {
    final dir = await _booksDir();
    return File(p.join(dir.path, '$bookId.json'));
  }

  static Future<void> _writeBookFile(Book book) async {
    final file = await _bookFile(book.id);
    await file.writeAsString(jsonEncode(book.toJson()));
  }

  static Future<void> deleteBook(String bookId) async {
    final dir = await _booksDir();
    final jsonFile = File(p.join(dir.path, '$bookId.json'));
    if (await jsonFile.exists()) await jsonFile.delete();
    for (final ext in ['png', 'jpg']) {
      final cover = File(p.join(dir.path, '$bookId.$ext'));
      if (await cover.exists()) await cover.delete();
    }
  }

  static Future<Book?> loadBook(String bookId) async {
    final file = await _bookFile(bookId);
    if (!await file.exists()) return null;
    try {
      final json = await file.readAsString();
      return Book.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<List<BookMeta>> listBooks() async {
    final dir = await _booksDir();
    if (!await dir.exists()) return const [];
    final metas = <BookMeta>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json')) continue;
      try {
        final json = await entity.readAsString();
        final book = Book.fromJson(jsonDecode(json) as Map<String, dynamic>);
        metas.add(BookMeta.fromBook(book));
      } catch (_) {
        // 忽略损坏的文件
      }
    }
    metas.sort((a, b) => a.title.compareTo(b.title));
    return metas;
  }
}
