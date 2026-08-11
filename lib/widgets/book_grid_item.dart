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
    return Container(
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
