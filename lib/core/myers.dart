// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See THIRD_PARTY_NOTICES.md.
// Dart adaptation of VS Code MyersDiffAlgorithm at b7d40a42d807a505b4bb6b73058c09340c9dfac0.
import 'dart:math' as math;

class SequenceChange {
  const SequenceChange(this.aStart, this.aEnd, this.bStart, this.bEnd);
  final int aStart, aEnd, bStart, bEnd;
}

class SequenceResult {
  const SequenceResult(this.changes, {this.timedOut = false});
  final List<SequenceChange> changes;
  final bool timedOut;
}

class _Snake {
  const _Snake(this.previous, this.x, this.y, this.length);
  final _Snake? previous;
  final int x, y, length;
}

/// 保留上游的最远对角线与匹配路径算法；使用 Dart Map 代替负索引数组。
SequenceResult myers<T>(
  List<T> a,
  List<T> b, {
  Duration budget = const Duration(milliseconds: 250),
}) {
  final watch = Stopwatch()..start();
  // 先裁掉相同首尾，降低局部修改与超时降级时的影响范围。
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var aEnd = a.length, bEnd = b.length;
  while (aEnd > prefix && bEnd > prefix && a[aEnd - 1] == b[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }
  final n = aEnd - prefix, m = bEnd - prefix;
  if (n == 0 && m == 0) return const SequenceResult([]);
  if (n == 0 || m == 0) {
    return SequenceResult([SequenceChange(prefix, aEnd, prefix, bEnd)]);
  }
  SequenceResult fallback() => SequenceResult([
    SequenceChange(prefix, aEnd, prefix, bEnd),
  ], timedOut: true);
  if (budget == Duration.zero) return fallback();
  int snake(int x, int y) {
    while (x < n && y < m && a[prefix + x] == b[prefix + y]) {
      x++;
      y++;
    }
    return x;
  }

  final v = <int, int>{0: snake(0, 0)};
  final paths = <int, _Snake?>{0: null};
  if (v[0]! > 0) paths[0] = _Snake(null, 0, 0, v[0]!);
  var k = 0;
  search:
  for (var d = 1; ; d++) {
    if (watch.elapsed >= budget) return fallback();
    final lower = -math.min(d, m + d % 2);
    final upper = math.min(d, n + d % 2);
    for (k = lower; k <= upper; k += 2) {
      // 内层也设截止点，避免高差异输入阻塞整个编辑流程。
      if ((k & 255) == 0 && watch.elapsed >= budget) return fallback();
      final top = k == upper ? -1 : (v[k + 1] ?? 0);
      final left = k == lower ? -1 : (v[k - 1] ?? 0) + 1;
      final x = math.min(math.max(top, left), n);
      final y = x - k;
      if (x > n || y > m || y < 0) continue;
      final next = snake(x, y);
      v[k] = next;
      final previous = x == top ? paths[k + 1] : paths[k - 1];
      paths[k] = next != x ? _Snake(previous, x, y, next - x) : previous;
      if (next == n && next - k == m) break search;
    }
  }
  var path = paths[k];
  var lastX = n, lastY = m;
  final result = <SequenceChange>[];
  while (true) {
    final x = path == null ? 0 : path.x + path.length;
    final y = path == null ? 0 : path.y + path.length;
    if (x != lastX || y != lastY) {
      result.add(
        SequenceChange(prefix + x, prefix + lastX, prefix + y, prefix + lastY),
      );
    }
    if (path == null) break;
    lastX = path.x;
    lastY = path.y;
    path = path.previous;
  }
  return SequenceResult(result.reversed.toList());
}
