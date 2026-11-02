import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/merge.dart';
import 'package:fmerge/session.dart';

void main() {
  test('保存期间的新输入继续保持未保存，不能误报 Git 合并成功', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-concurrent-');
    addTearDown(() => dir.delete(recursive: true));
    final session = CompareSession(
      TextFile.empty('L'),
      TextFile.empty('R'),
      base: TextFile.empty('B'),
      output: TextFile.empty()..path = '${dir.path}/out',
    );
    addTearDown(session.dispose);
    session.choose(
      session.merger!.state.regions.single.chunk.id,
      MergeChoice.left,
    );
    final saving = session.saveResult();
    session.resultEditor!.text = 'new edit while saving';
    await saving;
    expect(await File('${dir.path}/out').readAsString(), 'L');
    expect(session.resultDirty, true);
    expect(session.toolExitCode, 1);
  });
  test('手工确认冲突不重置光标', () {
    final session = CompareSession(
      TextFile.empty('L\nnext'),
      TextFile.empty('R\nnext'),
      base: TextFile.empty('B\nnext'),
    );
    addTearDown(session.dispose);
    session.resultEditor!.selection = session.resultEditor!.selection.copyWith(
      baseIndex: 1,
      baseOffset: 2,
      extentIndex: 1,
      extentOffset: 2,
    );
    session.markResolved(session.merger!.state.regions.single.chunk.id, true);
    expect(session.resultEditor!.selection.extentIndex, 1);
    expect(session.resultEditor!.selection.extentOffset, 2);
  });
}
