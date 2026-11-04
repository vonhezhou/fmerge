import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/diff_navigation.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/diff_overview.dart';
import 'package:fmerge/ui/document_status.dart';
import 'package:fmerge/ui/line_details.dart';

import 'support/menus.dart';

CompareSession session(String left, String right, {String? base}) =>
    CompareSession(
      TextFile.empty(left),
      TextFile.empty(right),
      base: base == null ? null : TextFile.empty(base),
      compareRunner: (task) async => runCompareTask(task),
    );

void desktopTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

void main() {
  test('行内导航保留同一行的替换与纯插入位置，双向循环且不切开字素', () {
    final diff = compare(const DiffInput('a OLD b c', 'a NEW b EXTRA c'));
    final targets = inlineTargets(diff, 0);
    expect(targets.length, 2);
    expect(targets.last.start, targets.last.end);
    expect(adjacentInlineTarget(targets, 0, -1, 1), same(targets.first));
    expect(
      adjacentInlineTarget(targets, 0, targets.first.start, 1),
      same(targets.last),
    );
    expect(
      adjacentInlineTarget(targets, 0, targets.last.start, 1),
      same(targets.first),
    );
    expect(
      adjacentInlineTarget(targets, 0, targets.first.start, -1),
      same(targets.last),
    );
    final emoji = inlineTargets(
      compare(const DiffInput('x👨‍👩‍👧‍👦z', 'x👩‍💻z')),
      1,
    ).single;
    expect('x👩‍💻z'.substring(emoji.start, emoji.end), '👩‍💻');
  });

  test('纯删除切到存在真实文本的一侧，空白忽略后无导航目标', () {
    final targets = inlineTargets(
      compare(const DiffInput('a\ndeleted\nz', 'a\nz')),
      1,
    );
    expect(targets.single.side, 0);
    expect(targets.single.line, 1);
    expect(
      inlineTargets(
        compare(
          const DiffInput(
            ' x',
            'x',
            CompareOptions(whitespace: WhitespaceMode.edges),
          ),
        ),
        0,
      ),
      isEmpty,
    );
    expect(lineAtRow([0, 3, 4], 1), isNull);
    expect(lineAtRow([0, 3, 4], 3), 1);
  });

  test('折叠后行详情仍取真实行；合并统计分别对照祖先；Tab 跟随文件交换且不计脏', () async {
    final s = session(
      List.generate(50, (i) => '$i').join('\n'),
      List.generate(50, (i) => i == 25 ? 'changed' : '$i').join('\n'),
    );
    addTearDown(s.dispose);
    await s.refresh();
    s.setContextOnly(true);
    expect(s.lineDetails(1, 25)!.left, '25');
    expect(s.lineDetails(1, 25)!.rightLine, 25);
    s.leftEditor.displayTabSize = 8;
    expect(s.dirty, false);
    s.swapSides();
    await s.refresh();
    expect(s.rightEditor.displayTabSize, 8);
    final merge = session('a\nleft\nz', 'a\nb\nright\nz', base: 'a\nb\nz');
    addTearDown(merge.dispose);
    await merge.refresh();
    expect(merge.branchDiffs![0].removed, 1);
    expect(merge.branchDiffs![0].added, 1);
    expect(merge.branchDiffs![1].removed, 0);
    expect(merge.branchDiffs![1].added, 1);
  });

  test('插入冲突的详情显示插入内容，合并结果非冲突行不显示过期详情', () async {
    final s = session('a\nLEFT\nz', 'a\nRIGHT\nz', base: 'a\nz');
    addTearDown(s.dispose);
    await s.refresh();
    final row = s.conflictDetails(s.merger!.state.regions.single.start)!;
    expect(row.left, 'LEFT');
    expect(row.right, 'RIGHT');
    expect(s.conflictDetails(0), isNull);
  });

  desktopTest('行内导航选中片段，详情同步且工具栏复制真实文本，左侧锁定禁用粘贴', (tester) async {
    final s = session('header\na OLD b OLD2\nend', 'header\na NEW b NEW2\nend');
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await tester.pumpAndSettle();
    await chooseMenuCommand(tester, 'nextInlineDiff', menu: '更多操作');
    await tester.pumpAndSettle();
    expect(s.rightEditor.selection.startIndex, 1);
    expect(s.rightEditor.selectedText, 'NEW');
    expect(
      tester.widget<LineDetails>(find.byType(LineDetails)).row!.left,
      'a OLD b OLD2',
    );
    await chooseMenuCommand(tester, 'nextInlineDiff', menu: '更多操作');
    await tester.pumpAndSettle();
    expect(s.rightEditor.selectedText, 'NEW');
    expect(s.rightEditor.selection.startOffset, greaterThan(6));
    await chooseMenuCommand(tester, 'previousInlineDiff', menu: '更多操作');
    await tester.pumpAndSettle();
    expect(s.rightEditor.selection.startOffset, 2);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await chooseMenuCommand(tester, 'copy', menu: '更多操作');
    await tester.pumpAndSettle();
    expect(copied, 'NEW');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    tester
        .widgetList<CodePane>(find.byType(CodePane))
        .first
        .focus
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const ValueKey('command-paste')),
          )
          .enabled,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  desktopTest('概览条点击和拖动同步滚动，隐藏详情和概览不改变文档', (tester) async {
    final lines = List.generate(300, (i) => 'line $i');
    final s = session(
      lines.join('\n'),
      ([...lines]..[200] = 'changed').join('\n'),
    );
    final settings = Settings(persist: false);
    await tester.pumpWidget(FmergeApp(settings: settings, initial: s));
    await tester.pumpAndSettle();
    final panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
    final overview = find.byType(DiffOverview);
    final bounds = tester.getRect(overview);
    await tester.tapAt(
      Offset(bounds.center.dx, bounds.top + bounds.height * .8),
    );
    await tester.pumpAndSettle();
    expect(panes.first.scroll.verticalScroller.offset, greaterThan(1000));
    expect(
      panes.first.scroll.verticalScroller.offset,
      panes.last.scroll.verticalScroller.offset,
    );
    await tester.dragFrom(
      Offset(bounds.center.dx, bounds.center.dy),
      Offset(0, -bounds.height * .3),
    );
    await tester.pumpAndSettle();
    expect(panes.first.scroll.verticalScroller.offset, lessThan(2000));
    await chooseMenuCommand(tester, 'toggleOverview');
    await chooseMenuCommand(tester, 'toggleLineDetails');
    await tester.pumpAndSettle();
    expect(find.byType(DiffOverview), findsNothing);
    expect(find.byType(LineDetails), findsNothing);
    expect(s.leftEditor.text, lines.join('\n'));
    expect(s.dirty, false);
    expect(settings.preferencesJson()['showOverview'], false);
    expect(tester.takeException(), isNull);
  });

  desktopTest('每侧 Tab 调整改变绘制宽度但保留文本、选择、历史和另一侧设置', (tester) async {
    final text = '${'\t' * 40}x';
    final s = session(text, text);
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await tester.pumpAndSettle();
    final pane = tester.widgetList<CodePane>(find.byType(CodePane)).last;
    final before = pane.scroll.horizontalScroller.position.maxScrollExtent;
    s.rightEditor.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 1,
    );
    final selection = s.rightEditor.selection;
    final menu = find.descendant(
      of: find.byType(DocumentStatus).last,
      matching: find.byType(PopupMenuButton<int>),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Tab 8'));
    await tester.pumpAndSettle();
    expect(
      pane.scroll.horizontalScroller.position.maxScrollExtent,
      greaterThan(before),
    );
    expect(s.rightEditor.text, text);
    expect(s.rightEditor.selection, selection);
    expect(s.rightEditor.selectedText, '\t');
    expect(s.rightEditor.canUndo, false);
    expect(s.leftEditor.displayTabSize, 4);
    expect(s.dirty, false);
    expect(tester.takeException(), isNull);
  });
}
