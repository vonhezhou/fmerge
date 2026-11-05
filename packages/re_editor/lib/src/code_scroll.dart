part of re_editor;

typedef CodeScrollbarBuilder = Widget Function(BuildContext context, Widget child, ScrollableDetails details);

class CodeScrollController {

  final ScrollController verticalScroller;
  final ScrollController horizontalScroller;

  GlobalKey? _editorKey;

  CodeScrollController({
    ScrollController? verticalScroller,
    ScrollController? horizontalScroller,
  }) : verticalScroller = verticalScroller ?? ScrollController(),
    horizontalScroller = horizontalScroller ?? ScrollController();

  void makeCenterIfInvisible(CodeLinePosition position) {
    _render?.makePositionCenterIfInvisible(position);
  }

  /// 主动导航时始终将目标行居中，不受其是否已在视口内影响。
  void makeCenter(CodeLinePosition position) {
    _render?.makePositionCenterIfInvisible(position, force: true);
  }

  /// 用真实文本位置保存视口锚点，省略带会映射到相邻真实行。
  CodeLinePosition? get viewportCenter {
    final render = _render;
    if (render == null || !render.hasSize) return null;
    return render.calculateTextPosition(Offset(0, render.size.height / 2));
  }

  bool isLineVisible(int index) {
    final render = _render;
    if (render == null || !render.hasSize) return false;
    final offset = render.calculateTextPositionViewportOffset(CodeLinePosition(index: index, offset: 0));
    return offset != null && offset.dy >= 0 && offset.dy < render.size.height;
  }

  void makeVisible(CodeLinePosition position) {
    _render?.makePositionVisible(position);
  }

  void bindEditor(GlobalKey key) {
    _editorKey = key;
  }

  _CodeFieldRender? get _render => _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;

  void dispose() {
    _editorKey = null;
  }

}