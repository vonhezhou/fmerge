import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/diff.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/session.dart';

class ControlledComparison {
  final tasks = <CompareTask>[];
  final completions = <Completer<CompareResult>>[];
  int active = 0, peakActive = 0;

  Future<CompareResult> run(CompareTask task) async {
    tasks.add(task);
    final completion = Completer<CompareResult>();
    completions.add(completion);
    active++;
    if (active > peakActive) peakActive = active;
    try {
      return await completion.future;
    } finally {
      active--;
    }
  }

  void finish(int index) =>
      completions[index].complete(runCompareTask(tasks[index]));
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('连续比较最多一个在途任务，只为最新文本与规则创建下一个快照', () async {
    final worker = ControlledComparison();
    final session = CompareSession(
      TextFile.empty('same'),
      TextFile.empty('old'),
      compareRunner: worker.run,
    );
    addTearDown(session.dispose);
    final first = session.refresh();
    final waiters = <Future<void>>[first];
    for (var i = 0; i < 50; i++) {
      session.rightEditor.text = 'intermediate $i';
      waiters.add(session.refresh());
    }
    session.rightEditor.text = '  same\t';
    waiters.add(
      session.refresh(const CompareOptions(whitespace: WhitespaceMode.edges)),
    );
    expect(worker.tasks, hasLength(1));
    expect(session.busy, true);
    worker.finish(0);
    await flush();
    expect(session.diff, isNull, reason: '过期结果不能进入编辑器');
    expect(worker.tasks, hasLength(2));
    expect(worker.tasks.last.right, '  same\t');
    expect(worker.tasks.last.options.whitespace, WhitespaceMode.edges);
    expect(worker.tasks.last.leftOriginal, isNull);
    expect(session.busy, true);
    worker.finish(1);
    await Future.wait(waiters);
    expect(worker.peakActive, 1);
    expect(session.diff!.right, ['  same\t']);
    expect(session.diff!.changes, isEmpty);
    expect(session.busy, false);
    expect(session.error, isNull);
  });

  testWidgets('编辑立即使结果过期，防抖后只比较最新内容', (tester) async {
    final worker = ControlledComparison();
    final session = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
      compareRunner: worker.run,
    );
    addTearDown(session.dispose);
    final first = session.refresh();
    session.rightEditor.text = 'latest';
    worker.finish(0);
    await tester.pump();
    await first;
    expect(session.diff, isNull);
    await tester.pump(const Duration(milliseconds: 139));
    expect(worker.tasks, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(worker.tasks, hasLength(2));
    expect(worker.tasks.last.right, 'latest');
    worker.finish(1);
    await tester.pump();
    expect(session.diff!.right, ['latest']);
    expect(worker.peakActive, 1);
  });

  testWidgets('待处理请求读取最新编辑后取消冗余防抖，不重复比较', (tester) async {
    final worker = ControlledComparison();
    final session = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
      compareRunner: worker.run,
    );
    addTearDown(session.dispose);
    final first = session.refresh();
    final queued = session.refresh();
    session.rightEditor.text = 'latest edit';
    worker.finish(0);
    await tester.pump();
    expect(worker.tasks, hasLength(2));
    expect(worker.tasks.last.right, 'latest edit');
    worker.finish(1);
    await tester.pump();
    await Future.wait([first, queued]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(worker.tasks, hasLength(2));
    expect(session.busy, false);
    expect(session.diff!.right, ['latest edit']);
  });

  test('三方比较在同一任务返回双侧差异，并保留祖先对齐和冲突状态', () async {
    final session = CompareSession(
      TextFile.empty('local\nkeep\n'),
      TextFile.empty('remote\nkeep\n'),
      base: TextFile.empty('base\nkeep\n'),
    );
    addTearDown(session.dispose);
    await session.refresh();
    expect(session.diff!.left.first, 'local');
    expect(session.diff!.right.first, 'remote');
    expect(session.mergeAlignment!.baseRows, [0, 1, 2]);
    expect(session.leftEditor.diffLayout!.lineRows, [0, 1, 2]);
    expect(session.rightEditor.diffLayout!.lineRows, [0, 1, 2]);
    expect(session.pending, 1);
  });

  test('过期任务失败不覆盖新请求，当前失败可再次恢复', () async {
    final worker = ControlledComparison();
    final session = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
      compareRunner: worker.run,
    );
    addTearDown(session.dispose);
    final first = session.refresh();
    final latest = session.refresh();
    worker.completions[0].completeError(StateError('obsolete'));
    await flush();
    expect(worker.tasks, hasLength(2));
    expect(session.error, isNull);
    expect(session.busy, true);
    worker.completions[1].completeError(StateError('current failure'));
    await Future.wait([first, latest]);
    expect(session.error, contains('current failure'));
    expect(session.busy, false);
    final retry = session.refresh();
    worker.finish(2);
    await retry;
    expect(session.error, isNull);
    expect(session.diff, isNotNull);
  });

  test('关闭会话丢弃待处理请求，不通知已销毁的编辑器', () async {
    final worker = ControlledComparison();
    final session = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
      compareRunner: worker.run,
    );
    final first = session.refresh();
    final queued = session.refresh();
    var notified = 0;
    session.addListener(() => notified++);
    session.dispose();
    worker.finish(0);
    await Future.wait([first, queued]);
    expect(worker.tasks, hasLength(1));
    expect(session.diff, isNull);
    expect(notified, 0);
    await session.refresh();
    expect(worker.tasks, hasLength(1));
  });

  test('精确换行快照在后台重建，修改行使用主导风格，保留未改动混合换行', () async {
    const original = 'one\r\ntwo\nthree\rfour\r\n';
    const edited = 'ONE\ntwo\nthree\nfour\n';
    const reconstructed = 'ONE\r\ntwo\nthree\rfour\r\n';
    final session = CompareSession(
      TextFile.empty(original),
      TextFile.empty(reconstructed),
    );
    addTearDown(session.dispose);
    session.leftEditor.text = edited;
    await session.refresh(const CompareOptions(ignoreEol: false));
    expect(session.diff!.changes, isEmpty);
    expect(session.left.original, original);
    expect(session.leftEditor.text, edited);
    expect(session.leftDirty, true);
  });
}
