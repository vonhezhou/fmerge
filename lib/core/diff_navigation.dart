import 'diff.dart';

/// 在有序视觉行映射中查找真实行；占位行返回 null。
int? lineAtRow(List<int> rows, int row) {
  var low = 0, high = rows.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (rows[middle] < row) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low < rows.length && rows[low] == row ? low : null;
}

class InlineTarget {
  const InlineTarget(this.side, this.line, this.start, this.end, this.row);
  final int side, line, start, end, row;
}

/// 优先使用当前侧的变化；纯插入/删除在该侧没有片段时切到另一侧。
List<InlineTarget> inlineTargets(DiffDocument diff, int preferredSide) => [
  for (final (index, row) in diff.changedRows)
    ..._rowTargets(row, index, preferredSide),
];

Iterable<InlineTarget> _rowTargets(DiffRow row, int index, int side) sync* {
  var marks = side == 0 ? row.leftMarks : row.rightMarks;
  if (marks.isEmpty) {
    side = 1 - side;
    marks = side == 0 ? row.leftMarks : row.rightMarks;
  }
  final line = side == 0 ? row.leftLine : row.rightLine;
  if (line == null) return;
  for (final mark in marks) {
    yield InlineTarget(side, line, mark.start, mark.end, index);
  }
}

/// 以当前片段的起点为锚，支持双向循环；选择范围的末端不影响导航顺序。
InlineTarget? adjacentInlineTarget(
  List<InlineTarget> targets,
  int row,
  int offset,
  int step,
) {
  if (targets.isEmpty) return null;
  var low = 0, high = targets.length;
  while (low < high) {
    final middle = (low + high) ~/ 2, target = targets[middle];
    final before =
        target.row < row ||
        target.row == row &&
            (step > 0 ? target.start <= offset : target.start < offset);
    if (before) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return step > 0
      ? targets[low % targets.length]
      : targets[(low - 1) % targets.length];
}
