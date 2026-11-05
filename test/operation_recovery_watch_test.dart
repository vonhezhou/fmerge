import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fmerge/core/file_watch.dart';
import 'package:fmerge/core/process_operation.dart';
import 'package:fmerge/core/recovery.dart';

Future<String> sdkDart() async {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  var folder = File(Platform.resolvedExecutable).parent;
  while (true) {
    final file = File(p.join(folder.path, 'dart-sdk', 'bin', name));
    if (await file.exists()) return file.path;
    if (folder.path == folder.parent.path) {
      throw StateError('未找到测试使用的 Dart SDK');
    }
    folder = folder.parent;
  }
}

void main() {
  testWidgets('连续输入仍按最长间隔保存，重置取消旧快照', (tester) async {
    var saves = 0;
    final scheduler = RecoveryScheduler(
      save: () async {
        saves++;
      },
      onError: (e) => fail('$e'),
    );
    addTearDown(scheduler.dispose);
    for (var i = 0; i < 12; i++) {
      scheduler.schedule();
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(saves, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(saves, 2);
    scheduler.schedule();
    scheduler.reset();
    await tester.pump(const Duration(seconds: 6));
    expect(saves, 2);
  });

  testWidgets('慢写期间只合并一次最新保存请求，不并发写入', (tester) async {
    final first = Completer<void>();
    var saves = 0, active = 0, maximum = 0;
    final scheduler = RecoveryScheduler(
      save: () async {
        saves++;
        active++;
        if (active > maximum) maximum = active;
        if (saves == 1) await first.future;
        active--;
      },
      onError: (e) => fail('$e'),
    );
    addTearDown(scheduler.dispose);
    scheduler.schedule();
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 10; i++) {
      scheduler.schedule();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(saves, 1);
    first.complete();
    await tester.pump();
    expect(saves, 2);
    expect(maximum, 1);
  });

  test('另一个进程持锁时不能恢复或删除，退出后记录重新可见', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-lock-');
    final store = RecoveryStore(dir.path);
    Process? child;
    addTearDown(() async {
      child?.kill(ProcessSignal.sigkill);
      if (child != null) await child.exitCode;
      await store.close();
      await dir.delete(recursive: true);
    });
    await store.save({
      'left': <String, dynamic>{},
      'right': <String, dynamic>{},
      'leftText': 'a',
      'rightText': 'b',
    });
    await store.close();
    final script = File('${dir.path}/lock.dart');
    await script.writeAsString(
      "import 'dart:io'; Future<void> main(List<String> args) async { final f=await File(args[0]).open(mode:FileMode.append); await f.lock(FileLock.exclusive); stdout.writeln('locked'); await stdin.first; }",
    );
    child = await Process.start(await sdkDart(), [
      script.path,
      p.join(store.folder, '${store.id}.lock'),
    ]);
    expect(
      await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10)),
      'locked',
    );
    expect(await store.list(), isEmpty);
    await expectLater(store.remove(), throwsStateError);
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    expect((await store.list()).single.id, store.id);
  });

  test('取消和超时结束真实子进程，允许后续操作', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-operation-');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/wait.dart');
    await script.writeAsString(
      "import 'dart:io'; Future<void> main(List<String> args) async { File(args[0]).writeAsStringSync('ready'); await Future<void>.delayed(const Duration(seconds:30)); }",
    );
    final dart = await sdkDart();
    final ready = File('${dir.path}/ready');
    final operation = ProcessOperation();
    addTearDown(operation.dispose);
    final task = operation.run(dart, [script.path, ready.path]);
    final cancelled = expectLater(
      task,
      throwsA(
        isA<OperationCancelled>().having((e) => e.timedOut, 'timedOut', false),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await ready.exists()) {
      if (DateTime.now().isAfter(deadline)) fail('子进程未启动');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    operation.cancel();
    await cancelled;
    final timed = ProcessOperation(timeout: const Duration(milliseconds: 200));
    addTearDown(timed.dispose);
    await expectLater(
      timed.run(dart, [script.path, ready.path]),
      throwsA(
        isA<OperationCancelled>().having((e) => e.timedOut, 'timedOut', true),
      ),
    );
    final next = ProcessOperation();
    addTearDown(next.dispose);
    expect((await next.run(dart, ['--version'])).exitCode, 0);
  });

  test('目录监听捕获原子替换、删除重建，切换文件后忽略旧事件', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-watch-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/file');
    await file.writeAsString('old');
    var events = 0;
    final watcher = FileWatchMonitor(
      () => events++,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(watcher.dispose);
    await watcher.update([file.path]);
    Future<void> eventAfter(Future<void> Function() mutation) async {
      final before = events;
      await mutation();
      final limit = DateTime.now().add(const Duration(seconds: 5));
      while (events == before) {
        if (DateTime.now().isAfter(limit)) fail('未收到文件事件');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await eventAfter(() async {
      final temp = File('${dir.path}/temp');
      await temp.writeAsString('new');
      await temp.rename(file.path);
    });
    await eventAfter(() async {
      await file.delete();
      await file.writeAsString('recreated');
    });
    await watcher.update([]);
    final before = events;
    await file.writeAsString('ignored');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events, before);
  });
}
