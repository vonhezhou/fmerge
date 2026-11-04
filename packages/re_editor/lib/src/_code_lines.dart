part of re_editor;

class _CodeLineSegmentQuckLineCount extends CodeLineSegment {

  late int _lineCount, _charCount;

  _CodeLineSegmentQuckLineCount({
    required super.codeLines,
    required super.dirty,
    int? lineCount,
    int? charCount,
  }) {
    _lineCount = lineCount ?? super.lineCount;
    _charCount = charCount ?? super.charCount;
  }

  @override
  int get lineCount => _lineCount;

  @override
  int get charCount => _charCount;

  @override
  CodeLineSegment copyWith({List<CodeLine>? codeLines, bool? dirty}) {
    final bool same = codeLines == null || identical(codeLines, this.codeLines);
    return _CodeLineSegmentQuckLineCount(
      codeLines: codeLines ?? this.codeLines,
      dirty: dirty ?? this.dirty,
      lineCount: same ? _lineCount : null,
      charCount: same ? _charCount : null,
    );
  }

  @override
  set length(int newLength) {
    super.length = newLength;
    _lineCount = super.lineCount;
    _charCount = super.charCount;
  }

  @override
  void add(CodeLine element) {
    super.add(element);
    _lineCount += element.lineCount;
    _charCount += element.charCount;
  }

  @override
  void operator []=(int index, CodeLine value) {
    final CodeLine previous = this[index];
    super[index] = value;
    _lineCount += value.lineCount - previous.lineCount;
    _charCount += value.charCount - previous.charCount;
  }

}
