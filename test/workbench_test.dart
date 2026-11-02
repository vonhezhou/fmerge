import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/workbench.dart';

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
  testWidgets('欢迎页不点击任何控件即可使用 Ctrl O 打开比较', (tester) async {
    await tester.pumpWidget(FmergeApp(settings: Settings(persist: false)));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('打开文件比较'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(OutlinedButton, '采用本地'));
      await tester.pumpAndSettle();
      expect(merge.resultEditor!.text, 'a\nL\nc');
      merge.resultEditor!.text = 'header\na\nL\nc';
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '采用远端'));
      await tester.pumpAndSettle();
      expect(merge.resultEditor!.text, 'header\na\nR\nc');
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
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
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
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
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
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.textContaining('请先确认剩余'), findsOneWidget);
    expect(s.savedMerge, false);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('有尚未保存的修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(code, isNull);
    expect(s.pending, 1);
  });
}
