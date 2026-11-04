import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/palette.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/settings_dialog.dart';

import 'desktop_workflow_test.dart' show waitUntil;

void main() {
  test('主题偏好保存与恢复，无效或亮暗不匹配字段回退', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-theme-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = Settings(storageDirectory: dir.path)
      ..setAppearance(mode: ThemeMode.dark, theme: ColorTheme.tokyoNight);
    await settings.save();
    final restored = await Settings.load(storageDirectory: dir.path);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.lightTheme, ColorTheme.githubLight);
    expect(restored.darkTheme, ColorTheme.tokyoNight);
    restored.readPreferences({
      'themeMode': 'invalid',
      'lightTheme': 'githubDark',
      'darkTheme': 42,
    });
    expect(restored.themeMode, ThemeMode.system);
    expect(restored.lightTheme, ColorTheme.githubLight);
    expect(restored.darkTheme, ColorTheme.fmergeDark);
  });

  testWidgets('亮暗主题与系统切换保留差异结果、文本、选择和撤销历史', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = tester.binding.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.dark;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    final settings = Settings(persist: false);
    final session = CompareSession(
      TextFile.empty('class Example {\n  final value = 1;\n}\n'),
      TextFile.empty('class Example {\n  final value = 2;\n}\n'),
      compareRunner: (task) async => runCompareTask(task),
    );
    session.leftLanguage = session.rightLanguage = 'dart';
    await tester.pumpWidget(FmergeApp(settings: settings, initial: session));
    await waitUntil(tester, () => session.comparisonCurrent);
    session.rightEditor.runRevocableOp(
      () => session.rightEditor.replaceSelection(' // edited'),
    );
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => session.comparisonCurrent);
    final text = session.rightEditor.text;
    final selection = session.rightEditor.selection;
    final diff = session.diff;
    final dirty = session.rightDirty;

    for (final theme in ColorTheme.values) {
      final colors = palettes[theme]!;
      settings.setAppearance(
        mode: theme.brightness == Brightness.light
            ? ThemeMode.light
            : ThemeMode.dark,
        theme: theme,
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(CodePane).first);
      expect(AppPalette.of(context), same(colors));
      expect(Theme.of(context).brightness, theme.brightness);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor).first);
      expect(editor.style!.textColor, colors.ink);
      expect(editor.style!.selectionColor, colors.selection);
      expect(editor.style!.codeTheme!.theme['keyword']!.color, colors.keyword);
      expect(editor.style!.codeTheme!.theme['string']!.color, colors.string);
      expect(
        session.leftEditor.diffLayout!.rowColors.values,
        contains(colors.removedBg),
      );
      expect(
        session.rightEditor.diffLayout!.ranges.values
            .expand((r) => r)
            .map((r) => r.color),
        contains(colors.addedInline),
      );
      expect(session.diff, same(diff));
      expect(session.rightEditor.text, text);
      expect(session.rightEditor.selection, selection);
      expect(session.rightDirty, dirty);
      expect(session.rightEditor.canUndo, isTrue);
      expect(tester.takeException(), isNull);
    }
    settings.setAppearance(mode: ThemeMode.system);
    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(session.palette.theme, ColorTheme.githubLight);
    platform.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(session.palette.theme, ColorTheme.tokyoNight);
    session.rightEditor.undo();
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => session.comparisonCurrent);
    expect(session.rightEditor.text, isNot(text));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('设置中即时预览主题，关闭并重新打开后保留选择', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = Settings(persist: false);
    await tester.pumpWidget(FmergeApp(settings: settings));
    Future<void> open() async {
      await tester.tap(find.byKey(const ValueKey('command-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑器与外观'));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.text('暗色').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tokyo Night').last);
    await tester.pumpAndSettle();
    expect(settings.darkTheme, ColorTheme.tokyoNight);
    expect(
      AppPalette.of(tester.element(find.byType(SettingsDialog))).theme,
      ColorTheme.tokyoNight,
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await open();
    expect(find.text('Tokyo Night'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('三方冲突及已解决区域随主题更新，不改写合并状态', () async {
    final session = CompareSession(
      TextFile.empty('left\n'),
      TextFile.empty('right\n'),
      base: TextFile.empty('base\n'),
      compareRunner: (task) async => runCompareTask(task),
    );
    addTearDown(session.dispose);
    await session.refresh();
    final state = session.merger!.state;
    session.setPalette(palettes[ColorTheme.githubLight]!);
    expect(
      session.resultEditor!.diffLayout!.rowColors.values,
      everyElement(palettes[ColorTheme.githubLight]!.conflictBg),
    );
    expect(session.merger!.state, same(state));
    expect(session.resultEditor!.text, state.text);
    expect(session.resultEditor!.diffLayout!.rowColors, isNotEmpty);
    session.markResolved(state.regions.first.chunk.id, true);
    final resolved = session.merger!.state;
    session.setPalette(palettes[ColorTheme.tokyoNight]!);
    expect(
      session.resultEditor!.diffLayout!.rowColors.values,
      everyElement(palettes[ColorTheme.tokyoNight]!.addedBg),
    );
    expect(session.merger!.state, same(resolved));
    session.undoMerge();
    expect(session.merger!.state, same(state));
  });
}
