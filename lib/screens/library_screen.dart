import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../services/epub_service.dart';
import '../services/progress_store.dart';
import '../services/txt_importer.dart';
import '../theme/app_theme.dart';
import '../widgets/book_grid_item.dart';
import '../widgets/book_sidebar_tile.dart';
import 'fanqie_import_dialog.dart';
import 'reader_screen.dart';

/// 批量导入的实时进度。total 为待处理文件数,done 为已处理数。
///
/// 用 ChangeNotifier 而不是 ValueNotifier:进度字段是原地累加的,
/// ValueNotifier 对同一实例赋值不会触发通知,界面会一直停在第一帧。
class _BatchProgress extends ChangeNotifier {
  _BatchProgress({required this.total});

  final int total;
  int done = 0;
  int imported = 0;
  int skipped = 0;
  int failed = 0;
  bool cancelled = false;
  String current = '';
  final List<String> failedNames = [];

  void update(void Function(_BatchProgress p) fn) {
    fn(this);
    notifyListeners();
  }
}

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

  /// 导入本地小说:文件可多选(epub / txt),选完统一走批量流程。
  Future<void> _importBook() async {
    if (_importing) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt'],
      allowMultiple: true,
      dialogTitle: '导入小说(可按住 ⌘/⇧ 多选)',
    );
    if (result == null) return;
    final paths =
        result.files.map((f) => f.path).whereType<String>().toList(growable: false);
    if (paths.isEmpty) return;
    await _runBatchImport(paths);
  }

  /// 批量导入:选择一个文件夹,递归扫描其中所有 epub / txt。
  Future<void> _importFolder() async {
    if (_importing) return;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择小说文件夹(含子文件夹)',
    );
    if (dir == null) return;

    final paths = <String>[];
    try {
      await for (final e
          in Directory(dir).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final lower = e.path.toLowerCase();
        if (lower.endsWith('.epub') || lower.endsWith('.txt')) {
          paths.add(e.path);
        }
      }
    } catch (e) {
      _showToast('读取文件夹失败:$e');
      return;
    }
    if (paths.isEmpty) {
      _showToast('该文件夹内没有找到 epub / txt 文件');
      return;
    }
    paths.sort();
    await _runBatchImport(paths);
  }

  /// 逐本导入 [paths],带进度弹窗、重复书跳过与失败汇总。
  Future<void> _runBatchImport(List<String> paths) async {
    if (_importing) return;
    setState(() => _importing = true);

    // 已有书籍 + 已导入过同一个源文件的,均视为重复
    final existingKeys = <String>{
      for (final b in _books) '${b.title}|${b.author}',
    };
    final existingSources = <String>{
      for (final b in _books) b.sourcePath,
    };

    final progress = _BatchProgress(total: paths.length);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildBatchDialog(progress),
    ));
    // 让弹窗先完成一帧渲染,避免长任务把它卡住不显示
    await Future<void>.delayed(const Duration(milliseconds: 120));

    var cancelRequested = false;

    for (var i = 0; i < paths.length; i++) {
      if (progress.cancelled) {
        cancelRequested = true;
        break;
      }
      final path = paths[i];
      final name = p.basename(path);
      progress.update((p) {
        p.current = name;
        p.done = i;
      });
      await Future<void>.delayed(Duration.zero);

      if (existingSources.contains(path)) {
        progress.update((p) {
          p.skipped += 1;
          p.done = i + 1;
        });
        continue;
      }

      try {
        final lower = path.toLowerCase();
        final book = lower.endsWith('.txt')
            ? await TxtImporter.parseFile(path)
            : await EpubService.importFromFile(path);
        if (lower.endsWith('.txt')) {
          await EpubService.saveBook(book);
        }

        final key = '${book.title}|${book.author}';
        if (existingKeys.contains(key)) {
          // 同书名同作者已在架上,删掉刚写入的副本并计为跳过
          await EpubService.deleteBook(book.id);
          progress.update((p) => p.skipped += 1);
        } else {
          existingKeys.add(key);
          existingSources.add(path);
          progress.update((p) => p.imported += 1);
        }
      } catch (_) {
        progress.update((p) {
          p.failed += 1;
          p.failedNames.add(name);
        });
      }
      progress.update((p) => p.done = i + 1);
    }

    final importedCount = progress.imported;
    final skippedCount = progress.skipped;
    final failedCount = progress.failed;
    final failedNames = List<String>.from(progress.failedNames);
    if (mounted && navigator.canPop()) navigator.pop();
    // 等退场动画走完再释放,否则 builder 可能在动画期间访问已 dispose 的通知器
    await Future<void>.delayed(const Duration(milliseconds: 250));
    progress.dispose();

    await _refresh();
    if (mounted) setState(() => _importing = false);

    if (!mounted) return;
    final parts = <String>['导入 $importedCount 本'];
    if (skippedCount > 0) parts.add('跳过重复 $skippedCount');
    if (failedCount > 0) {
      parts.add('失败 $failedCount');
      final names = failedNames.take(3).join('、');
      parts.add('($names${failedNames.length > 3 ? ' 等' : ''})');
    }
    if (cancelRequested) parts.add('已手动停止');
    _showToast(parts.join(' · '));
  }

  Widget _buildBatchDialog(_BatchProgress progress) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.library_add_outlined, size: 20, color: AppTheme.primary),
          SizedBox(width: 8),
          Text('批量导入', style: TextStyle(color: AppTheme.textPrimary)),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) {
            final ratio = progress.total == 0
                ? 0.0
                : (progress.done / progress.total).clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEAF2FC),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${progress.done} / ${progress.total} · 成功 ${progress.imported}'
                  '${progress.skipped > 0 ? ' · 跳过 ${progress.skipped}' : ''}'
                  '${progress.failed > 0 ? ' · 失败 ${progress.failed}' : ''}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  progress.current.isEmpty ? '准备中…' : progress.current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        ListenableBuilder(
          listenable: progress,
          builder: (context, _) => TextButton(
            onPressed: progress.cancelled
                ? null
                : () {
                    // 只置标记,由循环自然收尾,避免打断正在写入的文件
                    progress.update((p) => p.cancelled = true);
                  },
            child: const Text('取消',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ),
      ],
    );
  }

  /// 在线导入番茄小说:粘贴链接/ID → 选范围 → 下载并入架。
  Future<void> _importFanqie() async {
    final result = await showFanqieImportDialog(context);
    if (result == null || !mounted) return;
    await _refresh();

    String msg;
    if (result.cancelled) {
      final kept = result.fetched + result.refreshed + result.already;
      msg = kept > 0
          ? '已取消:《${result.title}》保留已下载 $kept 章,可再次导入续传'
          : '已取消下载';
    } else if (result.fetched + result.refreshed + result.already == 0) {
      msg = '《${result.title}》没有可下载的免费章节'
          '${result.lockedSkip > 0 ? '(VIP ${result.lockedSkip} 章已跳过)' : ''}';
    } else {
      final parts = <String>[
        '《${result.title}》导入完成:新增 ${result.fetched} 章'
      ];
      if (result.refreshed > 0) parts.add('刷新 ${result.refreshed} 章');
      if (result.already > 0) parts.add('已有 ${result.already} 章跳过');
      if (result.lockedSkip > 0) parts.add('跳过 VIP ${result.lockedSkip} 章');
      if (result.failed > 0) parts.add('失败 ${result.failed} 章');
      msg = parts.join(' · ');
      // 有既有章节被跳过且本次未执行刷新时,提示可开启覆盖更新
      if (result.already > 0 && result.refreshed == 0) {
        msg += ';若打开后内容未更新,可重新导入并勾选「覆盖更新」';
      }
    }
    _showToast(msg);
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
        // 顶部留出交通灯区域(40px)
        padding: const EdgeInsets.fromLTRB(12, 68, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _buildCollapseToggle()),
            const SizedBox(height: 16),
            _buildImportButton(),
            const SizedBox(height: 10),
            _buildFolderButton(collapsed: true),
            const SizedBox(height: 10),
            _buildFanqieImportButton(),
          ],
        ),
      );
    }
    return Container(
      // 顶部留出交通灯区域(40px)
      padding: const EdgeInsets.fromLTRB(20, 68, 12, 16),
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
          Row(
            children: [
              Expanded(child: _buildImportButton()),
              const SizedBox(width: 8),
              _buildFolderButton(),
            ],
          ),
          const SizedBox(height: 10),
          _buildFanqieImportButton(),
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

  /// 批量导入文件夹:选一个目录,递归扫描里面的 epub / txt 一次性入架。
  Widget _buildFolderButton({bool collapsed = false}) {
    const bg = Color(0xFFE8F1FC);
    const hover = Color(0xFFD8E7F8);
    const icon = Icon(Icons.folder_copy_outlined,
        size: 18, color: AppTheme.primaryDark);

    if (collapsed) {
      return Tooltip(
        message: '批量导入文件夹',
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: _importing ? null : _importFolder,
            borderRadius: BorderRadius.circular(8),
            hoverColor: hover,
            child: const SizedBox(
              height: 40,
              child: Center(child: icon),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: '批量导入文件夹',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _importing ? null : _importFolder,
          borderRadius: BorderRadius.circular(8),
          hoverColor: hover,
          child: Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            child: icon,
          ),
        ),
      ),
    );
  }

  Widget _buildFanqieImportButton() {
    const bg = Color(0xFFE8F1FC);
    const hover = Color(0xFFD8E7F8);
    if (_sidebarCollapsed) {
      return Tooltip(
        message: '在线导入番茄小说',
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: _importFanqie,
            borderRadius: BorderRadius.circular(8),
            hoverColor: hover,
            child: const SizedBox(
              height: 40,
              child: Icon(Icons.cloud_download_outlined,
                  size: 20, color: AppTheme.primaryDark),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _importFanqie,
          borderRadius: BorderRadius.circular(8),
          hoverColor: hover,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_download_outlined,
                    size: 15, color: AppTheme.primaryDark),
                SizedBox(width: 6),
                Text(
                  '在线导入(番茄)',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
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
            '书架为空,点击上方按钮导入小说',
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
      // 顶部留出交通灯区域(40px),让空书库提示整体下移不被遮挡
      padding: const EdgeInsets.only(top: 40),
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
              '批量导入本地 epub / txt,或在线导入番茄小说',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            // 两个按钮统一宽度,避免因文字长短造成宽窄不一
            SizedBox(width: 236, child: _buildInlineImportButton()),
            const SizedBox(height: 10),
            SizedBox(width: 236, child: _buildInlineFanqieButton()),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _importing ? Icons.hourglass_top : Icons.file_download_outlined,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                _importing ? '导入中…' : '导入本地小说',
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

  Widget _buildInlineFanqieButton() {
    return Material(
      color: const Color(0xFFE8F1FC),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _importFanqie,
        borderRadius: BorderRadius.circular(8),
        hoverColor: const Color(0xFFD8E7F8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_download_outlined,
                  size: 16, color: AppTheme.primaryDark),
              SizedBox(width: 8),
              Text(
                '在线导入(番茄小说)',
                style: TextStyle(
                  color: AppTheme.primaryDark,
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

  /// 计算书架网格单元格宽高比,保证封面 3:4 不变形。
  /// 单元格高度 = 封面(宽×4/3) + 标题(36) + 间距(8+2) + 作者(16)。
  double _gridAspectRatio(double totalWidth, int cols) {
    const crossSpacing = 22.0;
    final colWidth = (totalWidth - crossSpacing * (cols - 1)) / cols;
    const extra = 36.0 + 16.0 + 8.0 + 2.0;
    final cellHeight = colWidth * 4 / 3 + extra;
    return colWidth / cellHeight;
  }

  Widget _buildGridView() {
    return Container(
      color: AppTheme.background,
      // 顶部留出交通灯区域(40px)
      padding: const EdgeInsets.fromLTRB(48, 76, 48, 36),
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
            '共 ${_books.length} 本',
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
                    // 动态比例:封面固定 3:4,加上标题/作者固定高度后,
                    // 缩放窗口时封面宽高比保持不变
                    childAspectRatio: _gridAspectRatio(constraints.maxWidth, cols),
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
