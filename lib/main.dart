import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const NovelReaderApp());
}

class NovelReaderApp extends StatelessWidget {
  const NovelReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '书架',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const LibraryScreen(),
    );
  }
}
