import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/app_theme.dart';
import '../services/watch_folder_service.dart';

/// 打开「自动导入目录」设置弹窗。
///
/// [onLibraryChanged] 在扫描导入到新书后调用,让书架刷新列表。
Future<void> showWatchFolderDialog(
  BuildContext context, {
  required VoidCallback onLibraryChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => WatchFolderDialog(onLibraryChanged: onLibraryChanged),
  );
}

class WatchFolderDialog extends StatefulWidget {
  const WatchFolderDialog({super.key, required this.onLibraryChanged});

  final VoidCallback onLibraryChanged;

  @override
  State<WatchFolderDialog> createState() => _WatchFolderDialogState();
}

class _WatchFolderDialogState extends State<WatchFolderDialog> {
  String? _path;
  bool _busy = false;
  bool _loading = true;

  int _done = 0;
  int _total = 0;
  String _current = '';

  WatchScanResult? _lastResult;
  DateTime? _lastScanAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = await WatchFolderService.restoreAccess();
    final lastAt = await WatchFolderService.lastScanAt();
    if (!mounted) return;
    setState(() {
      _path = path;
      _lastScanAt = lastAt;
      _loading = false;
    });
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await WatchFolderService.pick();
      if (!mounted) return;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _path = path;
        _lastResult = null;
      });
      // 选完立刻扫一次,不用等下次启动才知道结果
      await _scan(keepBusy: true);
    } on WatchFolderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan({bool keepBusy = false}) async {
    if (_busy && !keepBusy) return;
    if (!keepBusy) setState(() => _busy = true);
    setState(() {
      _error = null;
      _done = 0;
      _total = 0;
      _current = '';
    });

    try {
      final result = await WatchFolderService.scan(
        onProgress: (done, total, current) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
            _current = current;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _lastScanAt = DateTime.now();
      });
      if (result != null && result.imported > 0) {
        widget.onLibraryChanged();
      }
    } on WatchFolderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await WatchFolderService.clear();
    if (!mounted) return;
    setState(() {
      _path = null;
      _lastResult = null;
      _lastScanAt = null;
      _error = null;
    });
    widget.onLibraryChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      title: const Row(
        children: [
          Icon(Icons.folder_special_outlined, size: 20, color: AppTheme.primary),
          SizedBox(width: 8),
          Text(
            '自动导入目录',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '指定一个本地文件夹,每次打开 App 会自动静默扫描其中的 epub / txt '
              '(含子文件夹),没入架的新书自动导入,已有的跳过。',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 14),
            _buildPathCard(),
            if (_busy && _total > 0) ...[
              const SizedBox(height: 12),
              _buildScanProgress(),
            ],
            if (!_busy && _lastResult != null) ...[
              const SizedBox(height: 12),
              _buildResult(),
            ],
            if (!_busy && _lastResult == null && _lastScanAt != null) ...[
              const SizedBox(height: 10),
              Text(
                '上次扫描:${_formatTime(_lastScanAt!)}',
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: Color(0xFFD64545)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFD64545),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_path != null)
          TextButton(
            onPressed: _busy ? null : _clear,
            child: const Text(
              '关闭自动导入',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        TextButton(
          onPressed: (_busy || _path == null) ? null : () => _scan(),
          child: Text(
            '立即扫描',
            style: TextStyle(
              color: _path == null ? AppTheme.textTertiary : AppTheme.primaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _pick,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            _path == null ? '选择文件夹' : '更换文件夹',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildPathCard() {
    final path = _path;
    final hasPath = path != null && path.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasPath ? Icons.folder_open_rounded : Icons.folder_off_outlined,
            size: 17,
            color: hasPath ? AppTheme.primary : AppTheme.textTertiary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _loading
                ? const Text(
                    '读取中…',
                    style: TextStyle(
                        color: AppTheme.textTertiary, fontSize: 12.5),
                  )
                : hasPath
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.basename(path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Tooltip(
                            message: path,
                            waitDuration: const Duration(milliseconds: 400),
                            child: Text(
                              path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '尚未设置。选择一个文件夹后,新放入的小说会在下次启动时自动导入。',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanProgress() {
    final ratio = _total == 0 ? 0.0 : (_done / _total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: const Color(0xFFEAF2FC),
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '$_done / $_total · $_current',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final r = _lastResult!;
    final ok = r.failed == 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.info_outline,
          size: 14,
          color: ok ? const Color(0xFF3E9C63) : const Color(0xFFD99A2B),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${r.summary} · 用时 ${(r.duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
