/// 将未改动区压缩成提示行；真实文档行号、文本和选择保持不变。
class ContextRows {
  ContextRows(int total, Set<int> changed, {int context = 3}) {
    final visible = List<bool>.filled(total, false);
    for (final row in changed) {
      for (
        var i = (row - context).clamp(0, total);
        i < (row + context + 1).clamp(0, total);
        i++
      ) {
        visible[i] = true;
      }
    }
    var i = 0, display = 0;
    while (i < total) {
      if (visible[i]) {
        rows.add(display++);
        i++;
      } else {
        final start = i;
        while (i < total && !visible[i]) {
          hidden.add(i++);
          rows.add(display);
        }
        labels[display++] = '⋯ 已隐藏 ${i - start} 行未改动内容 ⋯';
      }
    }
    totalRows = display;
  }
  final rows = <int>[];
  final hidden = <int>{};
  final labels = <int, String>{};
  late final int totalRows;
}
