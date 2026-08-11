import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/app_theme.dart';

/// 书架网格中的书籍卡片。
class BookGridItem extends StatelessWidget {
  final BookMeta book;
  final ReadingProgress? progress;
  final VoidCallback onTap;

  const BookGridItem({
    super.key,
    required this.book,
    this.progress,
    required this.onTap,
  });

  /// 是否已读过(不处于(0,0)初始状态)。
  bool get _hasRead =>
      progress != null && (progress!.chapterIndex > 0 || progress!.pageIndex > 0);

  /// 阅读进度(0~1)。按"已读至第 N 章"估算: (chapterIndex+1) / 总章数。
  double get _progress {
    if (!_hasRead) return 0;
    final total = book.chapterCount;
    if (total <= 0) return 0;
    return ((progress!.chapterIndex + 1) / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildCover()),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 16,
              child: Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    final hasCover =
        book.coverPath != null && File(book.coverPath!).existsSync();
    final pct = _progress;
    final cover = Container(
      decoration: BoxDecoration(
        color: AppTheme.sidebarBg,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2A37).withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF1F2A37).withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCover
          ? Image.file(
              File(book.coverPath!),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stack) => _buildPlaceholderCover(),
            )
          : _buildPlaceholderCover(),
    );

    // 已读的书在封面底部叠加进度条 + 百分比
    if (!_hasRead) return cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 24,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 5),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4,
                      backgroundColor: Colors.white30,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE3EEFB), Color(0xFFCFE0F6)],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        book.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.primaryDark,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
