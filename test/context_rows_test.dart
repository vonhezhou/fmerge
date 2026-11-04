import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/context_rows.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/session.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('会话默认快速比较忽略换行但不改原文，精确换行模式仍显示差异', () async {
    final s = CompareSession(
      TextFile.empty('a\r\nb\r\n'),
      TextFile.empty('a\nb\n'),
    );
    addTearDown(s.dispose);
    await s.refresh();
    expect(s.diff!.changes, isEmpty);
    expect(s.left.original, 'a\r\nb\r\n');
    expect(s.leftEditor.text, 'a\nb\n');
    await s.refresh(const CompareOptions(ignoreEol: false));
    expect(s.diff!.changes, isNotEmpty);
    expect(s.left.original, 'a\r\nb\r\n');
    expect(s.dirty, false);
  });
  test('大文件未改动行不创建空的行内装饰，实际差异仍有高亮', () async {
    final lines = List.generate(10000, (i) => 'line $i');
    final modified = [...lines]..[5000] = 'changed line';
    final s = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(modified.join('\n')),
    );
    addTearDown(s.dispose);
    await s.refresh();
    expect(s.leftEditor.diffLayout!.ranges.keys, [5000]);
    expect(s.rightEditor.diffLayout!.ranges.keys, [5000]);
    expect(s.rightEditor.diffLayout!.ranges[5000], isNotEmpty);
    s.setShowWhitespace(true);
    expect(s.rightEditor.diffLayout!.ranges.keys, [5000]);
    expect(s.rightEditor.diffLayout!.lineRows.length, 10000);
  });
  test('折叠保留差异前后 3 行，合并相邻上下文，首尾使用提示行', () {
    final map = ContextRows(40, {10, 11, 17, 30});
    expect(map.hidden, {
      ...List.generate(7, (i) => i),
      ...List.generate(6, (i) => 21 + i),
      ...List.generate(6, (i) => 34 + i),
    });
    expect(map.labels.length, 3);
    expect(map.rows[10], 4);
    expect(map.rows[17], 11);
    expect(map.totalRows, 24);
    expect(ContextRows(20, {}).totalRows, 1);
    expect(ContextRows(0, {}).totalRows, 0);
  });

  test('双栏折叠保持插入对齐、完整复制与可逆展开；导航隐藏行自动展开', () async {
    final lines = List.generate(60, (i) => 'line $i');
    final right = [...lines]..insertAll(25, ['insert 1', 'insert 2']);
    final s = CompareSession(
      TextFile.empty(lines.join('\n')),
      TextFile.empty(right.join('\n')),
    );
    addTearDown(s.dispose);
    await s.refresh();
    final full = s.leftEditor.diffLayout!.lineRows;
    s.setContextOnly(true);
    expect(s.leftEditor.diffLayout!.totalRows, 10);
    expect(s.rightEditor.diffLayout!.totalRows, 10);
    expect(s.hunkRows, [4]);
    s.rightEditor.selection = const CodeLineSelection.collapsed(
      index: 25,
      offset: 0,
    );
    expect(s.contextOnly, true, reason: '另一栏的旧光标位于隐藏行，不应触发展开');
    expect(
      s.leftEditor.diffLayout!.lineRows[25],
      s.rightEditor.diffLayout!.lineRows[27],
    );
    s.rightEditor.selectAll();
    expect(s.rightEditor.selectedText, right.join('\n'));
    s.setContextOnly(true);
    s.rightEditor.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    expect(s.contextOnly, false);
    expect(s.leftEditor.diffLayout!.lineRows, full);
    expect(s.dirty, false);
  });

  test('交换保留未保存文本、文件身份与撤销历史', () async {
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    addTearDown(s.dispose);
    final original = s.right;
    s.rightEditor.runRevocableOp(() => s.rightEditor.text = 'edited');
    await s.refresh();
    s.swapSides();
    expect(s.left, same(original));
    expect(s.leftEditor.text, 'edited');
    expect(s.leftDirty, true);
    expect(s.rightEditor.text, 'left');
    s.leftEditor.undo();
    expect(s.leftEditor.text, 'right');
    expect(s.leftDirty, false);
    await s.refresh();
  });
}
