import 'package:re_editor/re_editor.dart';

import 'line_diff.dart';
import 'myers.dart';

/// 跳过共享的不可变分段，只在真正变化的片段中计算行差异。
List<SequenceChange> editorChanges(CodeLines before, CodeLines after) {
  var head = 0, prefix = 0;
  while (head < before.segments.length &&
      head < after.segments.length &&
      identical(
        before.segments[head].codeLines,
        after.segments[head].codeLines,
      )) {
    prefix += before.segments[head++].length;
  }
  var ai = before.segments.length - 1, bi = after.segments.length - 1;
  var oldEnd = before.length, newEnd = after.length;
  while (ai >= head &&
      bi >= head &&
      identical(before.segments[ai].codeLines, after.segments[bi].codeLines)) {
    oldEnd -= before.segments[ai--].length;
    newEnd -= after.segments[bi--].length;
  }
  List<String> texts(CodeLines lines, int end) => [
    for (final segment in lines.sublines(prefix, end).segments)
      for (final line in segment.codeLines) line.text,
  ];
  return [
    for (final c in lineDiff(
      texts(before, oldEnd),
      texts(after, newEnd),
    ).changes)
      SequenceChange(
        prefix + c.aStart,
        prefix + c.aEnd,
        prefix + c.bStart,
        prefix + c.bEnd,
      ),
  ];
}
