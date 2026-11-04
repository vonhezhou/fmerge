import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'compare_task.dart';

class ComparisonCancelled implements Exception {
  const ComparisonCancelled();
}

/// 全 App 共用一个计算槽；关闭会话时终止其 isolate 并释放排队快照工厂。
class CompareWorker {
  final _queue = Queue<_Work>();
  _Work? _active;
  bool _draining = false;

  Future<CompareResult> run(Object owner, CompareTask Function() snapshot) {
    final work = _Work(owner, snapshot);
    _queue.add(work);
    if (!_draining) unawaited(_drain());
    return work.result.future;
  }

  void cancel(Object owner) {
    for (final work
        in _queue.where((w) => identical(w.owner, owner)).toList()) {
      _queue.remove(work);
      work.cancel();
    }
    if (identical(_active?.owner, owner)) _active!.cancel();
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final work = _active = _queue.removeFirst();
        await work.execute();
        _active = null;
      }
    } finally {
      _draining = false;
    }
  }
}

final compareWorker = CompareWorker();

class _Work {
  _Work(this.owner, this.snapshot);
  final Object owner;
  final CompareTask Function() snapshot;
  final result = Completer<CompareResult>();
  final _finished = Completer<void>();
  Isolate? _isolate;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    if (!result.isCompleted) result.completeError(const ComparisonCancelled());
  }

  Future<void> execute() async {
    final port = ReceivePort();
    final subscription = port.listen((message) {
      if (result.isCompleted) {
        // 取消的调用可先返回，但计算槽等真正退出通知后再交给下一个会话。
        if (message == null && !_finished.isCompleted) _finished.complete();
        return;
      }
      if (message is CompareResult) {
        result.complete(message);
      } else if (message is List && message.length == 2) {
        result.completeError(RemoteError('${message[0]}', '${message[1]}'));
      } else {
        result.completeError(StateError('比较进程未返回结果'));
      }
      if (!_finished.isCompleted) _finished.complete();
    });
    try {
      _isolate = await Isolate.spawn(
        _entry,
        (port.sendPort, snapshot()),
        onError: port.sendPort,
        onExit: port.sendPort,
        errorsAreFatal: true,
        debugName: 'fmerge.compare',
      );
      if (_cancelled) _isolate!.kill(priority: Isolate.immediate);
      await _finished.future;
    } catch (error, stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    } finally {
      _isolate?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    }
  }
}

void _entry((SendPort, CompareTask) input) {
  Isolate.exit(input.$1, runCompareTask(input.$2));
}
