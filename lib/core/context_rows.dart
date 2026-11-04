/// 将未改动区压缩成提示行；真实文档行号、文本和选择保持不变。
class ContextRows {
  ContextRows(int total, Set<int> changed, {int context = 3}) {
    if (changed.length == total &&
        changed.every((row) => row >= 0 && row < total)) {
      for (var row = 0; row < total; row++) {
        rows.add(row);
      }
      totalRows = total;
      return;
    }
    final sorted = changed.where((row) => row >= 0 && row < total).toList()
      ..sort();
    final distance = context.clamp(0, 1000);
    var cursor = 0, display = 0, rangeStart = -1, rangeEnd = -1;
    void hiddenRange(int end) {
      if (end <= cursor) return;
      final start = cursor;
      while (cursor < end) {
        hidden.add(cursor++);
        rows.add(display);
      }
      labels[display++] = '⋯ 已隐藏 ${end - start} 行未改动内容 ⋯';
    }

    void visibleRange(int start, int end) {
      hiddenRange(start);
      while (cursor < end) {
        rows.add(display++);
        cursor++;
      }
    }

    // 合并相邻的可见区间，避免“修改行数 × 上下文行数”的重复标记和整份 bool 数组。
    for (final row in sorted) {
      final start = (row - distance).clamp(0, total),
          end = (row + distance + 1).clamp(0, total);
      if (rangeStart >= 0 && start > rangeEnd) {
        visibleRange(rangeStart, rangeEnd);
        rangeStart = start;
      } else if (rangeStart < 0) {
        rangeStart = start;
      }
      if (end > rangeEnd) rangeEnd = end;
    }
    if (rangeStart >= 0) visibleRange(rangeStart, rangeEnd);
    hiddenRange(total);
    totalRows = display;
  }
  final rows = <int>[];
  final hidden = <int>{};
  final labels = <int, String>{};
  late final int totalRows;
}
