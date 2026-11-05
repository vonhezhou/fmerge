import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class OperationCancelled implements Exception {
  const OperationCancelled({this.timedOut = false});
  final bool timedOut;
  @override
  String toString() => timedOut ? '操作超时，已停止；请刷新确认结果' : '操作已取消；请刷新确认结果';
}

/// 一个用户操作共用截止时间；取消时结束子进程，并停止等待其输出管道。
class ProcessOperation {
  ProcessOperation({Duration timeout = const Duration(seconds: 30)}) {
    _timer = Timer(timeout, () => cancel(timedOut: true));
  }
  Timer? _timer;
  final _stopped = Completer<void>();
  bool _timedOut = false;
  Process? _process;
  bool _starting = false;
  bool get cancelled => _stopped.isCompleted;
  void check() {
    if (cancelled) throw OperationCancelled(timedOut: _timedOut);
  }

  void cancel({bool timedOut = false}) {
    if (cancelled) return;
    _timedOut = timedOut;
    _timer?.cancel();
    _stopped.complete();
    _process?.kill(ProcessSignal.sigkill);
  }

  Future<T> wait<T>(Future<T> future) async {
    check();
    final result = await Future.any<T>([
      future,
      _stopped.future.then<T>(
        (_) => throw OperationCancelled(timedOut: _timedOut),
      ),
    ]);
    check();
    return result;
  }

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? input,
  }) async {
    check();
    if (_process != null || _starting) throw StateError('同一操作不能并行启动子进程');
    _starting = true;
    late final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
      );
    } finally {
      _starting = false;
    }
    _process = process;
    final output = BytesBuilder(copy: false), error = BytesBuilder(copy: false);
    var streams = 0;
    int? code;
    final done = Completer<void>();
    unawaited(done.future.catchError((Object _) {}));
    void finish() {
      if (streams == 2 && code != null && !done.isCompleted) done.complete();
    }

    void streamError(Object e, StackTrace stack) {
      if (!done.isCompleted) done.completeError(e, stack);
    }

    final stdout = process.stdout.listen(
      output.add,
      onDone: () {
        streams++;
        finish();
      },
      onError: streamError,
    );
    final stderr = process.stderr.listen(
      error.add,
      onDone: () {
        streams++;
        finish();
      },
      onError: streamError,
    );
    unawaited(
      process.exitCode.then((value) {
        code = value;
        finish();
      }),
    );
    try {
      check();
      if (input != null) process.stdin.add(input);
      // 某些过滤器不读取 stdin；关闭管道也必须响应取消和超时。
      await wait(process.stdin.close());
      await wait(done.future);
      return ProcessResult(
        process.pid,
        code!,
        output.takeBytes(),
        error.takeBytes(),
      );
    } finally {
      if (code == null) process.kill(ProcessSignal.sigkill);
      await stdout.cancel();
      await stderr.cancel();
      await process.exitCode;
      _process = null;
    }
  }

  void dispose() {
    cancel();
  }
}
