part of re_editor;

/// 只改变显示布局，不改变文档、选择、输入法或撤销模型。禁止与语法代码折叠混用。
@immutable
class CodeDiffLayout {
  final List<int> lineRows;
  /// 折叠后的真实可见行索引，按升序排列；提供时渲染只遍历这些行。
  final List<int>? visibleLines;
  final int totalRows;
  final Set<int> hiddenLines;
  final Map<int, String> rowLabels;
  final Map<int, Color> rowColors;
  final bool showWhitespace;
  final Map<int, List<CodeDiffRange>> ranges;
  /// 两侧共享每个对齐行的换行高度；不换行时忽略。
  final CodeDiffWrap? wrap;
  const CodeDiffLayout({required this.lineRows, required this.totalRows,
    this.visibleLines, this.hiddenLines = const {}, this.rowLabels = const {}, this.rowColors = const {}, this.ranges = const {}, this.showWhitespace = false, this.wrap});
}

/// 收集各栏实际段落高度，以较高一侧为准；帧结束后通知另一栏重新布局。
class CodeDiffWrap extends ChangeNotifier {
  final _heights = <Object, List<int>>{};
  List<int> _offsets = const [0];
  bool _scheduled = false;
  int get totalRows => _offsets.last;
  int rowStart(int row) => row < _offsets.length ? _offsets[row] : row;
  int rowHeight(int row) => rowStart(row + 1) - rowStart(row);
  void update(Object owner, List<int> heights) {
    if (identical(_heights[owner], heights)) return;
    _heights[owner] = heights;
    _rebuild();
  }
  void remove(Object owner) {
    if (_heights.remove(owner) != null) _rebuild();
  }
  void _rebuild() {
    final count = _heights.values.fold<int>(0, (n, h) => max(n, h.length));
    final offsets = List<int>.filled(count + 1, 0);
    for (var i = 0; i < count; i++) {
      var height = 1;
      for (final heights in _heights.values) {
        if (i < heights.length) height = max(height, heights[i]);
      }
      offsets[i + 1] = offsets[i] + height;
    }
    if (listEquals(offsets, _offsets)) return;
    _offsets = offsets;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

@immutable
class CodeDiffRange {
  final int start, end;
  final Color color;
  const CodeDiffRange(this.start, this.end, this.color);
}
