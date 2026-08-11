import 'package:flutter/material.dart';

/// 将一段文本按可用空间拆分为多页,保证每页内容能完整渲染。
class TextPaginator {
  /// 把 [text] 按 [maxWidth] x [maxHeight] 与 [style] 拆分为多页。
  static List<String> paginate({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) return [text];
    if (text.isEmpty) return [''];

    final fullPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    fullPainter.layout(maxWidth: maxWidth);

    // 整章一页放得下
    if (fullPainter.height <= maxHeight) {
      final result = [text];
      fullPainter.dispose();
      return result;
    }

    final lines = fullPainter.computeLineMetrics();
    if (lines.isEmpty) {
      fullPainter.dispose();
      return [text];
    }

    final pages = <String>[];
    int currentLine = 0;

    while (currentLine < lines.length) {
      final startLine = lines[currentLine];
      final pageTopY = startLine.baseline - startLine.ascent;
      final pageBottomY = pageTopY + maxHeight;

      int endLine = currentLine;
      // 找出最后一行,其"底部"仍在可见区域内(避免行尾被截断)
      for (int i = currentLine; i < lines.length; i++) {
        final line = lines[i];
        final lineTopY = line.baseline - line.ascent;
        final lineBottomY = lineTopY + line.height;
        // 只保证完整行可见:若某行底部已超出页底,则本页到此为止
        if (i > currentLine && lineBottomY > pageBottomY + 0.5) break;
        endLine = i;
      }

      // 起始字符偏移:取本页第一行的左边界
      final startPos = fullPainter.getPositionForOffset(
        Offset(startLine.left, startLine.baseline - 1),
      );
      final startBoundary = fullPainter.getLineBoundary(startPos);
      final startOffset = startBoundary.start;

      // 结束字符偏移:取本页最后一行末尾(包含换行符)
      final endLineMetrics = lines[endLine];
      final endPos = fullPainter.getPositionForOffset(
        Offset(
          endLineMetrics.left + endLineMetrics.width - 0.5,
          endLineMetrics.baseline - 1,
        ),
      );
      final endBoundary = fullPainter.getLineBoundary(endPos);
      // getLineBoundary.end 通常不包含行尾换行符,这里手动补上,
      // 否则换页时换行符会被丢失,导致拼接后行间粘连。
      int endOffset = endBoundary.end;
      if (endOffset < text.length && text[endOffset] == '\n') {
        endOffset += 1;
      }

      if (endOffset <= startOffset) {
        // 安全兜底:取到文本末尾
        pages.add(text.substring(startOffset));
        break;
      }

      pages.add(text.substring(startOffset, endOffset));

      if (endLine >= lines.length - 1) break;
      currentLine = endLine + 1;
    }

    fullPainter.dispose();
    return pages;
  }
}
