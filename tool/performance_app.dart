import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:re_editor/re_editor.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!kReleaseMode) throw StateError('性能记录必须以 Release 运行');
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.show();
    final directory = await Directory.systemTemp.createTemp(
      'fmerge-performance-',
    );

    final lines = List.generate(
      100000,
      (i) => 'final value_$i = "sample text for line $i";',
    );
    final modified = [...lines];
    for (var i = 50; i < modified.length; i += 1000) {
      modified[i] = 'changed_$i = $i;';
    }
    final left = File('${directory.path}/left.dart'),
        right = File('${directory.path}/right.dart');
    await left.writeAsString(lines.join('\n'));
    await right.writeAsString(modified.join('\n'));
    final timings = <FrameTiming>[];
    void record(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(record);

    final cycles = <Map<String, Object>>[];
    Future<void> frame([
      Duration delay = const Duration(milliseconds: 16),
    ]) async {
      SchedulerBinding.instance.scheduleFrame();
      await Future<void>.delayed(delay);
    }

    final rootKey = GlobalKey();
    Future<void> ready(CompareSession session) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (session.busy || session.diff == null) {
        if (DateTime.now().isAfter(deadline)) throw StateError('比较未完成');
        await frame(const Duration(milliseconds: 20));
      }
      await frame();
    }

    double percentile(List<double> values, double p) {
      if (values.isEmpty) return 0;
      values.sort();
      return values[((values.length - 1) * p).round()];
    }

    for (var cycle = 0; cycle < 3; cycle++) {
      stdout.writeln('PERFORMANCE OPEN: $cycle');
      final watch = Stopwatch()..start();
      final session = await CompareSession.open(
        LaunchOptions(left: left.path, right: right.path),
      );
      runApp(
        KeyedSubtree(
          key: rootKey,
          child: FmergeApp(
            key: ValueKey(cycle),
            initial: session,
            settings: Settings(persist: false),
            nativeWindow: true,
          ),
        ),
      );
      await frame();
      await ready(session);
      final openMs = watch.elapsedMicroseconds / 1000,
          rssOpen = ProcessInfo.currentRss / 1048576;
      final edits = <double>[];
      session.rightEditor.selection = const CodeLineSelection.collapsed(
        index: 50000,
        offset: 0,
      );
      for (var i = 0; i < 5; i++) {
        watch.reset();
        session.rightEditor.runRevocableOp(
          () => session.rightEditor.replaceSelection('x'),
        );
        // 与界面一样读取未保存状态，统计同步编辑链路，不含后续差异计算。
        if (!session.rightDirty) throw StateError('编辑未计入未保存状态');
        edits.add(watch.elapsedMicroseconds / 1000);
        await frame(const Duration(milliseconds: 16));
      }
      watch.reset();
      await session.refresh();
      await frame();
      final editCompareMs = watch.elapsedMicroseconds / 1000;
      for (var i = 0; i < 5; i++) {
        session.rightEditor.undo();
      }
      if (session.rightDirty) throw StateError('撤销后内容未恢复');
      await session.refresh();
      await frame();
      final panes = <CodePane>[];
      void visit(Element element) {
        if (element.widget is CodePane) panes.add(element.widget as CodePane);
        element.visitChildren(visit);
      }

      (rootKey.currentContext! as Element).visitChildren(visit);
      final pane = panes.last;
      timings.clear();
      for (var i = 0; i < 120; i++) {
        final scroll = pane.scroll.verticalScroller;
        scroll.jumpTo(scroll.position.maxScrollExtent * ((i * 37) % 119) / 119);
        await frame(const Duration(milliseconds: 16));
      }
      await frame(const Duration(milliseconds: 600));
      final frames = [...timings];
      if (frames.isEmpty) throw StateError('没有采集到真实渲染帧');
      cycles.add({
        'cycle': cycle,
        'openAndFirstCompareMs': openMs,
        'rssAfterOpenMiB': rssOpen,
        'editSyncMs': edits,
        'editP50Ms': percentile(edits, .5),
        'editP95Ms': percentile(edits, .95),
        'explicitCompareAfterEditsMs': editCompareMs,
        'rssAfterScrollMiB': ProcessInfo.currentRss / 1048576,
        'frameCount': frames.length,
        'buildP95Ms': percentile(
          frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList(),
          .95,
        ),
        'rasterP95Ms': percentile(
          frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList(),
          .95,
        ),
      });
      debugPrint('PERFORMANCE CYCLE: ${jsonEncode(cycles.last)}');
    }
    runApp(const SizedBox());
    await frame(const Duration(milliseconds: 600));
    final report = {
      'mode': 'release',
      'lines': 100000,
      'platform': Platform.operatingSystem,
      'scope': 'one process; 3 document reload cycles; generated fixtures; programmatic edits and scroll; no IME or OS input latency; memory not forced-GC steady state',
      'cycles': cycles,
      'peakRssMiB': ProcessInfo.maxRss / 1048576,
      'rssAfterCloseMiB': ProcessInfo.currentRss / 1048576,
    };
    final output = File(
      '${Directory.systemTemp.path}/fmerge-performance-native.json',
    );
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('PERFORMANCE REPORT: ${output.path}');
    await directory.delete(recursive: true);
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
