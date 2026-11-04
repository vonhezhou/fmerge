import 'dart:typed_data';

import 'myers.dart';

/// 常规局部修改沿用 Myers；大面积重写用唯一文本锚点拆分。
/// 锚点用原始键精确匹配，不以行哈希相同替代文本相同。
SequenceResult lineDiff(List<String> a, List<String> b) {
  if (a.length < 4096 || b.length < 4096) return myers(a, b);
  var prefix = 0, aEnd = a.length, bEnd = b.length;
  while (prefix < aEnd && prefix < bEnd && a[prefix] == b[prefix]) {
    prefix++;
  }
  while (aEnd > prefix && bEnd > prefix && a[aEnd - 1] == b[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }
  final n = aEnd - prefix, m = bEnd - prefix;
  if (n < 4096 || m < 4096) return myers(a, b);
  // 抽样只选择算法，不决定两行是否相同；稀疏修改避免建立锚点表。
  for (var i = 0; i < 32; i++) {
    if (a[prefix + i * (n - 1) ~/ 31] == b[prefix + i * (m - 1) ~/ 31]) {
      return myers(a, b);
    }
  }
  final watch = Stopwatch()..start();
  final positions = <String, int>{};
  for (var i = prefix; i < aEnd; i++) {
    positions.update(a[i], (_) => -1, ifAbsent: () => i);
  }
  final matches = <String, int>{};
  var anyCommon = false;
  for (var i = prefix; i < bEnd; i++) {
    final position = positions[b[i]];
    if (position == null) continue;
    anyCommon = true;
    if (position >= 0) matches.update(b[i], (_) => -1, ifAbsent: () => i);
  }
  if (!anyCommon) {
    return SequenceResult([SequenceChange(prefix, aEnd, prefix, bEnd)]);
  }
  final candidates = <(int, int)>[
    for (final entry in positions.entries)
      if (entry.value >= 0 && (matches[entry.key] ?? -1) >= 0)
        (entry.value, matches[entry.key]!),
  ];
  if (candidates.isEmpty) return myers(a, b);
  final tails = <int>[];
  final previous = Int32List(candidates.length)
    ..fillRange(0, candidates.length, -1);
  for (var i = 0; i < candidates.length; i++) {
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (candidates[tails[mid]].$2 < candidates[i].$2) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) previous[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final anchors = <(int, int)>[];
  for (var index = tails.last; index >= 0; index = previous[index]) {
    anchors.add(candidates[index]);
  }
  final changes = <SequenceChange>[];
  var ai = prefix, bi = prefix, timedOut = false;
  void gap(int ae, int be) {
    final remaining = const Duration(milliseconds: 250) - watch.elapsed;
    final result = myers(
      a.sublist(ai, ae),
      b.sublist(bi, be),
      budget: remaining.isNegative ? Duration.zero : remaining,
    );
    timedOut |= result.timedOut;
    for (final c in result.changes) {
      changes.add(
        SequenceChange(ai + c.aStart, ai + c.aEnd, bi + c.bStart, bi + c.bEnd),
      );
    }
  }

  for (final anchor in anchors.reversed) {
    gap(anchor.$1, anchor.$2);
    ai = anchor.$1 + 1;
    bi = anchor.$2 + 1;
  }
  gap(aEnd, bEnd);
  return SequenceResult(changes, timedOut: timedOut);
}
