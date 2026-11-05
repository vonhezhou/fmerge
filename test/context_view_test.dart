import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/context_rows.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/diff_overview.dart';

void main() {
  testWidgets('多段省略和自动换行仍绘制文件原始行号', (tester) async {
    final controller = CodeLineEditingController.fromText(
      List.generate(
        120,
        (i) => i == 20 ? 'long value ' * 80 : 'line $i',
      ).join('\n'),
    );
    final wrap = CodeDiffWrap();
    addTearDown(controller.dispose);
    addTearDown(wrap.dispose);
    final map = ContextRows(120, {20, 80}, context: 1, placeholderRows: 2);
    controller.diffLayout = CodeDiffLayout(
      lineRows: map.rows,
      totalRows: map.totalRows,
      hiddenLines: map.hidden,
      visibleLines: [
        for (var i = 0; i < 120; i++)
          if (!map.hidden.contains(i)) i,
      ],
      rowLabels: map.labels,
      placeholderRows: 2,
      wrap: wrap,
    );
    final numbers = <int>{};
    for (final wordWrap in [false, true, false]) {
      numbers.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodeEditor(
              controller: controller,
              wordWrap: wordWrap,
              chunkAnalyzer: const NonCodeChunkAnalyzer(),
              style: const CodeEditorStyle(fontSize: 14, fontHeight: 1.5),
              indicatorBuilder: (_, editing, chunks, notifier) =>
                  DefaultCodeLineNumber(
                    controller: editing,
                    notifier: notifier,
                    customLineIndex2Text: (index) {
                      numbers.add(index);
                      return '${index + 1}';
                    },
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(numbers, containsAll([19, 20, 21, 79, 80, 81]));
      expect(numbers, isNot(contains(22)), reason: '第二段不能接着第一段的可见行编号');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '概览位于右侧，点击省略带恢复全文并定位原始行',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lines = List.generate(120, (i) => 'line $i');
      final changed = [...lines]..[30] = 'changed 30';
      changed[70] = 'changed 70';
      final s = CompareSession(
        TextFile.empty(lines.join('\n')),
        TextFile.empty(changed.join('\n')),
        compareRunner: (task) async => runCompareTask(task),
      );
      final settings = Settings(persist: false)..contextOnly = true;
      await tester.pumpWidget(FmergeApp(settings: settings, initial: s));
      await tester.pumpAndSettle();
      expect(s.comparisonCurrent, true);
      expect(
        tester.getRect(find.byType(DiffOverview)).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(CodePane).last).right),
      );
      final layout = s.rightEditor.diffLayout!;
      expect(layout.placeholderRows, 2);
      expect(layout.rowLabels.values.last, contains('原始行 L75–L120'));
      final editor = tester.getRect(find.byType(CodeEditor).last);
      final first = tester
          .widgetList<DefaultCodeLineNumber>(find.byType(DefaultCodeLineNumber))
          .last
          .notifier
          .value!
          .paragraphs
          .first;
      final unit = first.preferredLineHeight;
      final base = first.offset.dy - layout.lineRows[first.index] * unit;
      final row = layout.rowLabels.keys.last;
      await tester.tapAt(
        Offset(editor.center.dx, editor.top + base + (row + 1) * unit),
      );
      await tester.pumpAndSettle();
      expect(s.contextOnly, false);
      expect(settings.contextOnly, true, reason: '临时显示全文保留下次打开的折叠偏好');
      expect(s.rightEditor.selection.extentIndex, 74);
      expect(s.rightEditor.text, changed.join('\n'));
      expect(s.dirty, false);
      final shown = tester
          .widgetList<DefaultCodeLineNumber>(find.byType(DefaultCodeLineNumber))
          .last
          .notifier
          .value!
          .paragraphs;
      expect(shown.any((paragraph) => paragraph.index == 74), true);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('通过显示全文退出折叠时保留当前原始行位置', (tester) async {
    final lines = List.generate(120, (i) => 'line $i');
    final changed = [...lines]..[80] = 'changed';
    final s = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(changed.join('\n')),
      compareRunner: (task) async => runCompareTask(task),
    );
    await tester.pumpWidget(
      FmergeApp(
        settings: Settings(persist: false)..contextOnly = true,
        initial: s,
      ),
    );
    await tester.pumpAndSettle();
    const selection = CodeLineSelection(
      baseIndex: 80,
      baseOffset: 1,
      extentIndex: 80,
      extentOffset: 5,
    );
    s.rightEditor.selection = selection;
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示全文'));
    await tester.pumpAndSettle();
    expect(s.contextOnly, false);
    expect(s.rightEditor.selection, selection);
    final shown = tester
        .widgetList<DefaultCodeLineNumber>(find.byType(DefaultCodeLineNumber))
        .last
        .notifier
        .value!
        .paragraphs;
    expect(shown.any((paragraph) => paragraph.index == 80), true);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('手动滚动到另一段差异后显示全文，保留正在查看的区域', (tester) async {
    final lines = List.generate(400, (i) => 'line $i');
    final changed = [...lines]..[80] = 'changed 80';
    changed[250] = 'changed 250';
    final s = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(changed.join('\n')),
      compareRunner: (task) async => runCompareTask(task),
    );
    await tester.pumpWidget(
      FmergeApp(
        settings: Settings(persist: false)
          ..contextOnly = true
          ..contextLines = 12,
        initial: s,
      ),
    );
    await tester.pumpAndSettle();
    final pane = tester.widgetList<CodePane>(find.byType(CodePane)).last;
    pane.scroll.verticalScroller.jumpTo(
      pane.scroll.verticalScroller.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    expect(s.rightEditor.selection.extentIndex, 0);
    await tester.tap(find.text('显示全文'));
    await tester.pumpAndSettle();
    expect(s.rightEditor.selection.extentIndex, greaterThan(230));
    final shown = tester
        .widgetList<DefaultCodeLineNumber>(find.byType(DefaultCodeLineNumber))
        .last
        .notifier
        .value!
        .paragraphs;
    expect(
      shown.any((p) => p.index == s.rightEditor.selection.extentIndex),
      true,
    );
    expect(tester.takeException(), isNull);
  });
}
