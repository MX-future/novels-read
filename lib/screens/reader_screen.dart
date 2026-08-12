import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/progress_store.dart';
import '../services/reader_settings.dart';
import '../utils/pagination.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  final VoidCallback onBack;

  const ReaderScreen({super.key, required this.book, required this.onBack});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _focusNode = FocusNode(debugLabel: 'reader');
  final _pagesCache = <int, List<String>>{};

  int _chapterIndex = 0;
  int _pageIndex = 0;
  bool _paginating = false;
  bool _ready = false;
  Size _pageSize = Size.zero;
  Timer? _saveDebouncer;
  bool _uiVisible = false;
  Timer? _uiHideTimer;
  String? _highlightKeyword;

  ReaderSettings get _settings => ReaderSettings.current.value;

  @override
  void initState() {
    super.initState();
    _init();
    ReaderSettings.current.addListener(_onSettingsChanged);
  }

  Future<void> _init() async {
    await ReaderSettings.load();
    final progress = await ProgressStore.load(widget.book.id);
    if (!mounted) return;
    final maxChapter = math.max(0, widget.book.chapters.length - 1);
    setState(() {
      _chapterIndex = progress.chapterIndex.clamp(0, maxChapter);
      _pageIndex = progress.pageIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onSettingsChanged() {
    // 字号/行距/边距变化,需要重新分页
    _pagesCache.clear();
    _pageSize = Size.zero;
    setState(() {});
    _paginateCurrentChapter();
  }

  @override
  void dispose() {
    _saveDebouncer?.cancel();
    _uiHideTimer?.cancel();
    _flushProgress();
    ReaderSettings.current.removeListener(_onSettingsChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _flushProgress() {
    ProgressStore.save(
      widget.book.id,
      ReadingProgress(chapterIndex: _chapterIndex, pageIndex: _pageIndex),
    );
  }

  void _scheduleSave() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 500), _flushProgress);
  }

  void _showUi() {
    _uiHideTimer?.cancel();
    if (!_uiVisible && mounted) setState(() => _uiVisible = true);
    _uiHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _uiVisible = false);
    });
  }

  void _hideUi() {
    _uiHideTimer?.cancel();
    if (_uiVisible && mounted) setState(() => _uiVisible = false);
  }

  TextStyle _textStyle() => TextStyle(
    fontSize: _settings.fontSize,
    height: _settings.lineHeight,
    color: _settings.theme.colors.$2,
    letterSpacing: 0.3,
    fontFamilyFallback: const ['PingFang SC', 'Heiti SC', '.SF NS SC'],
  );

  List<String> get _currentPages => _pagesCache[_chapterIndex] ?? const [];

  void _onLayout(Size size) {
    if (size == _pageSize) return;
    _pageSize = size;
    _pagesCache.clear();
    _paginateCurrentChapter();
  }

  Future<void> _paginateCurrentChapter() async {
    if (_pageSize == Size.zero) return;
    if (_pagesCache.containsKey(_chapterIndex)) {
      setState(() {
        _ready = true;
        _paginating = false;
      });
      return;
    }
    setState(() {
      _paginating = true;
      _ready = false;
    });
    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;
    final chapter = widget.book.chapters[_chapterIndex];
    // 分页高度须减去章节标题区域(标题最多2行 + 18间距),
    // 否则每页文本按满高分页,渲染时被标题压缩导致末行文字截断/遮挡
    final titleHeight = _titleReservedHeight(_pageSize.width);
    final textMaxHeight = math.max(80.0, _pageSize.height - titleHeight);
    final pages = TextPaginator.paginate(
      text: chapter.content,
      maxWidth: _pageSize.width,
      maxHeight: textMaxHeight,
      style: _textStyle(),
    );
    _pagesCache[_chapterIndex] = pages;
    if (!mounted) return;
    setState(() {
      _paginating = false;
      _ready = true;
      _pageIndex = _pageIndex.clamp(0, math.max(0, pages.length - 1));
    });
  }

  /// 测量章节标题占用的高度(最多 2 行 + 18px 间距),与 _PageContent 渲染一致。
  double _titleReservedHeight(double maxWidth) {
    final title = widget.book.chapters[_chapterIndex].title;
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    final h = painter.height + 18;
    painter.dispose();
    return h;
  }

  /// 键位映射:
  /// - 上 / 下:上一页 / 下一页
  /// - 左 / 右:上一章 / 下一章
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _nextPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _prevPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _nextChapter();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _prevChapter();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      widget.onBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _nextPage() {
    if (_paginating || !_ready) return;
    if (_pageIndex < _currentPages.length - 1) {
      setState(() => _pageIndex++);
      _scheduleSave();
    } else {
      _nextChapter();
    }
  }

  void _prevPage() {
    if (_paginating || !_ready) return;
    if (_pageIndex > 0) {
      setState(() => _pageIndex--);
      _scheduleSave();
    } else {
      _prevChapter();
    }
  }

  Future<void> _nextChapter() async {
    if (_chapterIndex >= widget.book.chapters.length - 1) return;
    setState(() {
      _chapterIndex++;
      _pageIndex = 0;
      _ready = false;
    });
    await _paginateCurrentChapter();
    _scheduleSave();
  }

  Future<void> _prevChapter() async {
    if (_chapterIndex <= 0) return;
    setState(() {
      _chapterIndex--;
      _ready = false;
    });
    await _paginateCurrentChapter();
    if (!mounted) return;
    setState(() => _pageIndex = math.max(0, _currentPages.length - 1));
    _scheduleSave();
  }

  Future<void> _jumpToChapter(int index) async {
    if (index < 0 || index >= widget.book.chapters.length) return;
    if (index == _chapterIndex) return;
    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _ready = false;
    });
    await _paginateCurrentChapter();
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderSettings>(
      valueListenable: ReaderSettings.current,
      builder: (context, settings, _) {
        final colors = settings.theme.colors;
        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: colors.$1,
            body: MouseRegion(
              onHover: (_) => _showUi(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 阅读主体内容
                  Padding(
                    padding: EdgeInsets.only(
                      top: 28,
                      bottom: 28,
                      left: settings.padding,
                      right: settings.padding,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final contentWidth = math.min(
                          constraints.maxWidth,
                          760.0,
                        );
                        final pageSize = Size(
                          contentWidth,
                          constraints.maxHeight,
                        );
                        if (pageSize != _pageSize) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _onLayout(pageSize);
                          });
                        }
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentWidth),
                            child: _buildPageArea(colors),
                          ),
                        );
                      },
                    ),
                  ),
                  // 顶部工具栏(悬浮显示)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    top: _uiVisible ? 0 : -56,
                    left: 0,
                    right: 0,
                    child: _buildTopBar(colors),
                  ),
                  // 底部工具栏(悬浮显示)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    bottom: _uiVisible ? 0 : -44,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(colors),
                  ),
                  // 左侧上一页按钮
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: _uiVisible ? 20 : -56,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _buildPageButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: _prevPage,
                        colors: colors,
                      ),
                    ),
                  ),
                  // 右侧下一页按钮
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    right: _uiVisible ? 20 : -56,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _buildPageButton(
                        icon: Icons.chevron_right_rounded,
                        onTap: _nextPage,
                        colors: colors,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageButton({
    required IconData icon,
    required VoidCallback onTap,
    required (Color, Color, Color, Color) colors,
  }) {
    return MouseRegion(
      onEnter: (_) => _showUi(),
      child: Tooltip(
        message: icon == Icons.chevron_left_rounded ? '上一页' : '下一页',
        child: Material(
          color: colors.$1.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            hoverColor: colors.$1.hoverOverlay(),
            child: Container(
              width: 42,
              height: 84,
              alignment: Alignment.center,
              child: Icon(icon, size: 28, color: colors.$3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar((Color, Color, Color, Color) colors) {
    return Container(
      height: 56,
      // 半透明背景: hover 显示工具栏时下方文字仍可隐约透出,不突兀遮挡
      color: colors.$1.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回书架 (Esc)',
            colors: colors,
            onTap: widget.onBack,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.$3,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _buildIconButton(
            icon: Icons.search_rounded,
            tooltip: '搜索',
            colors: colors,
            onTap: _showSearchPanel,
          ),
          const SizedBox(width: 4),
          _buildIconButton(
            icon: Icons.text_fields_rounded,
            tooltip: '阅读设置',
            colors: colors,
            onTap: _showSettingsPanel,
          ),
          const SizedBox(width: 4),
          _buildIconButton(
            icon: Icons.list_rounded,
            tooltip: '目录',
            colors: colors,
            onTap: _showChapterList,
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required (Color, Color, Color, Color) colors,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: colors.$1.hoverOverlay(),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: colors.$3),
          ),
        ),
      ),
    );
  }

  Widget _buildPageArea((Color, Color, Color, Color) colors) {
    if (_paginating || !_ready || _currentPages.isEmpty) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(colors.$4),
          ),
        ),
      );
    }
    final page = _currentPages[_pageIndex.clamp(0, _currentPages.length - 1)];
    // 无动画直接替换内容,避免翻页/切章时的跳动
    return _PageContent(
      key: ValueKey('page_${_chapterIndex}_$_pageIndex'),
      chapterTitle: widget.book.chapters[_chapterIndex].title,
      text: page,
      style: _textStyle(),
      colors: colors,
      highlight: _highlightKeyword,
    );
  }

  Widget _buildBottomBar((Color, Color, Color, Color) colors) {
    final totalPages = _currentPages.isEmpty ? 1 : _currentPages.length;
    final safePage = _currentPages.isEmpty ? 0 : _pageIndex + 1;
    final chapterProgress = _currentPages.isEmpty
        ? 0.0
        : (_pageIndex + 1) / totalPages;
    final bookProgress = widget.book.chapters.isEmpty
        ? 0.0
        : (_chapterIndex + chapterProgress) / widget.book.chapters.length;

    return Container(
      height: 44,
      color: colors.$1.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            '第 ${_chapterIndex + 1} / ${widget.book.chapters.length} 章',
            style: TextStyle(color: colors.$3, fontSize: 11),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Tooltip(
              message: '整书进度 ${(bookProgress * 100).toStringAsFixed(1)}%',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: bookProgress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: colors.$1.computeTrack(),
                  valueColor: AlwaysStoppedAnimation(colors.$4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$safePage / $totalPages',
            style: TextStyle(
              color: colors.$3,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChapterList() async {
    _uiHideTimer?.cancel();
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _ChapterListDialog(
        book: widget.book,
        currentIndex: _chapterIndex,
        colors: _settings.theme.colors,
      ),
    );
    if (selected != null && selected != _chapterIndex) {
      await _jumpToChapter(selected);
    } else if (mounted) {
      _focusNode.requestFocus();
      _showUi();
    }
  }

  Future<void> _showSearchPanel() async {
    _uiHideTimer?.cancel();
    final result = await showDialog<_SearchResult>(
      context: context,
      builder: (ctx) => _SearchDialog(
        book: widget.book,
        colors: _settings.theme.colors,
      ),
    );
    if (result != null) {
      final keyword = result.keyword;
      final chapterIdx = result.chapterIndex;

      // 如果是同一章节,直接搜索页码;否则先跳章再搜索
      if (chapterIdx == _chapterIndex) {
        _findAndJumpToKeywordPage(keyword);
      } else {
        setState(() {
          _chapterIndex = chapterIdx;
          _pageIndex = 0;
          _ready = false;
          _highlightKeyword = keyword;
        });
        await _paginateCurrentChapter();
        if (mounted) {
          _findAndJumpToKeywordPage(keyword);
        }
      }
      // 几秒后取消高亮
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) setState(() => _highlightKeyword = null);
      });
    } else if (mounted) {
      _focusNode.requestFocus();
      _showUi();
    }
  }

  /// 在当前章节的分页中查找包含关键字的页,并跳转过去。
  void _findAndJumpToKeywordPage(String keyword) {
    if (keyword.isEmpty) return;
    final lowerK = keyword.toLowerCase();
    for (var i = 0; i < _currentPages.length; i++) {
      if (_currentPages[i].toLowerCase().contains(lowerK)) {
        setState(() {
          _pageIndex = i;
          _highlightKeyword = keyword;
        });
        _scheduleSave();
        return;
      }
    }
    // 如果没找到(可能是分页缓存未命中),至少设置高亮
    setState(() => _highlightKeyword = keyword);
  }

  Future<void> _showSettingsPanel() async {
    _uiHideTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SettingsDialog(
        settings: _settings,
        colors: _settings.theme.colors,
      ),
    );
    if (mounted) {
      _focusNode.requestFocus();
      _showUi();
    }
  }
}

