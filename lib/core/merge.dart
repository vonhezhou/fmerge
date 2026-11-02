import 'diff.dart';
import 'myers.dart';

enum MergeChoice { left, right, both, base }

class MergeChunk {
  const MergeChunk(
    this.id,
    this.start,
    this.end,
    this.base,
    this.left,
    this.right,
    this.conflict,
    this.automatic,
  );
  final int id, start, end;
  final List<String> base, left, right, automatic;
  final bool conflict;
  List<String> resolve(MergeChoice? choice) => !conflict
      ? automatic
      : switch (choice) {
          MergeChoice.left => left,
          MergeChoice.right => right,
          MergeChoice.both => [...left, ...right],
          MergeChoice.base || null => base,
        };
}

class MergePlan {
  const MergePlan(this.base, this.chunks);
  final List<String> base;
  final List<MergeChunk> chunks;
  List<MergeChunk> get conflicts => chunks.where((c) => c.conflict).toList();
  String compose(Map<int, MergeChoice> choices) {
    final output = <String>[];
    var cursor = 0;
    for (final chunk in chunks) {
      output.addAll(base.sublist(cursor, chunk.start));
      output.addAll(chunk.resolve(choices[chunk.id]));
      cursor = chunk.end;
    }
    output.addAll(base.sublist(cursor));
    return output.join('\n');
  }
}

class _Edit {
  const _Edit(this.change, this.left);
  final SequenceChange change;
  final bool left;
}

MergePlan planMerge(String base, String left, String right) {
  final b = splitLines(base), l = splitLines(left), r = splitLines(right);
  final ld = myers(b, l), rd = myers(b, r);
  // 超时后的粗粒度替换仍保留完整内容，宁可扩大冲突也不静默丢失修改。
  final edits = [
    ...ld.changes.map((c) => _Edit(c, true)),
    ...rd.changes.map((c) => _Edit(c, false)),
  ]..sort((a, b) => a.change.aStart.compareTo(b.change.aStart));
  final chunks = <MergeChunk>[];
  var index = 0;
  while (index < edits.length) {
    final group = <_Edit>[edits[index++]];
    final start = group.first.change.aStart;
    var end = group.first.change.aEnd;
    while (index < edits.length) {
      final c = edits[index].change;
      // 邻接替换可独立合并；同一位置插入或插入落在修改边界时保守标冲突。
      final touches =
          c.aStart < end ||
          c.aStart == end && (c.aStart == c.aEnd || start == end);
      if (!touches) break;
      group.add(edits[index++]);
      if (c.aEnd > end) end = c.aEnd;
    }
    List<String> render(bool isLeft) {
      final own = group.where((e) => e.left == isLeft).toList();
      final result = <String>[];
      var cursor = start;
      for (final e in own) {
        result.addAll(b.sublist(cursor, e.change.aStart));
        result.addAll((isLeft ? l : r).sublist(e.change.bStart, e.change.bEnd));
        cursor = e.change.aEnd;
      }
      result.addAll(b.sublist(cursor, end));
      return result;
    }

    final leftPart = render(true), rightPart = render(false);
    final hasLeft = group.any((e) => e.left),
        hasRight = group.any((e) => !e.left);
    final same =
        leftPart.length == rightPart.length &&
        List.generate(
          leftPart.length,
          (i) => leftPart[i] == rightPart[i],
        ).every((v) => v);
    final conflict = hasLeft && hasRight && !same;
    chunks.add(
      MergeChunk(
        chunks.length,
        start,
        end,
        b.sublist(start, end),
        leftPart,
        rightPart,
        conflict,
        hasLeft ? leftPart : rightPart,
      ),
    );
  }
  return MergePlan(b, chunks);
}
