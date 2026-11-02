import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/core/merge_labels.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/workbench.dart';
import 'package:fmerge/ui/git_dialog.dart';

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
  testWidgets('Git 界面只暂存勾选的块，并可从 Staged 取消暂存', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('fmerge-git-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/file');
    final lines = List.generate(30, (i) => 'line $i');
    final original = '${lines.join('\n')}\n';
    Future<String> git(List<String> args) async {
      final result = await Process.run('git', args, workingDirectory: dir.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout as String;
    }

    await tester.runAsync(() async {
      await git(['init', '-q']);
      await file.writeAsString(original);
      await git(['add', '.']);
      await git([
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.invalid',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'core.hooksPath=/dev/null',
        'commit',
        '-qm',
        'fixture',
      ]);
      lines[3] = 'selected';
      lines[25] = 'keep unstaged';
      await file.writeAsString('${lines.join('\n')}\n');
    });
    Future<void> waitFor(String text) async {
      await tester.pump();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (find.text(text).evaluate().isEmpty ||
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty) {
          if (DateTime.now().isAfter(deadline)) fail('Git 界面操作超时：$text');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
    }

    // 真实子进程必须从 runAsync 启动，避免其 I/O 被测试虚拟时钟挂起。
    await tester.runAsync(
      () => tester.pumpWidget(MaterialApp(home: GitDialog(path: file.path))),
    );
    await waitFor('差异块 2');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('暂存所选块')));
    await waitFor('所选差异块已暂存，其余修改保留在工作区');
    await tester.runAsync(() async {
      final index = await git(['show', ':file']);
      expect(index, contains('selected'));
      expect(index, isNot(contains('keep unstaged')));
    });
    await tester.runAsync(() => tester.tap(find.text('Staged · 已暂存')));
    await waitFor('差异块 1');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('取消暂存所选块')));
    await waitFor('此文件没有已暂存修改');
    await tester.runAsync(() async {
      expect(await git(['show', ':file']), original);
      expect(await file.readAsString(), '${lines.join('\n')}\n');
    });
    expect(tester.takeException(), isNull);
  });

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
    await tester.tap(find.byTooltip('仅显示差异及前后 3 行'));
    await tester.pumpAndSettle();
    expect(s.contextOnly, true);
    expect(s.leftEditor.diffLayout!.totalRows, 9);
    expect(s.rightEditor.text, right.join('\n'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('显示整个文件'));
    await tester.pumpAndSettle();
    expect(s.leftEditor.diffLayout!.totalRows, 80);
    await tester.tap(find.byTooltip('交换左右文件'));
    await ready(tester);
    expect(s.leftEditor.text, right.join('\n'));
    expect(s.rightEditor.text, lines.join('\n'));
    s.rightEditor.text = s.leftEditor.text.replaceFirst('line 0', 'line  0');
    await tester.pump(const Duration(milliseconds: 170));
    await ready(tester);
    expect(s.diff!.changes.length, 1);
    await tester.tap(find.byTooltip('隐藏空白字符差异'));
    await ready(tester);
    expect(s.diff!.changes, isEmpty);
    await tester.tap(find.byTooltip('显示空白字符差异'));
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
