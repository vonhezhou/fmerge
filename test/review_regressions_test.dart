import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/merge.dart';
import 'package:fmerge/core/merge_session.dart';
import 'package:fmerge/core/editor_changes.dart';
import 'package:fmerge/core/disk_check.dart';
import 'package:fmerge/core/recovery.dart';
import 'package:fmerge/session.dart';

void main() {
  test('空冲突处手工插入形成有效范围，重新采用只替换该范围', () {
    final s = MergeSession(planMerge('a\nc', 'a\nL\nc', 'a\nR\nc'));
    expect(s.state.regions.single.start, s.state.regions.single.end);
    s.edit('a\nmanual\nc');
    expect(s.state.regions.single.start, 1);
    expect(s.state.regions.single.end, 2);
    s.choose(s.state.regions.single.chunk.id, MergeChoice.left);
    expect(s.state.text, 'a\nL\nc');
  });
  test('冲突后的替换、插入及冲突前的插入不被重新采用吞掉', () {
    for (final edited in [
      'a\nb\nMANUAL\nd',
      'a\nb\ninserted\nc\nd',
      'a\ninserted\nb\nc\nd',
    ]) {
      final s = MergeSession(
        planMerge('a\nb\nc\nd', 'a\nL\nc\nd', 'a\nR\nc\nd'),
      );
      s.edit(edited);
      s.choose(s.state.regions.single.chunk.id, MergeChoice.left);
      expect(s.state.text, edited.replaceFirst('b', 'L'));
      s.choose(s.state.regions.single.chunk.id, MergeChoice.right);
      expect(s.state.text, edited.replaceFirst('b', 'R'));
      s.undo();
      expect(s.state.text, edited.replaceFirst('b', 'L'));
    }
  });

  test('分段结果编辑保留多个冲突以外的修改，不将全文作为一个替换块', () {
    final source = List.generate(2000, (i) => 'line $i');
    final l = [...source]..[600] = 'left';
    final r = [...source]..[600] = 'right';
    final s = CompareSession(
      TextFile.empty(l.join('\n')),
      TextFile.empty(r.join('\n')),
      base: TextFile.empty(source.join('\n')),
    );
    addTearDown(s.dispose);
    final editor = s.resultEditor!;
    final before = editor.codeLines;
    editor.selection = const CodeLineSelection.collapsed(index: 601, offset: 0);
    editor.runRevocableOp(() => editor.replaceSelection('manual '));
    final changes = editorChanges(before, editor.codeLines);
    expect(changes.single.aStart, 601);
    expect(changes.single.aEnd, 602);
    s.choose(s.merger!.state.regions.single.chunk.id, MergeChoice.left);
    expect(editor.codeLines[601].text, 'manual line 601');
    expect(editor.codeLines[600].text, 'left');
  });

  test('恢复保留未保存文本、冲突状态、编码、原文件校验基线，实例互不覆盖', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/out');
    await file.writeAsString('original');
    final s = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
      base: TextFile.empty('base'),
      output: await TextFile.read(file.path),
    );
    addTearDown(s.dispose);
    s.choose(s.merger!.state.regions.single.chunk.id, MergeChoice.left);
    s.resultEditor!.text = '手工结果';
    s.setSaveEncoding(2, TextEncoding.utf8Bom);
    final store = RecoveryStore(dir.path), other = RecoveryStore(dir.path);
    await store.save(s.recoverySnapshot());
    await other.save(s.recoverySnapshot());
    expect(await store.list(), isEmpty);
    await expectLater(store.remove(other.id), throwsStateError);
    await store.close();
    await other.close();
    expect(await store.list(), hasLength(2));
    final data = (await store.list()).firstWhere((r) => r.id == store.id).data;
    final restored = await CompareSession.recover(data);
    addTearDown(restored.dispose);
    expect(restored.resultEditor!.text, '手工结果');
    expect(restored.pending, 0);
    expect(restored.resultDirty, true);
    expect(restored.saveEncodings[2], TextEncoding.utf8Bom);
    await file.writeAsString('external');
    await expectLater(
      restored.saveResult(backup: false),
      throwsA(isA<FileConflict>()),
    );
    expect(await file.readAsString(), 'external');
    await store.remove();
    expect((await other.list()).single.id, other.id);
    await expectLater(store.remove('../outside'), throwsFormatException);
  });

  test('焦点磁盘检查包含同大小改动并合并正在运行的检查', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-disk-check-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/text');
    await file.writeAsString('old');
    final baseline = await TextFile.read(file.path);
    final check = DiskCheck();
    final first = check.changed([(file.path, baseline.digest!)]);
    expect(
      identical(first, check.changed([(file.path, baseline.digest!)])),
      true,
    );
    expect(await first, false);
    await file.writeAsString('new');
    expect(await check.changed([(file.path, baseline.digest!)]), true);
  });
}
