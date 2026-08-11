import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_reader/services/reader_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderSettings', () {
    test('默认值', () {
      const settings = ReaderSettings();
      expect(settings.fontSize, 17);
      expect(settings.lineHeight, 1.85);
      expect(settings.padding, 44);
      expect(settings.theme, ReaderTheme.white);
    });

    test('copyWith 只更新指定字段', () {
      const settings = ReaderSettings();
      final updated = settings.copyWith(fontSize: 20);
      expect(updated.fontSize, 20);
      expect(updated.lineHeight, 1.85); // 未改
      expect(updated.padding, 44);
      expect(updated.theme, ReaderTheme.white);

      final themed = updated.copyWith(theme: ReaderTheme.dark);
      expect(themed.theme, ReaderTheme.dark);
      expect(themed.fontSize, 20); // 保留
    });

    test('toJson/fromJson 往返一致', () {
      const settings = ReaderSettings(
        fontSize: 21.5,
        lineHeight: 2.0,
        padding: 32,
        theme: ReaderTheme.sepia,
      );
      final restored = ReaderSettings.fromJson(settings.toJson());
      expect(restored.fontSize, 21.5);
      expect(restored.lineHeight, 2.0);
      expect(restored.padding, 32);
      expect(restored.theme, ReaderTheme.sepia);
    });

    test('fromJson 缺失字段时使用默认值', () {
      final settings = ReaderSettings.fromJson(const {});
      expect(settings.fontSize, 17);
      expect(settings.lineHeight, 1.85);
      expect(settings.padding, 44);
      expect(settings.theme, ReaderTheme.white);
    });

    test('fromJson 处理非法 theme 索引', () {
      // ReaderTheme.values 只有 3 个,越界访问会抛 RangeError
      expect(
        () => ReaderSettings.fromJson(const {'theme': 99}),
        throwsA(isA<RangeError>()),
      );
    });

    test('save 后 load 能恢复设置', () async {
      SharedPreferences.setMockInitialValues({});
      const settings = ReaderSettings(
        fontSize: 24,
        lineHeight: 2.2,
        padding: 28,
        theme: ReaderTheme.dark,
      );
      await ReaderSettings.save(settings);
      expect(ReaderSettings.current.value.theme, ReaderTheme.dark);

      // 重置为默认再 load
      ReaderSettings.current.value = const ReaderSettings();
      await ReaderSettings.load();
      expect(ReaderSettings.current.value.fontSize, 24);
      expect(ReaderSettings.current.value.lineHeight, 2.2);
      expect(ReaderSettings.current.value.padding, 28);
      expect(ReaderSettings.current.value.theme, ReaderTheme.dark);
    });

    test('load 在无存档时保持默认', () async {
      SharedPreferences.setMockInitialValues({});
      ReaderSettings.current.value = const ReaderSettings();
      await ReaderSettings.load();
      expect(ReaderSettings.current.value, const ReaderSettings());
    });

    test('load 在存档损坏时保持默认(不抛异常)', () async {
      SharedPreferences.setMockInitialValues({
        'reader_settings_v1': '这不是合法 JSON {{{',
      });
      ReaderSettings.current.value = const ReaderSettings();
      await ReaderSettings.load();
      expect(ReaderSettings.current.value, const ReaderSettings());
    });
  });

  group('ReaderTheme', () {
    test('三种主题的配色元组长度和类型', () {
      for (final theme in ReaderTheme.values) {
        final (bg, text, subtext, accent) = theme.colors;
        expect(bg, isA<Color>());
        expect(text, isA<Color>());
        expect(subtext, isA<Color>());
        expect(accent, isA<Color>());
      }
    });

    test('不同主题配色不同', () {
      final white = ReaderTheme.white.colors;
      final sepia = ReaderTheme.sepia.colors;
      final dark = ReaderTheme.dark.colors;
      expect(white.$1, isNot(equals(sepia.$1)));
      expect(sepia.$1, isNot(equals(dark.$1)));
    });

    test('夜间主题背景是深色', () {
      final (bg, _, _, _) = ReaderTheme.dark.colors;
      expect(bg.computeLuminance(), lessThan(0.2));
    });

    test('白色主题背景是亮色', () {
      final (bg, _, _, _) = ReaderTheme.white.colors;
      expect(bg.computeLuminance(), greaterThan(0.9));
    });

    test('label 中文标识', () {
      expect(ReaderTheme.white.label, '白');
      expect(ReaderTheme.sepia.label, '黄');
      expect(ReaderTheme.dark.label, '夜');
    });
  });

  group('HoverAlpha', () {
    test('亮背景返回黑色半透明叠加', () {
      const light = Color(0xFFFFFFFF);
      final overlay = light.hoverOverlay();
      // 叠加层是黑色,alpha 低 (Flutter Color 分量是 0-1 浮点)
      expect(overlay.r, 0);
      expect(overlay.g, 0);
      expect(overlay.b, 0);
      expect(overlay.a, lessThan(0.1));
    });

    test('暗背景返回白色半透明叠加', () {
      const dark = Color(0xFF000000);
      final overlay = dark.hoverOverlay();
      expect(overlay.r, 1.0);
      expect(overlay.g, 1.0);
      expect(overlay.b, 1.0);
      expect(overlay.a, lessThan(0.15));
    });
  });
}
