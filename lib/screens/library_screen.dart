import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/epub_service.dart';
import '../services/progress_store.dart';
import '../theme/app_theme.dart';
import '../widgets/book_grid_item.dart';
import '../widgets/book_sidebar_tile.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<BookMeta> _books = const [];
  Map<String, ReadingProgress> _progress = {};
  String? _selectedBookId;
  Book? _openedBook;
  bool _importing = false;
  bool _loading = true;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final books = await EpubService.listBooks();
    final progress = await ProgressStore.loadAll();
    if (!mounted) return;
    setState(() {
      _books = books;
      _progress = progress;
      _loading = false;
    });
  }

  Future<void> _importBook() async {
    if (_importing) return;
    setState(() => _importing = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        allowMultiple: true,
        dialogTitle: '导入小说',
      );
      if (result == null || result.files.isEmpty) return;

      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        try {
          await EpubService.importFromFile(path);
        } catch (e) {
          _showToast('导入失败:${f.name}');
        }
      }
      await _refresh();
      _showToast('导入完成');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openBook(BookMeta meta) async {
    final book = await EpubService.loadBook(meta.id);
    if (book == null || !mounted) {
      _showToast('无法打开此书');
      return;
    }
    setState(() {
      _selectedBookId = meta.id;
      _openedBook = book;
      // 注意:不再强制收起侧边栏,阅读时由 _buildSidebar 按 _openedBook 决定宽度 0
    });
  }

  void _closeBook() {
    setState(() {
      _selectedBookId = null;
      _openedBook = null;
    });
    _refresh();
  }

  Future<void> _deleteBook(BookMeta meta) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '删除书籍',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要从书架移除《${meta.title}》吗?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await EpubService.deleteBook(meta.id);
    await ProgressStore.clear(meta.id);
    await _refresh();
    if (_selectedBookId == meta.id) _closeBook();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF2A3B4D),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppTheme.background,
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildMainArea()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final reading = _openedBook != null; // 阅读时完全隐藏侧边栏
    final collapsed = _sidebarCollapsed;
    final width = reading ? 0.0 : (collapsed ? 64.0 : 240.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: const BoxDecoration(
        color: AppTheme.sidebarBg,
        border: Border(right: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      // 动画过程中裁剪溢出内容,避免宽度过渡时出现文字撑出的红色错误
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebarHeader(),
          if (!collapsed && !reading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Text(
                    '书库',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_books.length}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: (collapsed || reading)
                ? const SizedBox.shrink()
                : _buildBookList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    final collapsed = _sidebarCollapsed;
    if (collapsed) {
      // 收缩状态:只显示居中的展开按钮 + 导入按钮
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _buildCollapseToggle()),
            const SizedBox(height: 16),
            _buildImportButton(),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 22,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                '书架',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              _buildCollapseToggle(),
            ],
          ),
          const SizedBox(height: 16),
          _buildImportButton(),
        ],
      ),
    );
  }

  Widget _buildCollapseToggle() {
    return Tooltip(
      message: _sidebarCollapsed ? '展开侧边栏' : '收起侧边栏',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppTheme.hoverBg,
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(
              _sidebarCollapsed
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    if (_sidebarCollapsed) {
      return Tooltip(
        message: '导入小说',
        child: Material(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: _importing ? null : _importBook,
            borderRadius: BorderRadius.circular(8),
            hoverColor: AppTheme.primaryDark,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              child: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.add, size: 20, color: Colors.white),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _importing ? null : _importBook,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_importing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.add, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  _importing ? '导入中…' : '导入小说',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookList() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_books.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Text(
            '点击上方按钮导入 epub 小说',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final meta = _books[index];
        final selected = meta.id == _selectedBookId;
        return BookSidebarTile(
          book: meta,
          selected: selected,
          progress: _progress[meta.id],
          onTap: () => _openBook(meta),
          onDelete: () => _deleteBook(meta),
        );
      },
    );
  }

  Widget _buildMainArea() {
    if (_openedBook != null) {
      return ReaderScreen(
        key: ValueKey('reader_${_openedBook!.id}'),
        book: _openedBook!,
        onBack: _closeBook,
      );
    }
    if (_books.isEmpty) return _buildEmptyState();
    return _buildGridView();
  }

  Widget _buildEmptyState() {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.sidebarBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                size: 44,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '还没有书籍',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '导入 epub 格式的小说开始阅读',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _buildInlineImportButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineImportButton() {
    return Material(
      color: AppTheme.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _importing ? null : _importBook,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _importing ? Icons.hourglass_top : Icons.file_download_outlined,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                _importing ? '导入中…' : '选择 epub 文件',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView() {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(48, 36, 48, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '书库',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '共 ${_books.length} 本 · 按 ← / → 翻页,↑ / ↓ 切换章节',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = math.max(3, (constraints.maxWidth / 180).floor());
                return GridView.builder(
                  itemCount: _books.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 22,
                    mainAxisSpacing: 26,
                  ),
                  itemBuilder: (context, index) {
                    final meta = _books[index];
                    return BookGridItem(
                      book: meta,
                      progress: _progress[meta.id],
                      onTap: () => _openBook(meta),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