extension on Color {
  Color computeTrack() {
    return withValues(alpha: 0.1);
  }
}

class _PageContent extends StatelessWidget {
  final String chapterTitle;
  final String text;
  final TextStyle style;
  final (Color, Color, Color, Color) colors;
  final String? highlight;

  const _PageContent({
    super.key,
    required this.chapterTitle,
    required this.text,
    required this.style,
    required this.colors,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 章节标题(唯一显示位置)
        Text(
          chapterTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.$4,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _buildHighlightedText()),
      ],
    );
  }

  Widget _buildHighlightedText() {
    if (highlight == null || highlight!.isEmpty) {
      return Text(
        text,
        style: style,
        softWrap: true,
        textAlign: TextAlign.left,
      );
    }
    // 将文本按关键字分割,匹配部分高亮显示
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerKeyword = highlight!.toLowerCase();
    var start = 0;
    while (start < text.length) {
      final idx = lowerText.indexOf(lowerKeyword, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + highlight!.length),
          style: style.copyWith(
            backgroundColor: const Color(0xFFFFEB3B).withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = idx + highlight!.length;
    }
    return RichText(
      text: TextSpan(children: spans, style: style),
      softWrap: true,
      textAlign: TextAlign.left,
    );
  }
}

/// 搜索结果
class _SearchResult {
  final String keyword;
  final int chapterIndex;

