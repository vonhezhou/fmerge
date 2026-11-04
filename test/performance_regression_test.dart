import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/compare_worker.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/line_diff.dart';
import 'package:re_editor/re_editor.dart';

CompareTask task(String left, String right) =>
    CompareTask(left: left, right: right, options: const CompareOptions());

void main() {
  test('全局计算槽延迟创建其他会话快照，取消当前任务后继续最新会话', () async {
    final worker = CompareWorker(),
        firstOwner = Object(),
        secondOwner = Object();
    final first = worker.run(firstOwner, () => task('a', 'b'));
    final cancelled = expectLater(first, throwsA(isA<ComparisonCancelled>()));
    var captured = false;
    final second = worker.run(secondOwner, () {
      captured = true;
      return task('latest', 'latest');
    });
    expect(captured, false);
    worker.cancel(firstOwner);
    await cancelled;
    final result = await second;
    expect(captured, true);
    expect(result.diff.changes, isEmpty);
  });
  test('取消排队会话不读取已销毁的编辑器，其他任务和失败重试继续执行', () async {
    final worker = CompareWorker(), owner = Object();
    final first = worker.run(Object(), () => task('first', 'first'));
    final queued = worker.run(owner, () => throw StateError('不应读取快照'));
    final cancellation = expectLater(
      queued,
      throwsA(isA<ComparisonCancelled>()),
    );
    worker.cancel(owner);
    await cancellation;
    await first;
    await expectLater(
      worker.run(Object(), () => throw StateError('capture failure')),
      throwsStateError,
    );
    expect(
      (await worker.run(Object(), () => task('last', 'last'))).diff.changes,
      isEmpty,
    );
  });
  test('大面积重写、交叉锚点和重复行均能精确重建，不把重复行当作唯一锚点', () {
    final random = Random(8192);
    for (var trial = 0; trial < 8; trial++) {
      final a = List.generate(
        5000,
        (i) => trial.isEven ? 'old $i' : 'repeat ${i % 40}',
      );
      final b = List.generate(5100, (i) => 'new $i');
      for (var i = 70; i < 4900; i += 137) {
        b[i] = a[random.nextInt(a.length)];
      }
      final result = lineDiff(a, b);
      final rebuilt = <String>[];
      var ai = 0, bi = 0;
      for (final c in result.changes) {
        expect(a.sublist(ai, c.aStart), b.sublist(bi, c.bStart));
        rebuilt.addAll(a.sublist(ai, c.aStart));
        rebuilt.addAll(b.sublist(c.bStart, c.bEnd));
        ai = c.aEnd;
        bi = c.bEnd;
      }
      expect(a.sublist(ai), b.sublist(bi));
      rebuilt.addAll(a.sublist(ai));
      expect(rebuilt, b);
    }
  });
  test('紧凑行模型完整保留插入删除、原始行号、高亮与末尾空行', () {
    final a = List.generate(10000, (i) => 'line $i')..add('');
    final b = [...a]
      ..removeRange(500, 510)
      ..insertAll(800, ['new A', 'new B']);
    final result = compare(DiffInput(a.join('\n'), b.join('\n')));
    expect(result.rows.where((r) => r.leftLine != null).map((r) => r.left), a);
    expect(
      result.rows.where((r) => r.rightLine != null).map((r) => r.right),
      b,
    );
    for (final row in result.rows) {
      if (row.leftLine != null) expect(row.left, a[row.leftLine!]);
      if (row.rightLine != null) expect(row.right, b[row.rightLine!]);
    }
    expect(result.rows.where((r) => r.changed), isNotEmpty);
    expect(result.rows.last.left, '');
    expect(result.rows.last.right, '');
  });
  test('大段重写保留整行差异与可采用内容，避免逐行消耗细化预算', () {
    final a = List.generate(6000, (i) => 'old $i'),
        b = List.generate(6000, (i) => 'new $i');
    final result = compare(DiffInput(a.join('\n'), b.join('\n')));
    expect(result.changes, hasLength(1));
    expect(result.rows.first.leftMarks.single.end, a.first.length);
    expect(result.rows.last.rightMarks.single.end, b.last.length);
    expect(result.left, a);
    expect(result.right, b);
  });
  test('撤销历史按条目截断，截断边界支持重做与分支编辑', () {
    final controller = CodeLineEditingController.fromText(
      'initial',
      const CodeLineOptions(historyLimit: 5),
    );
    addTearDown(controller.dispose);
    for (var i = 0; i < 12; i++) {
      controller.runRevocableOp(() => controller.text = 'edit $i');
    }
    var undos = 0;
    while (controller.canUndo) {
      controller.undo();
      undos++;
    }
    expect(undos, 4);
    expect(controller.text, 'edit 7');
    controller.redo();
    expect(controller.text, 'edit 8');
    controller.runRevocableOp(() => controller.text = 'branch');
    expect(controller.canRedo, false);
    controller.undo();
    expect(controller.text, 'edit 8');
  });
  test('撤销历史字符预算保留一次撤销，清理历史不改变正文', () {
    final controller = CodeLineEditingController.fromText(
      '0000000000',
      const CodeLineOptions(historyCharacterLimit: 25),
    );
    addTearDown(controller.dispose);
    for (var i = 1; i <= 5; i++) {
      controller.runRevocableOp(() => controller.text = '$i' * 10);
    }
    controller.undo();
    expect(controller.text, '4444444444');
    expect(controller.canUndo, false);
    controller.redo();
    expect(controller.text, '5555555555');
    controller.clearHistory();
    expect(controller.canUndo, false);
    expect(controller.canRedo, false);
    expect(controller.text, '5555555555');
  });
}
