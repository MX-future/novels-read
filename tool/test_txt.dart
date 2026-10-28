// 本地 txt 解析自检:编码探测 + 章节切分。
// 运行:dart run tool/test_txt.dart
import 'dart:io';

import 'package:novel_reader/services/txt_importer.dart';

void main() async {
  for (final path in ['/tmp/test_gbk.txt', '/tmp/test_utf8.txt']) {
    final f = File(path);
    if (!f.existsSync()) {
      stdout.writeln('跳过(不存在):$path');
      continue;
    }
    final bytes = f.readAsBytesSync();
    final text = TxtImporter.decodeBytes(bytes);
    final book = await TxtImporter.parseFile(path);
    stdout.writeln('=== $path ===');
    stdout.writeln('  解码后长度 ${text.length}');
    stdout.writeln('  首行:${text.split('\n').first}');
    stdout.writeln('  书名「${book.title}」 作者「${book.author}」');
    stdout.writeln('  章节数 ${book.chapters.length}');
    for (final c in book.chapters) {
      stdout.writeln('    - 「${c.title}」${c.content.length} 字');
    }
  }

  // 无章节标题时的兜底切分
  final plain = List.generate(400, (i) => '第 $i 段普通文字,没有章节标题。').join('\n\n');
  final fb = TxtImporter.splitChapters(plain, bookTitle: '无标题');
  stdout.writeln('=== 兜底切分 ===');
  stdout.writeln('  段落总数 400,切出 ${fb.length} 节,首节 ${fb.first.content.length} 字');
}