  const _SearchResult({required this.keyword, required this.chapterIndex});
}

class _SearchDialog extends StatefulWidget {
  final Book book;
  final (Color, Color, Color, Color) colors;

  const _SearchDialog({super.key, required this.book, required this.colors});

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<_SearchMatch> _results = [];
  bool _searched = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _doSearch(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() => _searching = true);
    final matches = <_SearchMatch>[];
    final lowerK = k.toLowerCase();
    for (var i = 0; i < widget.book.chapters.length; i++) {
      final content = widget.book.chapters[i].content;
      final lower = content.toLowerCase();
      var idx = lower.indexOf(lowerK);
      var count = 0;
      String? snippet;
      while (idx >= 0 && count < 200) {
        count++;
        if (snippet == null && count == 1) {
          final snippetStart = (idx - 30).clamp(0, content.length);
          final snippetEnd = (idx + k.length + 60).clamp(0, content.length);
          snippet = content
              .substring(snippetStart, snippetEnd)
              .replaceAll('\n', ' ');
          if (snippetStart > 0) snippet = '...$snippet';
          if (snippetEnd < content.length) snippet = '$snippet...';
        }
        idx = lower.indexOf(lowerK, idx + lowerK.length);
      }
      if (count > 0) {
        matches.add(
          _SearchMatch(
            chapterIndex: i,
            chapterTitle: widget.book.chapters[i].title,
            count: count,
            snippet: snippet ?? '',
          ),
        );
      }
    }
    setState(() {
      _results = matches;
      _searched = true;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (bg, text, subtext, accent) = widget.colors;
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '搜索',
                    style: TextStyle(
                      color: text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    color: subtext,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: TextStyle(color: text),
                cursorColor: accent,
                decoration: InputDecoration(
                  hintText: '输入关键字搜索内容...',
                  hintStyle: TextStyle(
                    color: subtext.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(Icons.search, size: 18, color: subtext),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          color: subtext,
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _results = [];
                              _searched = false;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: bg.hoverOverlay(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: subtext.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: accent,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onSubmitted: _doSearch,
                onChanged: (v) => setState(() {}),
              ),
            ),
            if (_searched && _results.isEmpty && !_searching)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 40,
                        color: subtext.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '未找到匹配内容',
                        style: TextStyle(
                          color: subtext,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (!_searched)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 40,
                        color: subtext.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '输入关键字搜索全书内容',
                        style: TextStyle(
                          color: subtext,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final m = _results[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(
                          context,
                          _SearchResult(
                            keyword: _controller.text.trim(),
                            chapterIndex: m.chapterIndex,
                          ),
                        ),
                        hoverColor: bg.hoverOverlay(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '第 ${m.chapterIndex + 1} 章',
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      m.chapterTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${m.count} 处',
                                    style: TextStyle(
                                      color: subtext,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              if (m.snippet.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  m.snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: subtext,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchMatch {
  final int chapterIndex;
  final String chapterTitle;
  final int count;
  final String snippet;

  const _SearchMatch({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.count,
    required this.snippet,
  });
}

class _ChapterListDialog extends StatefulWidget {
  final Book book;
  final int currentIndex;
  final (Color, Color, Color, Color) colors;

  const _ChapterListDialog({
    required this.book,
    required this.currentIndex,
    required this.colors,
  });

  @override
  State<_ChapterListDialog> createState() => _ChapterListDialogState();
}

class _ChapterListDialogState extends State<_ChapterListDialog> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 打开目录后自动滚动定位到当前章节(居中显示)
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!mounted) return;
    if (!_scrollController.hasClients) {
      // 首帧可能尚未 attach,下一帧再试
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
      return;
    }
    // 与 ListView.itemExtent 保持一致,滚动偏移才能精确
    const itemExtent = 40.0;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    // 目标:让当前章节的中心对准视口中心
    final target =
        widget.currentIndex * itemExtent - (viewport - itemExtent) / 2;
    _scrollController.jumpTo(
      target.clamp(0.0, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bg, text, subtext, accent) = widget.colors;
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 420,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Text(
                    '目录',
                    style: TextStyle(
                      color: text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.book.chapters.length} 章',
                    style: TextStyle(
                      color: subtext,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    color: subtext,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: subtext.withValues(alpha: 0.18)),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 6),
                // 固定条目高度,保证滚动定位精确(与 _scrollToCurrent 一致)
                itemExtent: 40,
                itemCount: widget.book.chapters.length,
                itemBuilder: (context, index) {
                  final ch = widget.book.chapters[index];
                  final selected = index == widget.currentIndex;
                  return Material(
                    color: selected
                        ? accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, index),
                      hoverColor: bg.hoverOverlay(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: selected ? accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                ch.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? accent : text,
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  final ReaderSettings settings;
  final (Color, Color, Color, Color) colors;

  const _SettingsDialog({required this.settings, required this.colors});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _fontSize;
  late double _lineHeight;
  late double _padding;
  late ReaderTheme _theme;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings.fontSize;
    _lineHeight = widget.settings.lineHeight;
    _padding = widget.settings.padding;
    _theme = widget.settings.theme;
  }

  Future<void> _update() async {
    await ReaderSettings.save(
      ReaderSettings(
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        padding: _padding,
        theme: _theme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bg, text, subtext, accent) = widget.colors;
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '阅读设置',
                    style: TextStyle(
                      color: text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    color: subtext,
                  ),
                ],
              ),
              Divider(height: 20, color: subtext.withValues(alpha: 0.18)),
              _SliderRow(
                label: '字号',
                valueLabel: _fontSize.toStringAsFixed(0),
                value: _fontSize,
                min: 14,
                max: 24,
                divisions: 10,
                colors: widget.colors,
                onChanged: (v) {
                  setState(() => _fontSize = v);
                  _update();
                },
              ),
              _SliderRow(
                label: '行距',
                valueLabel: _lineHeight.toStringAsFixed(2),
                value: _lineHeight,
                min: 1.4,
                max: 2.4,
                divisions: 20,
                colors: widget.colors,
                onChanged: (v) {
                  setState(() => _lineHeight = v);
                  _update();
                },
              ),
              _SliderRow(
                label: '边距',
                valueLabel: _padding.toStringAsFixed(0),
                value: _padding,
                min: 40,
                max: 160,
                divisions: 12,
                colors: widget.colors,
                onChanged: (v) {
                  setState(() => _padding = v);
                  _update();
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '背景',
                  style: TextStyle(
                    color: subtext,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: ReaderTheme.values.map((t) {
                  final c = t.colors.$1;
                  final selected = t == _theme;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _theme = t);
                          _update();
                        },
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? accent
                                  : subtext.withValues(alpha: 0.3),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            t.label,
                            style: TextStyle(
                              color: t.colors.$2,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                '上 / 下:翻页    左 / 右:切章    Esc:返回',
                style: TextStyle(color: subtext, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final (Color, Color, Color, Color) colors;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, text, subtext, accent) = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: TextStyle(
                color: subtext,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: accent,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              valueLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
