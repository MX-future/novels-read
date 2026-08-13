import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读背景主题。
enum ReaderTheme {
  /// 白色(默认)
  white,

  /// 护眼(米黄)
  sepia,

  /// 夜间(深色)
  dark,
}

extension ReaderThemeX on ReaderTheme {
  (Color bg, Color text, Color subtext, Color accent) get colors {
    switch (this) {
      case ReaderTheme.white:
        return (
          const Color(0xFFFBFCFE),
          const Color(0xFF1F2A37),
          const Color(0xFF5A6B7F),
          const Color(0xFF357ABD),
        );
      case ReaderTheme.sepia:
        return (
          // 橙金暖色背景 (类似第二张参考图/kindle 暖屏)
          const Color(0xFFF6E4C2),
          // 深棕橙文字
          const Color(0xFF5A3A1A),
          // 暖棕次要文字
          const Color(0xFFA07241),
          // 橙金强调色
          const Color(0xFFC97A2C),
        );
      case ReaderTheme.dark:
        return (
          const Color(0xFF1A1F26),
          const Color(0xFFD8DDE4),
          const Color(0xFF909AA6),
          const Color(0xFF8FB8E8),
        );
    }
  }

  String get label {
    switch (this) {
      case ReaderTheme.white:
        return '白';
      case ReaderTheme.sepia:
        return '黄';
      case ReaderTheme.dark:
        return '夜';
    }
  }
}

/// 键盘方向键的控制模式。
enum ArrowKeyMode {
  /// 上/下:翻页,左/右:切章(默认)
  pagingVertical,

  /// 上/下:切章,左/右:翻页
  chaptersVertical,
}

extension ArrowKeyModeX on ArrowKeyMode {
  String get label => switch (this) {
    ArrowKeyMode.pagingVertical => '上下翻页 · 左右切章',
    ArrowKeyMode.chaptersVertical => '上下切章 · 左右翻页',
  };
}

/// 阅读器设置:字号、行距、边距、背景主题、方向键模式。
class ReaderSettings {
  final double fontSize;
  final double lineHeight;
  final double padding;
  final ReaderTheme theme;
  final ArrowKeyMode arrowKeyMode;

  const ReaderSettings({
    this.fontSize = 17,
    this.lineHeight = 1.85,
    this.padding = 44,
    this.theme = ReaderTheme.white,
    this.arrowKeyMode = ArrowKeyMode.pagingVertical,
  });

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? padding,
    ReaderTheme? theme,
    ArrowKeyMode? arrowKeyMode,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    padding: padding ?? this.padding,
    theme: theme ?? this.theme,
    arrowKeyMode: arrowKeyMode ?? this.arrowKeyMode,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'padding': padding,
    'theme': theme.index,
    'arrowKeyMode': arrowKeyMode.index,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    final arrowIndex = (json['arrowKeyMode'] as int?) ?? 0;
    return ReaderSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 17,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.85,
      padding: (json['padding'] as num?)?.toDouble() ?? 44,
      theme: ReaderTheme.values[(json['theme'] as int?) ?? 0],
      arrowKeyMode: ArrowKeyMode.values[arrowIndex.clamp(0, ArrowKeyMode.values.length - 1)],
    );
  }

  static const _key = 'reader_settings_v1';

  /// 全局共享设置,改动会通知所有监听者。
  static final ValueNotifier<ReaderSettings> current = ValueNotifier(
    const ReaderSettings(),
  );

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      current.value = ReaderSettings.fromJson(json);
    } catch (_) {}
  }

  static Future<void> save(ReaderSettings settings) async {
    current.value = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}

extension HoverAlpha on Color {
  /// 在当前背景色上叠加一个浅灰/浅白的悬停层。
  Color hoverOverlay() {
    final luminance = computeLuminance();
    // 背景越亮,悬停层越偏灰;背景越暗,悬停层越偏白。
    return luminance > 0.5
        ? const Color(0xFF000000).withValues(alpha: 0.06)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.08);
  }
}
