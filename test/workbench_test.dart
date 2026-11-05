import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/core/merge_labels.dart';
import 'package:fmerge/core/merge.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/workbench.dart';
import 'package:fmerge/ui/toolbar_action.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

import 'support/menus.dart';

Future<void> ready(WidgetTester tester) async {
  await tester.runAsync(() async {
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (tester.widget<Workbench>(find.byType(Workbench)).initial?.busy ==
        true) {
      if (DateTime.now().isAfter(until)) throw StateError('差异计算超时');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('宽窗口中常用开关可直接操作并保持状态与文档', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lines = List.generate(30, (i) => 'line $i');
    final changed = [...lines]..[15] = 'changed';
    final s = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(changed.join('\n')),
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await ready(tester);
    for (final command in [
      'save',
      'nextDiff',
      'takeLeft',
      'toggleLeftEdit',
      'swapSides',
      'settings',
    ]) {
      expect(
        find.byKey(ValueKey('command-$command')).hitTestable(),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('menu-视图')).hitTestable(), findsOneWidget);
    for (final menu in ['文件', '编辑', '视图', '导航', '比较', '工具', '帮助']) {
      expect(find.byKey(ValueKey('menu-$menu')).hitTestable(), findsOneWidget);
    }
    expect(tester.getTopLeft(find.byType(CodePane).first).dy, 108);
    for (final command in [
      'ignoreWhitespace',
      'contextOnly',
      'toggleWordWrap',
      'showWhitespace',
    ]) {
      final button = find.byKey(ValueKey('command-$command'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.widget<ToolbarAction>(button).selected, false);
      await tester.tap(button);
      await ready(tester);
      expect(tester.widget<ToolbarAction>(button).selected, true);
    }
    expect(s.contextOnly, true);
    expect(s.rightEditor.text, changed.join('\n'));
    await tester.ensureVisible(
      find.byKey(const ValueKey('command-toggleLeftEdit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('command-toggleLeftEdit')));
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<CodePane>(find.byType(CodePane)).first.readOnly,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('缩放窗口收起和恢复快捷入口，隐藏操作仍可从分类菜单执行', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = Settings(persist: false);
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpWidget(FmergeApp(settings: settings, initial: s));
    await ready(tester);
    for (final width in [1600.0, 920.0, 640.0, 1600.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('workbench-toolbar'));
      expect(tester.getSize(toolbar).height, width >= 1280 ? 66 : 44);
      expect(settings.toolbarLabels, true);
      expect(
        find.byKey(const ValueKey('command-showWhitespace')),
        width >= 1280 ? findsOneWidget : findsNothing,
      );
      for (final menu in ['文件', '编辑', '视图', '导航', '比较', '工具', '帮助']) {
        expect(
          find.byKey(ValueKey('menu-$menu')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('menu-帮助'))).right,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('command-save'))).left,
        ),
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(640, 800);
    await tester.pumpAndSettle();
    await chooseMenuCommand(tester, 'showWhitespace');
    expect(settings.showWhitespace, true);
    expect(s.rightEditor.text, 'right');
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ToolbarAction>(
            find.byKey(const ValueKey('command-showWhitespace')),
          )
          .selected,
      true,
    );
  });

  testWidgets('跳转行校验范围并保持对话框，成功后恢复目标编辑器焦点', (tester) async {
    final s = CompareSession(
      TextFile.empty('a\nb\nc'),
      TextFile.empty('a\nb\nc'),
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await ready(tester);
    expect(
      tester
          .widget<ToolbarAction>(
            find.byWidgetPredicate(
              (w) =>
                  w is ToolbarAction &&
                  w.key == const ValueKey('command-nextDiff'),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    for (final value in ['0', '4', 'invalid']) {
      await tester.enterText(find.byType(TextFormField), value);
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(find.text('行号范围为 1–3'), findsOneWidget);
      expect(s.rightEditor.selection.extentIndex, 0);
    }
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('跳转到行'), findsNothing);
    expect(s.rightEditor.selection.extentIndex, 2);
    expect(
      tester.widgetList<CodePane>(find.byType(CodePane)).last.focus.hasFocus,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('撤销与重做反映当前编辑栏的历史及只读状态', (tester) async {
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await ready(tester);
    ToolbarAction action(String label) => tester.widget<ToolbarAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ToolbarAction &&
            widget.key ==
                ValueKey('command-${label == '撤销' ? 'undo' : 'redo'}'),
      ),
    );
    expect(action('撤销').onPressed, isNull);
    s.rightEditor.runRevocableOp(() => s.rightEditor.text = 'edited');
    await tester.pump(const Duration(milliseconds: 170));
    await ready(tester);
    expect(action('撤销').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('command-undo')));
    await tester.pump(const Duration(milliseconds: 170));
    await ready(tester);
    expect(s.rightEditor.text, 'right');
    expect(action('重做').onPressed, isNotNull);
    await tester.tapAt(tester.getCenter(find.byType(CodePane).first));
    await tester.pumpAndSettle();
    expect(action('撤销').onPressed, isNull);
    expect(action('重做').onPressed, isNull);
  });

  testWidgets('手选语言不改变编辑内容，左右独立且交换后跟随文件', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = CompareSession(
      TextFile.empty('{}')..path = '/left.unknown',
      TextFile.empty('{}')..path = '/right.json',
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: session),
    );
    await ready(tester);
    final controller = session.leftEditor;
    await tester.tap(find.byType(LanguageMenu).first);
    await tester.pumpAndSettle();
    final jsonc = find.widgetWithText(CheckedPopupMenuItem<String>, 'JSONC');
    await tester.ensureVisible(jsonc);
    await tester.tap(jsonc);
    await tester.pumpAndSettle();
    var panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
    expect(panes[0].language, 'jsonc');
    expect(panes[1].language, 'json');
    expect(identical(panes[0].controller, controller), true);
    expect(controller.text, '{}');
    expect(session.dirty, false);
    session.swapSides();
    await ready(tester);
    panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
    expect(panes[0].language, 'json');
    expect(panes[1].language, 'jsonc');
    await tester.tap(find.byType(LanguageMenu).last);
    await tester.pumpAndSettle();
    final automatic = find.widgetWithText(
      CheckedPopupMenuItem<String>,
      '自动识别（纯文本）',
    );
    await tester.ensureVisible(automatic);
    await tester.tap(automatic);
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<CodePane>(find.byType(CodePane)).last.language,
      'text',
    );
    expect(tester.takeException(), isNull);
  });

  test('JSONC、C、C++ 与 Rust 后缀独立识别，未知后缀使用纯文本', () {
    expect(languageFor('config.JSONC'), 'jsonc');
    expect(languageFor('config.json'), 'json');
    expect(languageFor('main.c'), 'c');
    expect(languageFor('main.cpp'), 'cpp');
    expect(languageFor('main.cxx'), 'cpp');
    expect(languageFor('main.rs'), 'rust');
    expect(languageFor('unknown'), 'text');
  });
  testWidgets('欢迎页 Ctrl O 直接打开系统多选，取消后保持欢迎页', (tester) async {
    final previous = FileSelectorPlatform.instance;
    final picker = _Picker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    await tester.pumpWidget(FmergeApp(settings: Settings(persist: false)));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('打开文件比较'), findsNothing);
    expect(find.text('新建文本比较'), findsOneWidget);
    expect(find.text('三方合并'), findsNothing);
  });

  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('可编辑双栏和三方合并在 $size 无布局溢出', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = CompareSession(
        TextFile.empty('a\nb\nc'),
        TextFile.empty('a\nx\ny\nb\nc'),
      );
      await tester.pumpWidget(
        FmergeApp(settings: Settings(persist: false), initial: s),
      );
      await ready(tester);
      final panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
      expect(panes[0].readOnly, true);
      expect(panes[1].readOnly, false);
      expect(s.leftEditor.diffLayout!.lineRows, [0, 3, 4]);
      s.rightEditor.runRevocableOp(() => s.rightEditor.text = 'a\nx\ny\nb\nC');
      await tester.pump(const Duration(milliseconds: 170));
      await ready(tester);
      expect(s.rightDirty, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final merge = CompareSession(
        TextFile.empty('a\nL\nc'),
        TextFile.empty('a\nR\nc'),
        base: TextFile.empty('a\nb\nc'),
      );
      await tester.pumpWidget(
        FmergeApp(settings: Settings(persist: false), initial: merge),
      );
      await ready(tester);
      expect(find.text('1 处冲突待确认'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '采用左侧'));
      await tester.pumpAndSettle();
      expect(merge.resultEditor!.text, 'a\nL\nc');
      merge.resultEditor!.text = 'header\na\nL\nc';
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '采用右侧'));
      await tester.pumpAndSettle();
      expect(merge.resultEditor!.text, 'header\na\nR\nc');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('工具栏折叠保留真实文档，空白差异开关和左右交换可用', (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lines = List.generate(80, (i) => 'line $i');
    final right = [...lines]..[40] = 'changed';
    final s = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(right.join('\n')),
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await ready(tester);
    await chooseMenuCommand(tester, 'contextOnly');
    await tester.pumpAndSettle();
    expect(s.contextOnly, true);
    expect(s.leftEditor.diffLayout!.totalRows, 11);
    expect(s.rightEditor.text, right.join('\n'));
    expect(find.text('仅看差异 · 前后各 3 行 · 已省略 2 段未改动内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, '显示全文'));
    await tester.pumpAndSettle();
    expect(s.contextOnly, false);
    expect(find.text('显示全文'), findsNothing);
    expect(s.leftEditor.diffLayout!.totalRows, 80);
    await tester.tap(find.byKey(const ValueKey('command-swapSides')));
    await ready(tester);
    expect(s.leftEditor.text, right.join('\n'));
    expect(s.rightEditor.text, lines.join('\n'));
    s.rightEditor.text = s.leftEditor.text.replaceFirst('line 0', '  line 0  ');
    await tester.pump(const Duration(milliseconds: 170));
    await ready(tester);
    expect(s.diff!.changes.length, 1);
    await chooseMenuCommand(tester, 'ignoreWhitespace', menu: '比较');
    await ready(tester);
    expect(s.diff!.changes, isEmpty);
    await chooseMenuCommand(tester, 'ignoreWhitespace', menu: '比较');
    await ready(tester);
    expect(s.diff!.changes.length, 1);
    expect(tester.takeException(), isNull);
  });

  for (final rebase in [false, true]) {
    testWidgets('${rebase ? 'rebase' : 'merge'} 角色标签和采用按钮对应真实左右输入', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(920, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final labels = MergeLabels(
        operation: rebase ? MergeOperation.rebase : MergeOperation.merge,
        summary: rebase ? '正在将 feature 变基到 main' : '正在将 main 合并到 feature',
        leftTitle: rebase ? '目标历史' : '当前分支 · feature-with-a-very-long-name',
        rightTitle: rebase ? '本次提交' : '合入版本 · main',
        leftSource: '12345678 · 左侧提交摘要',
        rightSource: 'abcdef01 · 右侧提交摘要',
        leftAction: rebase ? '采用目标历史' : '采用当前分支',
        rightAction: rebase ? '采用本次提交' : '采用合入版本',
      );
      final s = CompareSession(
        TextFile.empty('LEFT'),
        TextFile.empty('RIGHT'),
        base: TextFile.empty('BASE'),
        mergeLabels: labels,
      );
      await tester.pumpWidget(
        FmergeApp(settings: Settings(persist: false), initial: s),
      );
      await ready(tester);
      expect(find.text(labels.summary), findsOneWidget);
      expect(find.text(labels.leftTitle), findsOneWidget);
      expect(find.text(labels.rightSource), findsOneWidget);
      expect(find.text('本地 · Local'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, labels.leftAction));
      await tester.pumpAndSettle();
      expect(s.resultEditor!.text, 'LEFT');
      await tester.tap(find.widgetWithText(OutlinedButton, labels.rightAction));
      await tester.pumpAndSettle();
      expect(s.resultEditor!.text, 'RIGHT');
      await chooseMenuCommand(tester, 'choose-base', menu: '合并');
      expect(s.resultEditor!.text, 'BASE');
      expect(s.pending, 0);
      tester
          .widgetList<CodePane>(find.byType(CodePane))
          .last
          .focus
          .requestFocus();
      await tester.pumpAndSettle();
      await chooseMenuCommand(tester, 'undo', menu: '编辑');
      expect(s.resultEditor!.text, 'RIGHT');
      await chooseMenuCommand(tester, 'redo', menu: '编辑');
      expect(s.resultEditor!.text, 'BASE');
      await tester.tap(find.byTooltip('查看合并来源与角色'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ours / current / LOCAL'), findsOneWidget);
      expect(find.textContaining('theirs / incoming / REMOTE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('保存按钮写入真实输出文件，外部修改需要显式确认', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fmerge-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/right.txt')..writeAsStringSync('old');
    final s = CompareSession(
      TextFile.empty('left'),
      (await tester.runAsync(() => TextFile.read(file.path)))!,
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await ready(tester);
    s.rightEditor.runRevocableOp(() => s.rightEditor.text = 'new');
    await tester.pump(const Duration(milliseconds: 170));
    await ready(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('command-save')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (s.rightDirty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(file.readAsStringSync(), 'new');
    expect(s.dirty, false);
    file.writeAsStringSync('external');
    s.rightEditor.text = 'mine';
    await tester.pump(const Duration(milliseconds: 170));
    await ready(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('command-save')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (find.text('磁盘文件已经改变').evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('磁盘文件已经改变'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(file.readAsStringSync(), 'external');
  });
  for (final command in ['close', 'open']) {
    testWidgets('${command == 'close' ? '关闭' : '打开文件'}时保存期间的新输入阻止离开，再次保存后可离开', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('fmerge-leave-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final previous = FileSelectorPlatform.instance;
      final picker = _Picker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final s = _EditDuringSave('${dir.path}/out');
      s.choose(s.merger!.state.regions.single.chunk.id, MergeChoice.left);
      int? code;
      await tester.pumpWidget(
        FmergeApp(
          settings: Settings(persist: false),
          initial: s,
          onExit: (value) => code = value,
        ),
      );
      await ready(tester);
      Future<void> leaveAndSave() async {
        await chooseMenuCommand(tester, command, menu: '文件');
        expect(find.text('有尚未保存的修改'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(FilledButton, '保存'));
          await tester.pump();
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (find
                  .byKey(const ValueKey('command-save'))
                  .evaluate()
                  .isNotEmpty &&
              tester
                      .widget<ToolbarAction>(
                        find.byKey(const ValueKey('command-save')),
                      )
                      .icon ==
                  Icons.hourglass_empty) {
            if (DateTime.now().isAfter(deadline)) fail('等待保存完成超时');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
      }

      await leaveAndSave();
      expect(s.savedMerge, true);
      expect(File('${dir.path}/out').readAsStringSync(), 'L');
      expect(s.resultEditor!.text, 'new edit while saving');
      expect(s.resultDirty, true);
      expect(code, isNull);
      expect(picker.calls, 0);
      s.editDuringSave = false;
      await leaveAndSave();
      expect(
        File('${dir.path}/out').readAsStringSync(),
        'new edit while saving',
      );
      expect(s.dirty, false);
      expect(code, command == 'close' ? 0 : isNull);
      expect(picker.calls, command == 'open' ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('未解决冲突无法保存，取消关闭不丢失结果', (tester) async {
    int? code;
    final s = CompareSession(
      TextFile.empty('L'),
      TextFile.empty('R'),
      base: TextFile.empty('B'),
    );
    await tester.pumpWidget(
      FmergeApp(
        settings: Settings(persist: false),
        initial: s,
        onExit: (value) => code = value,
      ),
    );
    await ready(tester);
    await tester.tap(find.byKey(const ValueKey('command-save')));
    await tester.pump();
    expect(find.textContaining('请先确认剩余'), findsOneWidget);
    expect(s.savedMerge, false);
    await tester.tap(find.byKey(const ValueKey('menu-文件')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('关闭'));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('有尚未保存的修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(code, isNull);
    expect(s.pending, 1);
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

// 使用真实保存，在快照提交后、异步写入完成前注入下一次输入。
class _EditDuringSave extends CompareSession {
  _EditDuringSave(String path)
    : super(
        TextFile.empty('L'),
        TextFile.empty('R'),
        base: TextFile.empty('B'),
        output: TextFile.empty()..path = path,
      );
  bool editDuringSave = true;

  @override
  Future<void> saveResult({
    String? destination,
    bool backup = true,
    bool force = false,
    TextEncoding? encoding,
    String? eol,
    bool usePendingFormat = true,
  }) async {
    final saving = super.saveResult(
      destination: destination,
      backup: backup,
      force: force,
      encoding: encoding,
      eol: eol,
      usePendingFormat: usePendingFormat,
    );
    if (editDuringSave) resultEditor!.text = 'new edit while saving';
    await saving;
  }
}
