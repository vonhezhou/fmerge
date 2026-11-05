import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/palette.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/theme_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实 macOS：原生窗口随亮暗模式切换并可恢复跟随系统', (tester) async {
    await windowManager.ensureInitialized();
    final settings = Settings(persist: false);
    final session = CompareSession(
      TextFile.empty('class Example {\n  final message = "before";\n}\n'),
      TextFile.empty('class Example {\n  final message = "after";\n}\n'),
    )..leftLanguage = 'dart';
    session.rightLanguage = 'dart';
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          settings: settings,
          initial: session,
          nativeWindow: true,
        ),
      ),
    );
    await windowManager.show();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!session.comparisonCurrent) {
      if (DateTime.now().isAfter(deadline)) fail('差异计算超时');
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> snapshot(String name) async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '${Directory.systemTemp.path}/fmerge-appearance-$name.png',
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('PREVIEW: ${file.path}');
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark, ThemeMode.system]) {
      settings.setAppearance(mode: mode, theme: ColorTheme.tokyoNight);
      await tester.pumpAndSettle();
      expect(
        await const MethodChannel('fmerge/appearance')
            .invokeMethod<String>('getMode'),
        mode.name,
      );
      final context = tester.element(find.byType(CodePane).first);
      final brightness = mode == ThemeMode.system
          ? tester.binding.platformDispatcher.platformBrightness
          : mode == ThemeMode.light
          ? Brightness.light
          : Brightness.dark;
      expect(Theme.of(context).brightness, brightness);
      expect(find.textContaining('更新窗口外观失败'), findsNothing);
      expect(tester.takeException(), isNull);
      await snapshot(mode.name);
    }
    settings.setAppearance(mode: ThemeMode.dark);
    await windowManager.setSize(const Size(920, 680));
    await tester.pumpAndSettle();
    final originalDiff = session.diff;
    await tester.tap(find.byKey(const ValueKey('command-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑器与外观'));
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('edit-theme-dark'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(ThemeEditor), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('custom-theme-name')),
      '我的 macOS 主题',
    );
    final keyword = find.byKey(const ValueKey('theme-color-keyword'));
    await tester.ensureVisible(keyword);
    await tester.enterText(keyword, '#ffaa66');
    await tester.pumpAndSettle();
    await snapshot('custom-editor');
    await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
    await tester.pumpAndSettle();
    final custom = settings.customThemeFor(Brightness.dark)!;
    expect(custom.palette.keyword, const Color(0xffffaa66));
    await snapshot('custom-settings');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(session.diff, same(originalDiff));
    expect(session.palette, same(custom.palette));
    final file = File(
      '${Directory.systemTemp.path}/custom-theme.fmerge-theme.json',
    );
    await file.writeAsString(custom.encode());
    final imported = settings.importTheme(await file.readAsString());
    expect(imported.palette.colors, custom.palette.colors);
    expect(imported.id, isNot(custom.id));
    await tester.pumpAndSettle();
    await snapshot('custom-applied');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
