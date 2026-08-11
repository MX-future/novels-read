import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/app_theme.dart';

/// 侧边栏中的书籍条目。
class BookSidebarTile extends StatelessWidget {
  final BookMeta book;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const BookSidebarTile({
    super.key,
    required this.book,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? AppTheme.selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapUp: (details) => _showContextMenu(context, details),
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppTheme.hoverBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _buildCoverThumb(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, TapUpDetails details) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = details.globalPosition;
    final offset = overlay.localToGlobal(Offset.zero);
    final relX = localPosition.dx - offset.dx;
    final relY = localPosition.dy - offset.dy;

    showMenu<Null>(
      context: context,
      position: RelativeRect.fromLTRB(relX, relY, relX + 1, relY + 1),
      items: [
        PopupMenuItem(
          onTap: () => onTap(),
          child: const Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 16),
              SizedBox(width: 8),
              Text('打开'),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: onDelete,
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverThumb() {
    final hasCover = book.coverPath != null && File(book.coverPath!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 32,
        height: 44,
        child: hasCover
            ? Image.file(
                File(book.coverPath!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : Container(
                color: AppTheme.selectedBg,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  book.title.characters.first,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}
