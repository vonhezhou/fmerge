import 'dart:math';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';

import 'package:fmerge/core/files.dart';
import 'package:fmerge/session.dart';

/// 内容检查和局部输入不得通过序列化未改动行来判断变化。
class NoSerializationLine extends CodeLine {
  const NoSerializationLine(super.text);
  @override
  String asString(int start, TextLineBreak lineBreak) =>
      throw StateError('局部编辑不应拼接全文');
}

class CountingHiddenLines extends SetBase<int> {
  CountingHiddenLines(this.values);
  final Set<int> values;
  int lookups = 0;
  @override
  bool contains(Object? value) {
    lookups++;
    return values.contains(value);
  }

  @override
  Iterator<int> get iterator => values.iterator;
  @override
  int get length => values.length;
  @override
  int? lookup(Object? value) => values.lookup(value);
  @override
  bool add(int value) => values.add(value);
  @override
  bool remove(Object? value) => values.remove(value);
  @override
  Set<int> toSet() => values.toSet();
}

void main() {
  test('局部输入、未保存判断、撤销与组合区更新不序列化未改动行', () {
    final lines = List.generate(3000, (i) => 'line $i');
    final session = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(lines.join('\n')),
    );
    addTearDown(session.dispose);
    final editor = session.rightEditor;
    editor.codeLines = CodeLines.of(lines.map(NoSerializationLine.new));
    expect(session.dirty, false);
    editor.selection = const CodeLineSelection.collapsed(
      index: 1500,
      offset: 4,
    );
    editor.composing = const TextRange(start: 0, end: 4);
    editor.clearComposing();
    editor.runRevocableOp(() => editor.replaceSelection('x'));
    expect(session.rightDirty, true);
    editor.undo();
    expect(session.rightDirty, false);
    editor.redo();
    expect(session.rightDirty, true);
    expect(editor.codeLines[1500].text, 'linex 1500');
  });

  test('分段统计在随机局部替换、跨行粘贴、删除及撤销后与实际文本一致', () {
    final random = Random(1007);
    final editor = CodeLineEditingController.fromText(
      List.generate(1100, (i) => 'line $i 👩‍💻').join('\n'),
    );
    addTearDown(editor.dispose);
    for (var i = 0; i < 100; i++) {
      final line = random.nextInt(editor.lineCount);
      editor.selection = CodeLineSelection.collapsed(index: line, offset: 0);
      editor.runRevocableOp(
        () => editor.replaceSelection(i.isEven ? 'new\n👨‍👩‍👧‍👦\n' : 'x'),
      );
      final text = editor.text;
      expect(editor.codeLines.textLength(TextLineBreak.lf), text.length);
      expect(editor.lineCount, text.split('\n').length);
      if (i % 5 == 0) {
        editor.undo();
        expect(
          editor.codeLines.textLength(TextLineBreak.lf),
          editor.text.length,
        );
        editor.redo();
        expect(editor.text, text);
      }
    }
    final snapshot = CodeLines.from(editor.codeLines);
    final original = snapshot.asString(TextLineBreak.lf);
    final changed = CodeLines.from(snapshot)..[0] = const CodeLine('different');
    expect(snapshot.asString(TextLineBreak.lf), original);
    expect(changed.contentEquals(snapshot), false);
  });

  test('不同分段与折叠结构按展开正文判断，换行长度与统计保持一致', () {
    final flat = CodeLines.of([
      const CodeLine('one'),
      const CodeLine('two'),
      const CodeLine('three'),
    ]);
    final folded = CodeLines.of([
      const CodeLine('one', [CodeLine('two'), CodeLine('three')]),
    ]);
    expect(flat.contentEquals(folded), true);
    expect(folded.contentEquals(flat), true);
    expect(flat.equals(folded), false);
    for (final eol in [TextLineBreak.lf, TextLineBreak.crlf]) {
      expect(folded.textLength(eol), folded.asString(eol).length);
    }
    final a = CodeLines.of(List.generate(1500, (i) => CodeLine('$i')));
    final b = CodeLines([
      CodeLineSegment.of(
        codeLines: [for (var i = 0; i < 37; i++) CodeLine('$i')],
      ),
      ...a.sublines(37).segments,
    ]);
    expect(a.equals(b), true);
    expect(b.contentEquals(a), true);
    final segment = CodeLineSegment.of(
      codeLines: [const CodeLine('longer'), const CodeLine('two')],
    );
    segment.length = 1;
    expect(segment.charCount, 6);
    expect(segment.lineCount, 1);
    segment.add(const CodeLine('a', [CodeLine('child')]));
    expect(segment.charCount, 12);
    expect(segment.lineCount, 3);
  });

  test('移动光标与组合区变化不创建正文历史，撤销后移动光标仍可重做', () {
    final editor = CodeLineEditingController.fromText('abc\ndef');
    addTearDown(editor.dispose);
    editor.selection = const CodeLineSelection.collapsed(index: 1, offset: 0);
    editor.composing = const TextRange(start: 0, end: 1);
    editor.clearComposing();
    expect(editor.canUndo, false);
    editor.runRevocableOp(() => editor.replaceSelection('x'));
    editor.undo();
    expect(editor.codeLines[1].text, 'def');
    editor.selection = const CodeLineSelection.collapsed(index: 0, offset: 2);
    expect(editor.canRedo, true);
    editor.redo();
    expect(editor.codeLines[1].text, 'xdef');
  });

  testWidgets('折叠视图直接遍历可见行索引，跨越长隐藏区不逐行扫描', (tester) async {
    final editor = CodeLineEditingController.fromText(
      List.generate(10000, (i) => 'line $i').join('\n'),
    );
    final scroll = CodeScrollController();
    addTearDown(() {
      editor.dispose();
      scroll.dispose();
    });
    final hidden = CountingHiddenLines({for (var i = 100; i < 9900; i++) i});
    editor.diffLayout = CodeDiffLayout(
      lineRows: [
        for (var i = 0; i < 10000; i++)
          i < 100
              ? i
              : i < 9900
              ? 100
              : i - 9799,
      ],
      visibleLines: [
        for (var i = 0; i < 100; i++) i,
        for (var i = 9900; i < 10000; i++) i,
      ],
      hiddenLines: hidden,
      totalRows: 201,
      rowLabels: const {100: 'hidden'},
    );
    CodeIndicatorValueNotifier? notifier;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: editor,
            scrollController: scroll,
            wordWrap: false,
            indicatorBuilder: (context, editing, chunks, value) {
              notifier = value;
              return const SizedBox(width: 20);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    hidden.lookups = 0;
    scroll.verticalScroller.jumpTo(
      scroll.verticalScroller.position.maxScrollExtent / 2,
    );
    await tester.pumpAndSettle();
    expect(hidden.lookups, lessThan(500));
    expect(notifier!.value!.paragraphs.any((p) => p.index >= 9900), true);
    expect(
      notifier!.value!.paragraphs.any((p) => hidden.values.contains(p.index)),
      false,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('超高亮预算直接显示可见行纯文本，编辑后不提交全文序列化任务', (tester) async {
    final editor = CodeLineEditingController(
      codeLines: CodeLines.of([
        const NoSerializationLine('final value = 12345;'),
        const NoSerializationLine('second line'),
      ]),
    );
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: editor,
            style: CodeEditorStyle(
              codeTheme: CodeHighlightTheme(
                theme: const {},
                languages: {
                  'dart': CodeHighlightThemeMode(mode: langDart, maxSize: 8),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    editor.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
    editor.runRevocableOp(() => editor.replaceSelection('x'));
    await tester.pumpAndSettle();
    expect(editor.codeLines.first.text, 'xfinal value = 12345;');
    expect(editor.codeLines.last.text, 'second line');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
