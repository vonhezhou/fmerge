import 'dart:io';
import 'dart:math';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fmerge/core/context_rows.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/core/shortcuts.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/toolbar_action.dart';

import 'desktop_workflow_test.dart' show waitUntil;

void desktopTest(String name, Future<void> Function(WidgetTester) callback) =>
    testWidgets(
      name,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

Future<void> modifiedKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  test('连续切换的设置按最后快照持久化，重新加载保留上下文和快捷键', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-preferences-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = Settings(storageDirectory: dir.path)..contextOnly = true;
    final first = settings.save();
    settings.contextLines = 9;
    settings.shortcuts.assign(
      AppCommand.save,
      const KeyBinding(LogicalKeyboardKey.f6),
    );
    final second = settings.save();
    settings.contextOnly = false;
    settings.showWhitespace = true;
    final third = settings.save();
    await Future.wait([first, second, third]);
    final restored = await Settings.load(storageDirectory: dir.path);
    expect(restored.contextOnly, false);
    expect(restored.contextLines, 9);
    expect(restored.showWhitespace, true);
    expect(restored.shortcuts[AppCommand.save]!.key, LogicalKeyboardKey.f6);
    expect(await File('${dir.path}/settings.json.$pid.tmp').exists(), false);
  });
  test('忽略空白只处理行首行尾空格和 Tab，不隐藏行内字符差异', () {
    const options = CompareOptions(whitespace: WhitespaceMode.edges);
    expect(
      compare(const DiffInput('  alpha\t\n\tbeta ', 'alpha\nbeta', options))
          .changes,
      isEmpty,
    );
    expect(
      compare(const DiffInput('alpha  beta', 'alpha beta', options)).changes,
      isNotEmpty,
    );
    expect(
      compare(const DiffInput('alpha\tbeta', 'alpha beta', options)).changes,
      isNotEmpty,
    );
    expect(
      compare(const DiffInput('Alpha', 'alpha', options)).changes,
      isNotEmpty,
    );
    expect(
      compare(
        const DiffInput(
          'Alpha',
          'alpha',
          CompareOptions(whitespace: WhitespaceMode.edges, ignoreCase: true),
        ),
      ).changes,
      isEmpty,
    );
  });

  test('比较、显示、上下文行数和自定义快捷键完整往返，兼容旧空白设置', () {
    final original = Settings(persist: false)
      ..contextOnly = true
      ..contextLines = 12
      ..showWhitespace = true
      ..ignoreWhitespace = true
      ..ignoreCase = true
      ..ignoreEol = false
      ..toolbarLabels = false;
    original.shortcuts.assign(
      AppCommand.swapSides,
      const KeyBinding(LogicalKeyboardKey.f9),
    );
    original.shortcuts.assign(AppCommand.stage, null);
    final restored = Settings(persist: false)
      ..readPreferences(original.preferencesJson());
    expect(restored.preferencesJson(), original.preferencesJson());
    expect(restored.shortcuts[AppCommand.stage], isNull);
    expect(
      restored.shortcuts[AppCommand.swapSides]!.key,
      LogicalKeyboardKey.f9,
    );
    for (final legacy in [1, 2, 3]) {
      restored.readPreferences({'whitespace': legacy});
      expect(restored.whitespace, WhitespaceMode.edges);
    }
    restored.readPreferences({
      'contextLines': -3,
      'contextOnly': 'bad',
      'shortcuts': {
        'open': {'key': -7},
      },
    });
    expect(restored.contextLines, 0);
    expect(restored.contextOnly, false);
    expect(restored.shortcuts[AppCommand.open]!.key, LogicalKeyboardKey.keyO);
    restored.readPreferences({'contextLines': 999999});
    expect(restored.contextLines, 1000);
  });

  test('快捷键拒绝冲突、裸字符和系统保留键；损坏配置不覆盖合法默认键', () {
    final shortcuts = ShortcutPreferences();
    expect(
      shortcuts.validate(AppCommand.open, shortcuts[AppCommand.save]),
      contains('保存'),
    );
    expect(
      () => shortcuts.assign(AppCommand.open, shortcuts[AppCommand.save]),
      throwsArgumentError,
    );
    expect(
      shortcuts.validate(
        AppCommand.open,
        const KeyBinding(LogicalKeyboardKey.keyA),
      ),
      isNotNull,
    );
    expect(
      shortcuts.validate(
        AppCommand.open,
        const KeyBinding(LogicalKeyboardKey.keyQ, meta: true),
      ),
      isNotNull,
    );
    shortcuts.load({'open': shortcuts[AppCommand.save]!.toJson()});
    expect(shortcuts[AppCommand.open]!.key, LogicalKeyboardKey.keyO);
    shortcuts.load({
      'open': defaultBindings[AppCommand.save]!.toJson(),
      'save': defaultBindings[AppCommand.open]!.toJson(),
    });
    expect(shortcuts[AppCommand.open]!.key, LogicalKeyboardKey.keyS);
    expect(shortcuts[AppCommand.save]!.key, LogicalKeyboardKey.keyO);
    expect(
      AppCommand.values
          .map((command) => shortcuts[command]!.signature)
          .toSet()
          .length,
      AppCommand.values.length,
    );
  });

  test('可配置上下文区间与逐行参考算法一致，零行和密集修改不破坏映射', () {
    final random = Random(403);
    for (var sample = 0; sample < 150; sample++) {
      final total = random.nextInt(150), context = random.nextInt(25);
      final changed = {
        for (var i = 0; i < total; i++)
          if (random.nextBool()) i,
      };
      final map = ContextRows(total, changed, context: context);
      final visible = {
        for (final line in changed)
          for (
            var row = max(0, line - context);
            row < min(total, line + context + 1);
            row++
          )
            row,
      };
      expect(map.hidden, {
        for (var row = 0; row < total; row++)
          if (!visible.contains(row)) row,
      });
      expect(map.rows.length, total);
      for (var row = 1; row < total; row++) {
        expect(map.rows[row] - map.rows[row - 1], inInclusiveRange(0, 1));
      }
    }
  });

  desktopTest('上下文偏好跨会话保留，临时展开不改偏好，设置固定在工具栏最右侧', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = Settings(persist: false)
      ..contextOnly = true
      ..contextLines = 8;
    CompareSession session() {
      final left = List.generate(80, (i) => 'line $i'),
          right = List.generate(80, (i) => i == 40 ? 'changed' : 'line $i');
      return CompareSession(
        TextFile.empty(left.join('\n')),
        TextFile.empty(right.join('\n')),
      );
    }

    final first = session();
    await tester.pumpWidget(FmergeApp(settings: settings, initial: first));
    await waitUntil(tester, () => !first.busy);
    expect(first.contextOnly, true);
    expect(first.leftEditor.diffLayout!.totalRows, 21);
    final settingsRect = tester.getRect(
      find.byKey(const ValueKey('command-settings')),
    );
    for (final key in ['swapSides']) {
      expect(
        find.byKey(ValueKey('command-$key')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(ValueKey('command-$key'))).right,
        lessThan(settingsRect.left),
      );
    }
    for (final (menu, command) in [
      ('比较', 'ignoreWhitespace'),
      ('视图', 'contextOnly'),
    ]) {
      await tester.tap(find.byKey(ValueKey('menu-$menu')));
      await tester.pumpAndSettle();
      final item = find.byKey(ValueKey('menu-command-$command'));
      await tester.ensureVisible(item);
      expect(item.hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();
    }
    first.rightEditor.text = '${first.rightEditor.text}\nedited';
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !first.busy);
    expect(first.contextOnly, false);
    expect(settings.contextOnly, true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final second = session();
    await tester.pumpWidget(FmergeApp(settings: settings, initial: second));
    await waitUntil(tester, () => !second.busy);
    expect(second.contextOnly, true);
    expect(second.contextLines, 8);
  });

  desktopTest('快捷键录制提示冲突并生效，旧键位不再触发打开', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = FileSelectorPlatform.instance, picker = _Picker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final settings = Settings(persist: false);
    await tester.pumpWidget(FmergeApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('command-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('快捷键').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shortcut-open')));
    await tester.pumpAndSettle();
    await modifiedKey(tester, LogicalKeyboardKey.keyS);
    expect(find.textContaining('已用于“保存”'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存快捷键'))
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存快捷键'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(settings.shortcuts[AppCommand.open]!.key, LogicalKeyboardKey.f9);
    await modifiedKey(tester, LogicalKeyboardKey.keyO);
    expect(picker.calls, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(tester.takeException(), isNull);
  });

  desktopTest('编辑器使用自定义保存键，旧保存键不写磁盘，显示调整不重新比较', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fmerge-custom-save-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/right')..writeAsStringSync('old');
    final right = (await tester.runAsync(() => TextFile.read(file.path)))!;
    final settings = Settings(persist: false);
    final s = CompareSession(TextFile.empty('left'), right);
    await tester.pumpWidget(FmergeApp(settings: settings, initial: s));
    await waitUntil(tester, () => !s.busy);
    final editing = s.rightEditor;
    await tester.tap(find.byKey(const ValueKey('command-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('快捷键').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shortcut-save')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存快捷键'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(identical(editing, s.rightEditor), true);
    final diff = s.diff;
    s.setShowWhitespace(true);
    await tester.pumpAndSettle();
    expect(identical(diff, s.diff), true);
    expect(s.leftEditor.diffLayout!.showWhitespace, true);
    expect(s.busy, false);
    s.rightEditor.text = 'new';
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    tester
        .widgetList<CodePane>(find.byType(CodePane))
        .last
        .focus
        .requestFocus();
    await tester.pumpAndSettle();
    await modifiedKey(tester, LogicalKeyboardKey.keyS);
    expect(file.readAsStringSync(), 'old');
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.f6));
    await waitUntil(tester, () => !s.rightDirty);
    expect(file.readAsStringSync(), 'new');
    expect(
      tester
          .widget<ToolbarAction>(find.byKey(const ValueKey('command-save')))
          .tooltip,
      '保存 · F6',
    );
  });
}

class _Picker extends FileSelectorPlatform {
  int calls = 0;
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls++;
    return [];
  }
}
