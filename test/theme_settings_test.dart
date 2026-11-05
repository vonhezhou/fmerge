import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fmerge/core/custom_theme.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/palette.dart';
import 'package:fmerge/ui/app_theme.dart';
import 'package:fmerge/ui/theme_editor.dart';
import 'package:fmerge/ui/theme_settings.dart';

import 'desktop_workflow_test.dart' show waitUntil;

Future<void> host(WidgetTester tester, Settings settings) async {
  tester.view.physicalSize = const Size(920, 680);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        theme: buildAppTheme(palette: settings.paletteFor(Brightness.light)),
        darkTheme: buildAppTheme(palette: settings.paletteFor(Brightness.dark)),
        themeMode: settings.themeMode,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: SingleChildScrollView(child: ThemeSettings(settings: settings)),
        ),
      ),
    ),
  );
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('自定义颜色校验、保存应用、取消草稿和删除确认', (tester) async {
    final settings = Settings(persist: false)
      ..setAppearance(mode: ThemeMode.dark);
    await host(tester, settings);
    await click(tester, find.byKey(const ValueKey('edit-theme-dark')));
    expect(find.byType(ThemeEditor), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('custom-theme-name')),
      '我的夜色',
    );
    final bg = find.byKey(const ValueKey('theme-color-bg'));
    await tester.ensureVisible(bg);
    await tester.enterText(bg, '#not-valid');
    await click(tester, find.byKey(const ValueKey('save-custom-theme')));
    expect(find.byType(ThemeEditor), findsOneWidget);
    expect(settings.customThemes, isEmpty);
    await tester.ensureVisible(bg);
    await tester.enterText(bg, '#112233');
    await click(tester, find.byKey(const ValueKey('save-custom-theme')));
    expect(settings.customThemes.single.name, '我的夜色');
    expect(
      AppPalette.of(tester.element(find.byType(ThemeSettings))).bg,
      const Color(0xff112233),
    );
    final palette = settings.paletteFor(Brightness.dark);
    await click(tester, find.byKey(const ValueKey('edit-theme-dark')));
    await tester.enterText(
      find.byKey(const ValueKey('custom-theme-name')),
      '取消的修改',
    );
    await click(tester, find.text('取消'));
    expect(settings.customThemes.single.name, '我的夜色');
    expect(settings.paletteFor(Brightness.dark), same(palette));
    await click(tester, find.byTooltip('删除暗色自定义主题'));
    await click(tester, find.text('取消'));
    expect(settings.customThemes, hasLength(1));
    await click(tester, find.byTooltip('删除暗色自定义主题'));
    await click(tester, find.text('删除'));
    expect(settings.customThemes, isEmpty);
    expect(
      settings.paletteFor(Brightness.dark),
      same(palettes[ColorTheme.fmergeDark]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统文件选择器导入导出、取消、无效文件及保存错误', (tester) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('theme-ui-');
    });
    addTearDown(() => dir.delete(recursive: true));
    final previous = FileSelectorPlatform.instance;
    final picker = _ThemePicker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final settings = Settings(persist: false)
      ..setAppearance(mode: ThemeMode.light);
    await host(tester, settings);
    final imported = CustomTheme(
      id: '',
      name: '导入的主题',
      base: ColorTheme.githubLight,
      colors: {'ink': const Color(0xff112233)},
    );
    picker.file = XFile.fromData(
      utf8.encode(imported.encode()),
      name: 'theme.json',
    );
    await click(tester, find.byKey(const ValueKey('import-theme')));
    await waitUntil(tester, () => settings.customThemes.isNotEmpty);
    expect(settings.paletteFor(Brightness.light).ink, const Color(0xff112233));
    final first = settings.customThemes.single;
    picker.destination = '${dir.path}/theme.json';
    await click(tester, find.byKey(const ValueKey('export-theme-light')));
    await waitUntil(
      tester,
      () => find.textContaining('已导出主题').evaluate().isNotEmpty,
    );
    await tester.runAsync(() async {
      final exported = await File(picker.destination!).readAsString();
      expect(
        CustomTheme.decode(exported, id: '').palette.colors,
        first.palette.colors,
      );
      picker.file = XFile(picker.destination!);
    });
    await click(tester, find.byKey(const ValueKey('import-theme')));
    await waitUntil(tester, () => settings.customThemes.length == 2);
    expect(settings.customThemes.last.name, '导入的主题 (2)');
    final before = settings.preferencesJson();
    picker.file = null;
    await click(tester, find.byKey(const ValueKey('import-theme')));
    expect(settings.preferencesJson(), before);
    picker.destination = null;
    await click(tester, find.byKey(const ValueKey('export-theme-light')));
    expect(settings.preferencesJson(), before);
    picker.file = XFile.fromData(
      utf8.encode('{"invalid":true}'),
      name: 'invalid.json',
    );
    await click(tester, find.byKey(const ValueKey('import-theme')));
    await waitUntil(
      tester,
      () => find.textContaining('导入失败').evaluate().isNotEmpty,
    );
    expect(settings.preferencesJson(), before);
    picker.file = XFile.fromData(
      Uint8List(1024 * 1024 + 1),
      name: 'large.json',
    );
    await click(tester, find.byKey(const ValueKey('import-theme')));
    await waitUntil(
      tester,
      () => find.textContaining('1 MB').evaluate().isNotEmpty,
    );
    expect(settings.preferencesJson(), before);
    picker.destination = '${dir.path}/missing/theme.json';
    await click(tester, find.byKey(const ValueKey('export-theme-light')));
    await waitUntil(
      tester,
      () => find.textContaining('导出失败').evaluate().isNotEmpty,
    );
    expect(settings.preferencesJson(), before);
    expect(tester.takeException(), isNull);
  });
}

class _ThemePicker extends FileSelectorPlatform {
  XFile? file;
  String? destination;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => destination == null ? null : FileSaveLocation(destination!);
}
