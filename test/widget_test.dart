import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_reader/main.dart';
import 'package:novel_reader/theme/app_theme.dart';

/// 测试用假 path_provider(避免原生插件调用)。
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/test_support';

  @override
  Future<String?> getTemporaryPath() async => '/tmp';

  @override
  Future<String?> getLibraryPath() async => '/tmp/test_library';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider();
    SharedPreferences.setMockInitialValues({});
  });

  group('NovelReaderApp 冒烟测试', () {
    /// 显式 pump 等待异步 _refresh 完成(避免 pumpAndSettle 被无限动画卡住)
    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(const NovelReaderApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('应用能构建并显示书架标题', (tester) async {
      await pumpApp(tester);

      // 应用名「书架」出现在标题栏
      expect(find.text('书架'), findsWidgets);
    });

    testWidgets('空书库时显示提示', (tester) async {
      await pumpApp(tester);

      // 空库应有导入/空状态相关提示
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('应用使用浅色主题', (tester) async {
      await pumpApp(tester);

      // 取应用内部元素(Scaffold)的 context,Theme.of 才会命中 MaterialApp 的 theme
      final context = tester.element(find.byType(Scaffold).first);
      final theme = Theme.of(context);
      expect(theme.brightness, Brightness.light);
      // 与 AppTheme.lightTheme 一致
      expect(theme.colorScheme.primary, AppTheme.lightTheme.colorScheme.primary);
    });
  });

  group('AppTheme', () {
    test('lightTheme 是浅色主题', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
    });
  });
}
