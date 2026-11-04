import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/session.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('文本快照在编辑、撤销、重做和全文替换后保持最新', () {
    final controller = CodeLineEditingController.fromText('alpha\nbeta');
    addTearDown(controller.dispose);
    expect(controller.text, 'alpha\nbeta');
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 5,
    );
    controller.composing = const TextRange(start: 0, end: 5);
    expect(controller.text, 'alpha\nbeta');
    controller.clearComposing();
    controller.runRevocableOp(() => controller.text = 'edited\nbeta\n');
    expect(controller.text, 'edited\nbeta\n');
    controller.undo();
    expect(controller.text, 'alpha\nbeta');
    controller.redo();
    expect(controller.text, 'edited\nbeta\n');
    controller.codeLines = CodeLines.fromText('replacement');
    expect(controller.text, 'replacement');
  });

  test('左右交换、采用差异与撤销后，文本和未保存状态不受快照复用影响', () async {
    final session = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
    );
    addTearDown(session.dispose);
    await session.refresh();
    session.applyHunk(0);
    expect(session.rightEditor.text, 'left');
    expect(session.rightDirty, true);
    session.rightEditor.undo();
    expect(session.rightEditor.text, 'right');
    expect(session.rightDirty, false);
    await session.refresh();
    session.swapSides();
    expect(session.leftEditor.text, 'right');
    expect(session.rightEditor.text, 'left');
    expect(session.dirty, false);
    await session.refresh();
  });

  test('未保存状态在磁盘基线和输出目标变化后重新判断，格式状态独立计入', () async {
    final output = TextFile.empty('saved\r\n');
    final session = CompareSession(
      TextFile.empty('left\r\n'),
      TextFile.empty('source\n'),
      output: output,
    );
    addTearDown(session.dispose);
    expect(session.leftDirty, false);
    expect(session.rightDirty, true);
    session.rightEditor.text = 'saved\n';
    expect(session.rightDirty, false);
    output.original = 'new disk baseline\n';
    expect(session.rightDirty, true);
    output.original = 'saved\n';
    expect(session.rightDirty, false);
    session.right.original = 'changed source';
    expect(session.rightDirty, false, reason: '指定输出时应比较输出文件的保存基线');
    session.left.original = 'external\n';
    expect(session.leftDirty, true);
    session.left.original = 'left\n';
    expect(session.leftDirty, false);
    session.setSaveEol(1, '\r\n');
    expect(session.rightDirty, true);
    session.inputSaved(side: 1);
    expect(session.rightDirty, false);
    await session.refresh();
  });
}
