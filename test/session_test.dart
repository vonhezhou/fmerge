import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/merge.dart';
import 'package:fmerge/session.dart';

void main() {
  test('各输入及已有输出分别使用所选编码', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-encodings-');
    addTearDown(() => dir.delete(recursive: true));
    final left = File('${dir.path}/left')
      ..writeAsBytesSync(TextFile.encode('café', TextEncoding.latin1));
    final right = File(
      '${dir.path}/right',
    )..writeAsBytesSync(TextFile.encode('右侧', TextEncoding.utf16be).sublist(2));
    final base = File('${dir.path}/base')..writeAsStringSync('base');
    final output = File('${dir.path}/out')
      ..writeAsBytesSync(TextFile.encode('déjà', TextEncoding.latin1));
    final session = await CompareSession.open(
      LaunchOptions(
        left: left.path,
        right: right.path,
        base: base.path,
        output: output.path,
      ),
      leftEncoding: TextEncoding.latin1,
      rightEncoding: TextEncoding.utf16be,
      outputEncoding: TextEncoding.latin1,
    );
    addTearDown(session.dispose);
    expect(session.left.text, 'café');
    expect(session.right.text, '右侧');
    expect(session.base!.text, 'base');
    expect(session.output!.text, 'déjà');
  });
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
  for (final toRight in [true, false]) {
    for (final inserted in [true, false]) {
      test(
        '防抖期间${inserted ? '插入' : '删除'}行后拒绝采用过期${toRight ? '左' : '右'}侧区块',
        () async {
          final session = CompareSession(
            TextFile.empty('head\nLEFT\ntail'),
            TextFile.empty('head\nRIGHT\ntail'),
          );
          addTearDown(session.dispose);
          await session.refresh();
          final target = toRight ? session.rightEditor : session.leftEditor;
          final edited = inserted
              ? 'new\n${target.text}'
              : target.text.substring('head\n'.length);
          target.text = edited;
          expect(session.comparisonCurrent, false);
          expect(session.busy, false);
          for (final combine in [0, 1, 2]) {
            session.applyHunk(0, toRight: toRight, combine: combine);
            expect(target.text, edited);
          }
          await session.refresh();
          expect(session.comparisonCurrent, true);
          session.applyHunk(session.diff!.changes.length - 1, toRight: toRight);
          expect(target.text, contains(toRight ? 'LEFT' : 'RIGHT'));
        },
      );
    }
  }
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
