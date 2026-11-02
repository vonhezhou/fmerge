part of re_editor;

/// 只改变显示布局，不改变文档、选择、输入法或撤销模型。禁止与自动换行/语法代码折叠混用。
@immutable
class CodeDiffLayout {
  final List<int> lineRows;
  final int totalRows;
  final Set<int> hiddenLines;
  final Map<int, String> rowLabels;
  final Map<int, Color> rowColors;
  final bool showWhitespace;
  final Map<int, List<CodeDiffRange>> ranges;
  const CodeDiffLayout({required this.lineRows, required this.totalRows,
    this.hiddenLines = const {}, this.rowLabels = const {}, this.rowColors = const {}, this.ranges = const {}, this.showWhitespace = false});
}

@immutable
class CodeDiffRange {
  final int start, end;
  final Color color;
  const CodeDiffRange(this.start, this.end, this.color);
}
