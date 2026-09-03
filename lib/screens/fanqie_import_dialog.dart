import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fanqie/fanqie_service.dart';
import '../theme/app_theme.dart';

/// 番茄小说在线导入的结果摘要(供书架页弹提示)。
class FanqieImportResult {
  final String title;
  final bool cancelled;
  final int total;
  final int fetched;
  final int already;
  final int lockedSkip;
  final int failed;

  const FanqieImportResult({
    required this.title,
    required this.cancelled,
    required this.total,
    required this.fetched,
    required this.already,
    required this.lockedSkip,
    required this.failed,
  });
}

/// 在线导入番茄小说:贴链接/ID → 确认书籍与范围 → 下载并入架。
///
/// 下载过程每 10 章落盘一次,取消后已下载章节保留,可再次导入续传。
Future<FanqieImportResult?> showFanqieImportDialog(BuildContext context) {
  return showDialog<FanqieImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const FanqieImportDialog(),
  );
}

class FanqieImportDialog extends StatefulWidget {
  const FanqieImportDialog({super.key});

  @override
  State<FanqieImportDialog> createState() => _FanqieImportDialogState();
}

class _FanqieImportDialogState extends State<FanqieImportDialog> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _cookieCtl = TextEditingController();
  final TextEditingController _startCtl = TextEditingController();
  final TextEditingController _endCtl = TextEditingController();

  bool _busy = false; // 正在查询书籍
  bool _downloading = false; // 正在下载
  bool _cancelRequested = false;
  bool _cookieExpanded = false; // Cookie 输入区展开
  bool _relayEnabled = false; // 备用中转源开关(默认关,实验性)
  String? _error;
  String? _fieldError; // 范围输入校验错误
  FanqieBookMeta? _meta;
  FanqieDownloadStats? _stats;

  @override
  void dispose() {
    _input.dispose();
    _cookieCtl.dispose();
    _startCtl.dispose();
    _endCtl.dispose();
    super.dispose();
  }

  Future<void> _queryBook() async {
    if (_busy || _downloading) return;
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请粘贴番茄小说链接或书籍 ID');
      return;
    }
    final bookId = FanqieService.parseBookId(raw);
    if (bookId == null) {
      setState(() => _error = '未识别到书籍 ID,请粘贴 https://fanqienovel.com 的书籍链接或纯数字 ID');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
      _meta = null;
    });
    try {
      final meta = await FanqieService.fetchBookMeta(bookId);
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().isEmpty ? '查询失败,请检查网络' : '$e';
      });
    }
  }

  Future<void> _startDownload() async {
    final meta = _meta;
    if (meta == null || _downloading) return;
    final n = meta.chapters.length;
    final sRaw = _startCtl.text.trim();
    final eRaw = _endCtl.text.trim();
    int? s = sRaw.isEmpty ? null : int.tryParse(sRaw);
    int? e = eRaw.isEmpty ? null : int.tryParse(eRaw);
    if (sRaw.isNotEmpty && s == null) {
      setState(() => _fieldError = '起始章节需为数字');
      return;
    }
    if (eRaw.isNotEmpty && e == null) {
      setState(() => _fieldError = '结束章节需为数字');
      return;
    }
    if (s != null && s < 1) s = 1;
    if (e != null && e > n) e = n;
    if (s != null && e != null && s > e) {
      setState(() => _fieldError = '起始章节不能大于结束章节');
      return;
    }
    setState(() {
      _downloading = true;
      _cancelRequested = false;
      _fieldError = null;
      _stats = null;
    });
    try {
      final stats = await FanqieService.downloadBook(
        bookId: meta.bookId,
        meta: meta,
        catalog: meta.chapters,
        startOrder: s,
        endOrder: e,
        cookie: _cookieCtl.text.trim().isEmpty
            ? null
            : _cookieCtl.text.trim(),
        useRelay: _relayEnabled,
        onProgress: (v) {
          if (mounted) setState(() => _stats = v);
        },
        isCancelled: () async => _cancelRequested,
      );
      if (!mounted) return;
      Navigator.of(context).pop(FanqieImportResult(
        title: meta.title,
        cancelled: _cancelRequested,
        total: stats.total,
        fetched: stats.fetched,
        already: stats.already,
        lockedSkip: stats.lockedSkipped,
        failed: stats.failed,
      ));
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载中断:${err.toString().isEmpty ? '未知错误' : err}';
      });
    }
  }

  void _cancelDownload() {
    if (!_cancelRequested) setState(() => _cancelRequested = true);
  }

  static String _fmtWord(int n) {
    if (n < 10000) return '$n 字';
    return '${(n / 10000).toStringAsFixed(1)} 万字';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 520,
        child: _downloading ? _buildDownloading() : _buildSetup(),
      ),
    );
  }

  // ---------- 输入 / 确认阶段 ----------

  Widget _buildSetup() {
    final meta = _meta;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitle(),
          const SizedBox(height: 18),
          if (meta == null) _buildInputForm() else _buildConfirmForm(meta),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1FC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.cloud_download_outlined,
              size: 20, color: AppTheme.primary),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            '在线导入番茄小说',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _input,
          enabled: !_busy,
          autofocus: true,
          onSubmitted: (_) => _queryBook(),
          decoration: InputDecoration(
            hintText: '粘贴书籍链接或书籍 ID',
            hintStyle:
                const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
            prefixIcon: const Icon(Icons.link, size: 18, color: AppTheme.primary),
            filled: true,
            fillColor: const Color(0xFFF5F8FC),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '支持两种输入:书籍链接(如 fanqienovel.com/page/…)或纯书籍 ID(长串数字)',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFD64545), fontSize: 12),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('取消',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 34,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: _busy ? null : _queryBook,
                child: _busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('查询书籍',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirmForm(FanqieBookMeta meta) {
    final n = meta.chapters.length;
    final locked = meta.lockedCount;
    final free = n - locked;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBookRow(meta),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 14),
          const Text('下载范围',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _startCtl,
                  enabled: !_downloading,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _rangeDeco('起始章(可空)'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('—',
                    style: TextStyle(
                        color: AppTheme.textTertiary, fontSize: 15)),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _endCtl,
                  enabled: !_downloading,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _rangeDeco('结束章(可空)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta.lockedCount > 0 && !_cookieExpanded && !_relayEnabled
                ? '留空表示从第 1 章到最后一章;付费/VIP 章节默认跳过,可展开下方"登录 Cookie"或开启"备用源"后下载'
                : '留空表示从第 1 章到最后一章',
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          ),
          if (meta.lockedCount > 0) ...[
            const SizedBox(height: 10),
            _buildCookieSection(),
            const SizedBox(height: 6),
            _buildRelayToggle(),
          ],
          if (_fieldError != null) ...[
            const SizedBox(height: 8),
            Text(_fieldError!,
                style: const TextStyle(color: Color(0xFFD64545), fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _meta = null;
                    _error = null;
                  });
                },
                child: const Text('重新输入',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  onPressed: _startDownload,
                  child: const Text('开始下载',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          // 预览:书架无此书时提示将新加入
          if (free == 0 && !_cookieExpanded && !_relayEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('该范围全部为付费章节,填写"登录 Cookie"或开启"备用源"后才能下载',
                  style: TextStyle(color: Color(0xFFD64545), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  /// 登录 Cookie 输入区:粘贴浏览器登录番茄后的 Cookie,用于下载 VIP/付费章。
  Widget _buildCookieSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _cookieExpanded = !_cookieExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  _cookieExpanded
                      ? Icons.expand_less
                      : Icons.key_rounded,
                  size: 15,
                  color: const Color(0xFFB07C2F),
                ),
                const SizedBox(width: 6),
                Text(
                  _cookieExpanded
                      ? '收起登录 Cookie(可选)'
                      : '登录 Cookie(可选) — 下载 VIP/付费章节',
                  style: const TextStyle(
                    color: Color(0xFFB07C2F),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_cookieExpanded) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _cookieCtl,
            enabled: !_downloading,
            maxLines: 2,
            minLines: 2,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '粘贴 Cookie(浏览器登录 fanqienovel.com 后,从开发者工具复制)',
              hintStyle: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFFFFAF1),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFF0DFC0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFF0DFC0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '说明:在浏览器登录番茄小说后按 F12,切到 Network 标签,点任意请求,'
            '复制 Cookie 请求头的值粘贴到上方。Cookie 仅在本次下载时携带、'
            '不保存到书架;账号无该章阅读权限时仍会跳过——网页端 VIP 正文只能'
            '靠账号权限获取。若该书在手机 App 上游客即可免费读(网页却要 VIP),'
            '请改用下方"备用源"。',
            style: TextStyle(
                color: AppTheme.textTertiary, fontSize: 11, height: 1.5),
          ),
        ],
      ],
    );
  }

  /// 备用中转源开关(实验性,默认关):部分书"网页需 VIP、App 游客可免费读",
  /// 官方 web 无 Cookie/VIP 通道取不到全文;开启后锁章将尝试从社区中转源取文。
  Widget _buildRelayToggle() {
    final on = _relayEnabled;
    return InkWell(
      onTap: _downloading
          ? null
          : () => setState(() => _relayEnabled = !_relayEnabled),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEAF2FC) : const Color(0xFFF5F8FC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on ? AppTheme.primary : AppTheme.divider,
            width: on ? 1.2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.route_outlined,
                size: 15,
                color: on ? AppTheme.primary : const Color(0xFF9AA7B8)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    on ? '备用源已开启' : '备用源(实验性)',
                    style: TextStyle(
                      color: on ? AppTheme.primary : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    on
                        ? '锁章将先走官方通道,拿不到全文再从社区中转取文。'
                            '正文经第三方服务器中转,非官方通道、可能随时失效。'
                        : '适用于:手机 App 游客即可免费读、网页却要 VIP 的书。',
                    style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _buildTogglePill(on),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTogglePill(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 34,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? AppTheme.primary : const Color(0xFFC9D4E0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  InputDecoration _rangeDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFFF5F8FC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
      ),
    );
  }

  Widget _buildBookRow(FanqieBookMeta meta) {
    final n = meta.chapters.length;
    final free = n - meta.lockedCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCover(meta),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meta.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('共 $n 章', const Color(0xFFEFF3F8),
                      AppTheme.textSecondary),
                  _chip('免费 $free 章', const Color(0xFFE8F1FC),
                      AppTheme.primaryDark),
                  if (meta.lockedCount > 0)
                    _chip('VIP ${meta.lockedCount} 章', const Color(0xFFFFF4E6),
                        const Color(0xFFB07C2F)),
                  if (meta.wordCount > 0)
                    _chip(_fmtWord(meta.wordCount), const Color(0xFFEFF3F8),
                        AppTheme.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCover(FanqieBookMeta meta) {
    final url = meta.coverUrl;
    Widget fallback() {
      return Container(
        width: 84,
        height: 112,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE3EEFB), Color(0xFFCFE0F6)],
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book_rounded,
            size: 28, color: AppTheme.primaryDark),
      );
    }

    if (url == null || url.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: 84,
        height: 112,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: 84,
            height: 112,
            color: const Color(0xFFF5F8FC),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.primary)),
            ),
          );
        },
      ),
    );
  }

  // ---------- 下载阶段 ----------

  Widget _buildDownloading() {
    final stats = _stats;
    final meta = _meta;
    final total = stats?.total ?? meta?.chapters.length ?? 0;
    final done = stats == null
        ? 0
        : stats.fetched + stats.already + stats.lockedSkipped + stats.failed;
    final value = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('正在下载',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                total <= 0 ? '' : '$done / $total',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: const Color(0xFFEDF1F6),
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            stats?.currentTitle == null
                ? '准备中…'
                : '正在获取:${stats!.currentTitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            stats == null
                ? ''
                : '新下载 ${stats.fetched} 章'
                    '${stats.already > 0 ? ' · 已有 ${stats.already} 章' : ''}'
                    '${stats.lockedSkipped > 0 ? ' · 跳过 VIP ${stats.lockedSkipped} 章' : ''}'
                    '${stats.failed > 0 ? ' · 失败 ${stats.failed} 章' : ''}',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelRequested ? null : _cancelDownload,
                child: Text(
                  _cancelRequested ? '正在停止…' : '取消并保留进度',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
