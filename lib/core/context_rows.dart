import 'dart:collection';
import 'dart:typed_data';

/// 将未改动区压缩成提示行；真实文档行号、文本和选择保持不变。
class ContextRows {
  ContextRows(int total, Set<int> changed, {int context = 3})
    : rows = Int32List(total) {
    if (changed.length == total &&
        changed.every((row) => row >= 0 && row < total)) {
      for (var row = 0; row < total; row++) {
        rows[row] = row;
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
        rows[cursor++] = display;
      }
      (hidden as _HiddenRanges).append(start, end);
      labels[display++] = '⋯ 已隐藏 ${end - start} 行未改动内容 ⋯';
    }

    void visibleRange(int start, int end) {
      hiddenRange(start);
      while (cursor < end) {
        rows[cursor++] = display++;
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
  final List<int> rows;
  final Set<int> hidden = _HiddenRanges();
  final labels = <int, String>{};
  late final int totalRows;
}

/// 隐藏行连续成段，按区间保存，避免为几十万行逐个创建哈希表条目。
class _HiddenRanges extends SetBase<int> {
  final _ranges = <(int, int)>[];
  int _length = 0;
  void append(int start, int end) {
    _ranges.add((start, end));
    _length += end - start;
  }

  @override
  bool contains(Object? value) {
    if (value is! int) return false;
    var low = 0, high = _ranges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2, range = _ranges[middle];
      if (value < range.$1) {
        high = middle;
      } else if (value >= range.$2) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  @override
  int? lookup(Object? value) => contains(value) ? value as int : null;
  @override
  Iterator<int> get iterator => _values().iterator;
  Iterable<int> _values() sync* {
    for (final range in _ranges) {
      for (var i = range.$1; i < range.$2; i++) {
        yield i;
      }
    }
  }

  @override
  int get length => _length;
  @override
  bool add(int value) => throw UnsupportedError('只读隐藏区间');
  @override
  bool remove(Object? value) => throw UnsupportedError('只读隐藏区间');
  @override
  Set<int> toSet() => {...this};
}
