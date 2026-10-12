import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'services/reader_settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时就把阅读设置(主题/字号/行距)读进内存:
  // 否则首次进入阅读页才加载,会先按默认主题渲染一帧再切到用户主题(闪一下)。
  await ReaderSettings.load();
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
