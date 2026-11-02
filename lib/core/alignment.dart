import 'dart:math' as math;

import 'diff.dart';

class ThreeWayAlignment {
  const ThreeWayAlignment(
    this.baseRows,
    this.localRows,
    this.remoteRows,
    this.totalRows,
    this.changeRows,
  );
  final List<int> baseRows, localRows, remoteRows, changeRows;
  final int totalRows;
}

/// 以共同祖先的行边界为锚，把双方插入空位取并集；不把本地和远端直接互比。
ThreeWayAlignment alignThreeWay(DiffDocument local, DiffDocument remote) {
  (List<int?>, Map<int, List<int>>) side(DiffDocument diff) {
    final atBase = List<int?>.filled(diff.left.length, null),
        insertions = <int, List<int>>{};
    var boundary = 0;
    for (final row in diff.rows) {
      if (row.leftLine != null) {
        atBase[row.leftLine!] = row.rightLine;
        boundary = row.leftLine! + 1;
      } else if (row.rightLine != null) {
        (insertions[boundary] ??= []).add(row.rightLine!);
      }
    }
    return (atBase, insertions);
  }

  final l = side(local), r = side(remote);
  final baseRows = <int>[],
      leftRows = List.filled(local.right.length, 0),
      rightRows = List.filled(remote.right.length, 0);
  final changed = <int>{};
  final changedLeft = {
    for (final row in local.rows)
      if (row.changed && row.rightLine != null) row.rightLine!,
  };
  final changedRight = {
    for (final row in remote.rows)
      if (row.changed && row.rightLine != null) row.rightLine!,
  };
  var cursor = 0;
  for (var b = 0; b <= local.left.length; b++) {
    final li = l.$2[b] ?? const <int>[], ri = r.$2[b] ?? const <int>[];
    final count = math.max(li.length, ri.length);
    for (var j = 0; j < count; j++) {
      if (j < li.length) leftRows[li[j]] = cursor;
      if (j < ri.length) rightRows[ri[j]] = cursor;
      changed.add(cursor++);
    }
    if (b == local.left.length) break;
    baseRows.add(cursor);
    final ll = l.$1[b], rr = r.$1[b];
    if (ll != null) leftRows[ll] = cursor;
    if (rr != null) rightRows[rr] = cursor;
    if (ll == null ||
        rr == null ||
        changedLeft.contains(ll) ||
        changedRight.contains(rr)) {
      changed.add(cursor);
    }
    cursor++;
  }
  final hunks = <int>[];
  var previous = -2;
  for (final row in changed.toList()..sort()) {
    if (row != previous + 1) hunks.add(row);
    previous = row;
  }
  return ThreeWayAlignment(baseRows, leftRows, rightRows, cursor, hunks);
}
