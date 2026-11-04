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
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '${Directory.systemTemp.path}/fmerge-appearance-${mode.name}.png',
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('PREVIEW: ${file.path}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
