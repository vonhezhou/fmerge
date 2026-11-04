import 'package:flutter/material.dart';

import '../core/diff.dart';
import '../palette.dart';

/// 详情与编辑器共用真实行和范围，长行可独立横向滚动。
class LineDetails extends StatefulWidget {
  const LineDetails({
    super.key,
    required this.row,
    required this.tabSizes,
    required this.fontSize,
    required this.onClose,
    this.merge = false,
    this.conflict = false,
    this.movementLabel,
    this.onFollowMove,
  });
  final DiffRow? row;
  final List<int> tabSizes;
  final double fontSize;
  final bool merge;
  final bool conflict;
  final VoidCallback onClose;
  final String? movementLabel;
  final VoidCallback? onFollowMove;

  @override
  State<LineDetails> createState() => _LineDetailsState();
}

class _LineDetailsState extends State<LineDetails> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  TextSpan _span(
    BuildContext context,
    String text,
    List<TextRangeMark> marks,
    int tabSize,
    Color color,
  ) {
    var truncated = false;
    if (text.length > 32000) {
      var end = 32000;
      if (text.codeUnitAt(end - 1) >= 0xd800 &&
          text.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      text = text.substring(0, end);
      truncated = true;
    }
    final children = <InlineSpan>[];
    var offset = 0, column = 0;
    String display(String value) {
      final buffer = StringBuffer();
      for (final rune in value.runes) {
        if (rune == 9) {
          final width = tabSize - column % tabSize;
          buffer.write(' ' * width);
          column += width;
        } else {
          buffer.writeCharCode(rune);
          column++;
        }
      }
      return buffer.toString();
    }

    for (final mark in marks) {
      final start = mark.start.clamp(offset, text.length),
          end = mark.end.clamp(start, text.length);
      children.add(TextSpan(text: display(text.substring(offset, start))));
      children.add(
        TextSpan(
          text: display(text.substring(start, end)),
          style: TextStyle(backgroundColor: color),
        ),
      );
      offset = end;
    }
    children.add(TextSpan(text: display(text.substring(offset))));
    if (truncated) {
      children.add(
        TextSpan(
          text: ' …',
          style: TextStyle(color: muted),
        ),
      );
    }
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final rowHeight = (widget.fontSize * 1.5 + 10).clamp(30.0, 48.0);
    final row = widget.row;
    final identical = row != null && row.left != null && row.left == row.right;
    Color rowColor(int side) => identical
        ? panel
        : (side == 0 ? removedBg : addedBg).withValues(alpha: .32);
    return Container(
      decoration: BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Row(
                children: [
                  Icon(Icons.segment, size: 14, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    widget.conflict ? '冲突首行' : '行详情',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                  if (identical) ...[
                    const SizedBox(width: 12),
                    Text(
                      '两侧相同',
                      style: TextStyle(
                        fontSize: 10,
                        color: muted.withValues(alpha: .7),
                      ),
                    ),
                  ],
                  if (widget.merge)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: '三方输入按共同祖先对齐；高亮为各侧相对祖先的变化',
                        child: Icon(Icons.info_outline, size: 13, color: muted),
                      ),
                    ),
                  const Spacer(),
                  if (widget.movementLabel != null)
                    TextButton.icon(
                      key: const ValueKey('follow-moved-block'),
                      onPressed: widget.onFollowMove,
                      style: TextButton.styleFrom(
                        foregroundColor: movedInk,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 14),
                      label: Text(
                        widget.movementLabel!,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '隐藏行详情',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 14),
                    color: muted,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          if (row == null)
            SizedBox(
              height: rowHeight * 2 + 8,
              child: Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '正在比较或当前行没有可对应的输入',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: rowHeight * 2 + 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 侧别和真实行号固定，横向滚动只移动代码。
                  SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        for (var side = 0; side < 2; side++)
                          Container(
                            height: rowHeight,
                            padding: const EdgeInsets.only(left: 12, right: 10),
                            decoration: BoxDecoration(
                              color: elevated.withValues(alpha: .35),
                              border: Border(
                                right: BorderSide(
                                  color: border.withValues(alpha: .6),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 2,
                                  height: 12,
                                  color: (side == 0 ? red : green).withValues(
                                    alpha: .8,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  side == 0 ? '左侧' : '右侧',
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                                Expanded(
                                  child: Text(
                                    (side == 0
                                                ? row.leftLine
                                                : row.rightLine) ==
                                            null
                                        ? '—'
                                        : '${(side == 0 ? row.leftLine! : row.rightLine!) + 1}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: Scrollbar(
                          controller: _scroll,
                          thumbVisibility: true,
                          thickness: 4,
                          radius: const Radius.circular(2),
                          child: SingleChildScrollView(
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: IntrinsicWidth(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var side = 0; side < 2; side++)
                                      Container(
                                        height: rowHeight,
                                        alignment: Alignment.centerLeft,
                                        color: rowColor(side),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text.rich(
                                          (side == 0 ? row.left : row.right) ==
                                                  null
                                              ? TextSpan(
                                                  text: '此侧无对应行',
                                                  style: TextStyle(
                                                    color: muted,
                                                    fontSize: 11,
                                                  ),
                                                )
                                              : _span(
                                                  context,
                                                  side == 0
                                                      ? row.left!
                                                      : row.right!,
                                                  side == 0
                                                      ? row.leftMarks
                                                      : row.rightMarks,
                                                  widget.tabSizes[side],
                                                  side == 0
                                                      ? removedInline
                                                      : addedInline,
                                                ),
                                          key: ValueKey('line-detail-$side'),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: widget.fontSize,
                                            height: 1.5,
                                            color: ink,
                                          ),
                                          maxLines: 1,
                                          softWrap: false,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
