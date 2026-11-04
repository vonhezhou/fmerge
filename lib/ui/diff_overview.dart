import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../palette.dart';

/// 两条色带分别表示左右输入；视口覆盖层随同步滚动更新。
class DiffOverview extends StatelessWidget {
  const DiffOverview({
    super.key,
    required this.left,
    required this.right,
    required this.scroll,
    required this.onSeek,
    this.wordWrap = false,
  });
  final CodeDiffLayout? left, right;
  final ScrollController scroll;
  final ValueChanged<double>? onSeek;
  final bool wordWrap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    child: LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset position) =>
            onSeek?.call((position.dy / constraints.maxHeight).clamp(0, 1));
        return Semantics(
          label: '全文差异概览，点击或拖动定位',
          child: Tooltip(
            message: '全文差异概览 · 点击或拖动定位',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
              onVerticalDragStart: onSeek == null
                  ? null
                  : (d) => seek(d.localPosition),
              onVerticalDragUpdate: onSeek == null
                  ? null
                  : (d) => seek(d.localPosition),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _OverviewPainter(left, right, wordWrap),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: scroll,
                    builder: (_, _) {
                      final position =
                          scroll.positions.length == 1 &&
                              scroll.position.hasContentDimensions &&
                              scroll.position.hasViewportDimension
                          ? scroll.position
                          : null;
                      final extent = position == null
                          ? 0.0
                          : position.maxScrollExtent +
                                position.viewportDimension;
                      return CustomPaint(
                        size: Size(22, constraints.maxHeight),
                        painter: _ViewportPainter(
                          extent == 0 ? 0 : position!.pixels / extent,
                          extent == 0
                              ? 1
                              : position!.viewportDimension / extent,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _OverviewPainter extends CustomPainter {
  _OverviewPainter(this.left, this.right, this.wordWrap)
    : super(repaint: wordWrap ? left?.wrap : null);
  final CodeDiffLayout? left, right;
  final bool wordWrap;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    void lane(CodeDiffLayout? layout, double x, Color color) {
      if (layout == null || layout.totalRows == 0) return;
      final wrap = wordWrap ? layout.wrap : null;
      final total = wrap != null && wrap.totalRows > 0
          ? wrap.totalRows
          : layout.totalRows;
      for (final entry in layout.rowColors.entries) {
        if (entry.value == bg) continue;
        final top =
            (wrap?.rowStart(entry.key) ?? entry.key) / total * size.height;
        final height = math.max(
          2.0,
          (wrap?.rowHeight(entry.key) ?? 1) * size.height / total,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            top.clamp(0, math.max(0, size.height - height)),
            7,
            height,
          ),
          Paint()
            ..color = entry.value == amber
                ? amber
                : entry.value == movedBg
                ? movedInk
                : color,
        );
      }
    }

    lane(left, 2, red);
    lane(right, 12, green);
  }

  @override
  bool shouldRepaint(_OverviewPainter old) =>
      old.left != left || old.right != right || old.wordWrap != wordWrap;
}

/// 滚动只重绘视口框，避免每一帧遍历整份文件的差异标记。
class _ViewportPainter extends CustomPainter {
  const _ViewportPainter(this.start, this.visible);
  final double start, visible;
  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Rect.fromLTRB(
      0.5,
      (start * size.height).clamp(0, size.height),
      size.width - .5,
      ((start + visible) * size.height).clamp(0, size.height),
    );
    canvas.drawRect(viewport, Paint()..color = accent.withValues(alpha: .12));
    canvas.drawRect(
      viewport,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ViewportPainter old) =>
      old.start != start || old.visible != visible;
}
