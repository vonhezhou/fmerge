import 'dart:convert';
import 'dart:io';

import 'package:fmerge/core/context_rows.dart';
import 'package:fmerge/core/diff.dart';

// 独立进程测量核心比较与折叠模型；不代表编辑器渲染、滚动或完整 App 的峰值。
void main(List<String> args) {
  final count = int.parse(args.firstOrNull ?? '100000');
  final scenario = args.length > 1 ? args[1] : 'sparse';
  compare(const DiffInput('warm\nup', 'warm\nUP'));
  final leftLines = List.generate(
    count,
    (i) => 'final value_$i = "sample text for line $i";',
  );
  final rightLines = [...leftLines];
  if (scenario == 'dense') {
    for (var i = 0; i < count; i++) {
      rightLines[i] = 'changed_$i = $i;';
    }
  } else {
    for (var i = 50; i < count; i += 1000) {
      rightLines[i] = 'changed_$i = $i;';
    }
  }
  final left = leftLines.join('\n'), right = rightLines.join('\n');
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  final diff = compare(DiffInput(left, right));
  final diffMicros = watch.elapsedMicroseconds;
  watch.reset();
  final folded = ContextRows(diff.rows.length, {
    for (var i = 0; i < diff.rows.length; i++)
      if (diff.rows[i].changed) i,
  }, context: 10);
  final contextMicros = watch.elapsedMicroseconds;
  stdout.writeln(
    jsonEncode({
      'lines': count,
      'scenario': scenario,
      'inputBytes': utf8.encode(left).length + utf8.encode(right).length,
      'diffMs': diffMicros / 1000,
      'contextMs': contextMicros / 1000,
      'rssBeforeMiB': rssBefore / 1048576,
      'peakRssMiB': ProcessInfo.maxRss / 1048576,
      'changes': diff.changes.length,
      'foldedRows': folded.totalRows,
      'degraded': diff.timedOut,
    }),
  );
}
