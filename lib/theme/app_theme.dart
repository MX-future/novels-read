import 'package:flutter/material.dart';

/// 应用配色:浅蓝白基调,无灰色边框与深色渐变。
class AppTheme {
  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryDark = Color(0xFF357ABD);
  static const Color accent = Color(0xFF5B8DEF);

  static const Color background = Color(0xFFFFFFFF);
  static const Color sidebarBg = Color(0xFFF1F6FC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color hoverBg = Color(0xFFE3EEFB);
  static const Color selectedBg = Color(0xFFCFE0F6);

  static const Color textPrimary = Color(0xFF1F2A37);
  static const Color textSecondary = Color(0xFF5A6B7F);
  static const Color textTertiary = Color(0xFF9CA8B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color readerBg = Color(0xFFFBFCFE);
  static const Color divider = Color(0xFFE6EDF5);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    colorScheme: ColorScheme.light(
      primary: primary,
      onPrimary: textOnPrimary,
      secondary: accent,
      onSecondary: textOnPrimary,
      surface: background,
      onSurface: textPrimary,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textPrimary),
      bodyMedium: TextStyle(color: textPrimary),
      bodySmall: TextStyle(color: textSecondary),
      titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: textSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    iconTheme: const IconThemeData(color: primary),
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 1,
      space: 1,
    ),
  );
}
