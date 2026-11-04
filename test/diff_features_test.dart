import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';

import 'support/menus.dart';

CompareSession comparison(String a, String b, {String? base}) => CompareSession(
  TextFile.empty(a),
  TextFile.empty(b),
  base: base == null ? null : TextFile.empty(base),
  compareRunner: (task) async => runCompareTask(task),
);

void main() {
  test('单词高亮选中完整标识符，字符高亮精确定位且保留字素边界', () {
    const a = 'getUserName(👨‍👩‍👧‍👦);', b = 'getUserNames(👩‍💻);';
    final chars = compare(const DiffInput(a, b));
    final words = compare(
      const DiffInput(a, b, CompareOptions(inlineMode: InlineDiffMode.words)),
    );
    final row = words.rows.single;
    expect(
      b.substring(row.rightMarks.first.start, row.rightMarks.first.end),
      'getUserNames',
    );
    expect(
      a.substring(row.leftMarks.first.start, row.leftMarks.first.end),
      'getUserName',
    );
    final emoji = row.rightMarks.last;
    expect(b.substring(emoji.start, emoji.end), '👩‍💻');
    expect(
      chars.rows.single.rightMarks.first.start,
      greaterThan(row.rightMarks.first.start),
    );
    expect(words.changes.length, chars.changes.length);
  });

  test('移动块要求来源唯一且逐行精确匹配，不把复制、改缩进或重复短行当移动', () {
    const block = 'int movedValue = 42;\nreturn movedValue;';
    final context = List.generate(12, (i) => 'unchanged line $i;').join('\n');
    final a = 'start\n$block\n$context\nend';
    final b = 'start\n$context\n$block\nend';
    final diff = compare(DiffInput(a, b));
    expect(diff.movedBlocks, hasLength(1));
    final move = diff.movedBlocks.single;
    expect(
      diff.left
          .sublist(move.leftStart, move.leftStart + move.length)
          .join('\n'),
      block,
    );
    expect(
      diff.right
          .sublist(move.rightStart, move.rightStart + move.length)
          .join('\n'),
      block,
    );
    expect(
      compare(DiffInput(a, b, const CompareOptions(detectMoves: false)))
          .movedBlocks,
      isEmpty,
    );
    expect(
      compare(DiffInput(a, 'start\n$block\n$context\n$block\nend')).movedBlocks,
      isEmpty,
    );
    expect(
      compare(
        DiffInput(
          a,
          b.replaceAll('return movedValue;', '  return movedValue;'),
        ),
      ).movedBlocks,
      isEmpty,
    );
    expect(
      compare(const DiffInput('a\n}\n}\nb\nc\nd', 'a\nb\nc\nd\n}\n}'))
          .movedBlocks,
      isEmpty,
    );
  });

  test('显示偏好往返保留，损坏枚举回退字符模式', () {
    final s = Settings(persist: false)
      ..wordWrap = true
      ..detectMoves = false
      ..inlineMode = InlineDiffMode.words;
    final loaded = Settings(persist: false)
      ..readPreferences(s.preferencesJson());
    expect(loaded.wordWrap, true);
    expect(loaded.comparison, s.comparison);
    loaded.readPreferences({'inlineMode': 'invalid'});
    expect(loaded.inlineMode, InlineDiffMode.characters);
  });

  for (final merge in [false, true]) {
    testWidgets('${merge ? "三方" : "双栏"}自动换行保留对齐、占位、真实选择并随窗口和 Tab 重算', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final long = '\t中文👩‍💻 ${'long_identifier ' * 6}';
      final a = 'first\n$long\nlast\nend',
          b = 'first\nshort\ninserted\nlast\nend';
      final s = comparison(a, b, base: merge ? 'first\nbase\nlast\nend' : null);
      final settings = Settings(persist: false)..wordWrap = true;
      await tester.pumpWidget(FmergeApp(settings: settings, initial: s));
      await tester.pumpAndSettle();
      List<CodeLineRenderParagraph> paragraphs(int side) => tester
          .widgetList<DefaultCodeLineNumber>(find.byType(DefaultCodeLineNumber))
          .elementAt(side)
          .notifier
          .value!
          .paragraphs;
      CodeLineRenderParagraph line(int side, int index) =>
          paragraphs(side).firstWhere((p) => p.index == index);
      expect(line(0, 1).height, greaterThan(line(1, 1).height));
      expect(line(0, 2).offset.dy, closeTo(line(1, 3).offset.dy, .01));
      final height = s.inputWrap.totalRows;
      tester.view.physicalSize = const Size(920, 900);
      await tester.pumpAndSettle();
      expect(s.inputWrap.totalRows, greaterThanOrEqualTo(height));
      expect(line(0, 2).offset.dy, closeTo(line(1, 3).offset.dy, .01));
      s.leftEditor.displayTabSize = 8;
      await tester.pumpAndSettle();
      expect(line(0, 2).offset.dy, closeTo(line(1, 3).offset.dy, .01));
      s.leftEditor.selectAll();
      expect(s.leftEditor.selectedText, a);
      expect(s.leftEditor.canUndo, false);
      expect(s.leftDirty, false);
      final panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
      panes[0].scroll.makeVisible(const CodeLinePosition(index: 1, offset: 80));
      await tester.pumpAndSettle();
      expect(
        panes[0].scroll.verticalScroller.offset,
        panes[1].scroll.verticalScroller.offset,
      );
      if (!merge) {
        final previousHeight = s.inputWrap.totalRows;
        s.rightEditor.runRevocableOp(
          () => s.rightEditor.text = b.replaceFirst('short', long * 3),
        );
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pumpAndSettle();
        expect(s.inputWrap.totalRows, greaterThan(previousHeight));
        s.rightEditor.undo();
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pumpAndSettle();
        expect(s.rightEditor.text, b);
        expect(s.rightDirty, false);
        s.setContextOnly(true, context: 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        s.setContextOnly(false);
        await tester.pumpAndSettle();
      }
      await chooseMenuCommand(tester, 'toggleWordWrap');
      await tester.pumpAndSettle();
      expect(settings.wordWrap, false);
      expect(line(0, 1).height, line(1, 1).height);
      expect(s.leftEditor.text, a);
      expect(s.rightEditor.text, b);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('移动块提示跳转到另一侧对应真实行，显示模式切换不改正文', (tester) async {
    final context = List.generate(12, (i) => 'context $i').join('\n');
    const block = 'int movedValue = 42;\nreturn movedValue;';
    final s = comparison(
      'start\n$block\n$context\nend',
      'start\n$context\n$block\nend',
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await tester.pumpAndSettle();
    final move = s.diff!.movedBlocks.single;
    s.rightEditor.selection = CodeLineSelection.collapsed(
      index: move.rightStart,
      offset: 0,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('follow-moved-block')));
    await tester.pumpAndSettle();
    expect(s.leftEditor.selection.extentIndex, move.leftStart);
    expect(
      tester.widgetList<CodePane>(find.byType(CodePane)).first.focus.hasFocus,
      true,
    );
    expect(s.dirty, false);
    await chooseMenuCommand(tester, 'toggleWordDiff');
    await tester.pumpAndSettle();
    expect(s.options.inlineMode, InlineDiffMode.words);
    await chooseMenuCommand(tester, 'toggleMovedBlocks');
    await tester.pumpAndSettle();
    expect(s.diff!.movedBlocks, isEmpty);
    expect(s.dirty, false);
    expect(tester.takeException(), isNull);
  });
}
