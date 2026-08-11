import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

/// 将 EPUB 章节的 HTML 内容转换为带段落换行的纯文本。
class HtmlText {
  static const _blockTags = <String>{
    'p',
    'div',
    'br',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'blockquote',
    'pre',
    'tr',
    'hr',
    'section',
    'article',
    'header',
    'footer',
  };

  /// 这些标签的内容不应进入正文(脚本/样式/元信息等)。
  static const _skipTags = <String>{
    'script',
    'style',
    'head',
    'title',
    'meta',
    'link',
    'noscript',
    'template',
  };

  static String convert(String htmlString) {
    if (htmlString.isEmpty) return '';
    final doc = html_parser.parse(htmlString);
    final root = doc.body ?? doc.documentElement;
    if (root == null) return '';

    // 移除开头的标题标签(h1-h6),避免与 UI 中的章节标题重复
    final headings = root.querySelectorAll('h1, h2, h3, h4, h5, h6');
    for (final h in headings) {
      h.remove();
    }

    final buffer = StringBuffer();
    _walk(root, buffer);

    // 折叠行内空白,保留换行,移除空行
    final lines = buffer.toString().split('\n');
    final cleaned = <String>[];
    for (final line in lines) {
      final trimmed =
          line.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim();
      if (trimmed.isNotEmpty) cleaned.add(trimmed);
    }
    return cleaned.join('\n');
  }

  static void _walk(Node node, StringBuffer buffer) {
    if (node is Text) {
      final t = node.text;
      if (t.isNotEmpty) buffer.write(t);
      return;
    }
    if (node is Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) return; // 跳过 script/style 等,不输出其内容
      final isBlock = _blockTags.contains(tag);

      if (isBlock && !_endsWithNewline(buffer)) {
        buffer.write('\n');
      }
      for (final child in node.nodes) {
        _walk(child, buffer);
      }
      if (isBlock && tag != 'br' && !_endsWithNewline(buffer)) {
        buffer.write('\n');
      }
    }
  }

  static bool _endsWithNewline(StringBuffer buffer) {
    final s = buffer.toString();
    return s.isEmpty || s.endsWith('\n');
  }
}
