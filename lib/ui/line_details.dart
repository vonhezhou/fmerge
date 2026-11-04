import 'package:flutter/material.dart';

import '../core/diff.dart';
import '../palette.dart';

/// 详情与编辑器共用真实行和范围，长行可独立横向滚动。
class LineDetails extends StatelessWidget {
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

  TextSpan _span(
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
          style: TextStyle(backgroundColor: color, fontWeight: FontWeight.bold),
        ),
      );
      offset = end;
    }
    children.add(TextSpan(text: display(text.substring(offset))));
    if (truncated) {
      children.add(
        const TextSpan(
          text: ' …',
          style: TextStyle(color: muted),
        ),
      );
    }
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 104,
    decoration: const BoxDecoration(
      color: panel,
      border: Border(top: BorderSide(color: border)),
    ),
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            conflict ? '冲突首行' : '行详情',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ),
        Expanded(
          child: row == null
              ? const Text(
                  '正在比较或当前行没有可对应的输入',
                  style: TextStyle(color: muted, fontSize: 11),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var side = 0; side < 2; side++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      '${side == 0 ? "左" : "右"} L${(side == 0 ? row!.leftLine : row!.rightLine) == null ? "—" : (side == 0 ? row!.leftLine! : row!.rightLine!) + 1}  ',
                                  style: TextStyle(
                                    color: side == 0 ? red : green,
                                  ),
                                ),
                                if ((side == 0 ? row!.left : row!.right) ==
                                    null)
                                  const TextSpan(
                                    text: '（此侧无对应行）',
                                    style: TextStyle(color: muted),
                                  )
                                else
                                  _span(
                                    side == 0 ? row!.left! : row!.right!,
                                    side == 0
                                        ? row!.leftMarks
                                        : row!.rightMarks,
                                    tabSizes[side],
                                    side == 0 ? removedInline : addedInline,
                                  ),
                              ],
                            ),
                            key: ValueKey('line-detail-$side'),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: fontSize,
                              color: ink,
                            ),
                            maxLines: 1,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        if (merge)
          const Tooltip(
            message: '三方输入按共同祖先对齐；高亮为各侧相对祖先的变化',
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.info_outline, size: 16, color: muted),
            ),
          ),
        if (movementLabel != null)
          TextButton.icon(
            key: const ValueKey('follow-moved-block'),
            onPressed: onFollowMove,
            icon: const Icon(Icons.swap_horiz, size: 16, color: movedInk),
            label: Text(
              movementLabel!,
              style: const TextStyle(color: movedInk, fontSize: 11),
            ),
          ),
        IconButton(
          tooltip: '隐藏行详情',
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}
