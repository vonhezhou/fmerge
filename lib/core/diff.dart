import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'myers.dart';

class TextRangeMark {
  const TextRangeMark(this.start, this.end);
  final int start, end;
}

class DiffRow {
  const DiffRow({
    this.left,
    this.right,
    this.leftLine,
    this.rightLine,
    this.leftMarks = const [],
    this.rightMarks = const [],
    this.hunk,
  });
  final String? left, right;
  final int? leftLine, rightLine;
  final List<TextRangeMark> leftMarks, rightMarks;
  final int? hunk;
  bool get changed => hunk != null;
}

class DiffDocument {
  const DiffDocument(
    this.left,
    this.right,
    this.rows,
    this.changes,
    this.hunkRows,
    this.elapsedMicros,
    this.timedOut,
  );
  final List<String> left, right;
  final List<DiffRow> rows;
  final List<SequenceChange> changes;
  final List<int> hunkRows;
  final int elapsedMicros;
  final bool timedOut;
  int get added => changes.fold(0, (n, c) => n + c.bEnd - c.bStart);
  int get removed => changes.fold(0, (n, c) => n + c.aEnd - c.aStart);
}

// 保留尾部空行，从而让“缺少末尾换行”成为可见差异。输入不做换行归一化。
List<String> splitLines(String text) => text.split('\n');

enum WhitespaceMode { exact, trailing, all }

class CompareOptions {
  const CompareOptions({
    this.whitespace = WhitespaceMode.exact,
    this.ignoreCase = false,
    this.ignoreEol = true,
  });
  final WhitespaceMode whitespace;
  final bool ignoreCase, ignoreEol;
  String key(String line) {
    var value = switch (whitespace) {
      WhitespaceMode.exact => line,
      WhitespaceMode.trailing => line.replaceFirst(RegExp(r'[ \t]+$'), ''),
      WhitespaceMode.all => line.replaceAll(RegExp(r'[ \t]'), ''),
    };
    return ignoreCase ? value.toLowerCase() : value;
  }
}

class DiffInput {
  const DiffInput(
    this.left,
    this.right, [
    this.options = const CompareOptions(),
  ]);
  final String left, right;
  final CompareOptions options;
}

DiffDocument computeDiff((String, String) input) =>
    compare(DiffInput(input.$1, input.$2));
DiffDocument compare(DiffInput input) {
  final watch = Stopwatch()..start();
  List<String> logical(String raw) =>
      raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final a = logical(input.left), b = logical(input.right);
  List<String> keys(List<String> lines, String raw) {
    final ends = RegExp(r'\r\n|\r|\n')
        .allMatches(raw)
        .map((m) => m[0]!)
        .toList();
    return [
      for (var i = 0; i < lines.length; i++)
        input.options.key(lines[i]) +
            (input.options.ignoreEol
                ? ''
                : '\x00${i < ends.length ? ends[i] : ""}'),
    ];
  }

  final result = myers(keys(a, input.left), keys(b, input.right));
  var degraded = result.timedOut;
  final rows = <DiffRow>[];
  final starts = <int>[];
  var ai = 0, bi = 0;
  for (var h = 0; h < result.changes.length; h++) {
    final c = result.changes[h];
    while (ai < c.aStart) {
      rows.add(
        DiffRow(left: a[ai], right: b[bi], leftLine: ai++, rightLine: bi++),
      );
    }
    starts.add(rows.length);
    final length = math.max(c.aEnd - c.aStart, c.bEnd - c.bStart);
    for (var i = 0; i < length; i++) {
      final l = c.aStart + i < c.aEnd ? c.aStart + i : null;
      final r = c.bStart + i < c.bEnd ? c.bStart + i : null;
      final refine =
          l != null &&
          r != null &&
          watch.elapsedMilliseconds < 400 &&
          a[l].length + b[r].length <= 24000;
      if (l != null && r != null && !refine) degraded = true;
      final marks = refine
          ? _inline(a[l], b[r])
          : (
              l == null ? <TextRangeMark>[] : [TextRangeMark(0, a[l].length)],
              r == null ? <TextRangeMark>[] : [TextRangeMark(0, b[r].length)],
            );
      rows.add(
        DiffRow(
          left: l == null ? null : a[l],
          right: r == null ? null : b[r],
          leftLine: l,
          rightLine: r,
          leftMarks: marks.$1,
          rightMarks: marks.$2,
          hunk: h,
        ),
      );
    }
    ai = c.aEnd;
    bi = c.bEnd;
  }
  while (ai < a.length) {
    rows.add(
      DiffRow(left: a[ai], right: b[bi], leftLine: ai++, rightLine: bi++),
    );
  }
  return DiffDocument(
    a,
    b,
    rows,
    result.changes,
    starts,
    watch.elapsedMicroseconds,
    degraded,
  );
}

(List<TextRangeMark>, List<TextRangeMark>) _inline(String a, String b) {
  // 使用字素簇避免高亮切开 Emoji、代理对或组合字符。
  final ac = a.characters.toList(), bc = b.characters.toList();
  final result = myers(ac, bc, budget: const Duration(milliseconds: 4));
  List<int> offsets(List<String> chars) {
    final list = [0];
    for (final c in chars) {
      list.add(list.last + c.length);
    }
    return list;
  }

  final ao = offsets(ac), bo = offsets(bc);
  return (
    [
      for (final c in result.changes)
        if (c.aEnd > c.aStart) TextRangeMark(ao[c.aStart], ao[c.aEnd]),
    ],
    [
      for (final c in result.changes)
        if (c.bEnd > c.bStart) TextRangeMark(bo[c.bStart], bo[c.bEnd]),
    ],
  );
}

/// 从真实文档区间复制；视觉占位永远不参与复制。
String selectedText(
  List<String> lines,
  int startLine,
  int startOffset,
  int endLine,
  int endOffset,
) {
  if (startLine > endLine || startLine == endLine && startOffset > endOffset) {
    return selectedText(lines, endLine, endOffset, startLine, startOffset);
  }
  if (startLine == endLine) {
    return lines[startLine].substring(startOffset, endOffset);
  }
  return [
    lines[startLine].substring(startOffset),
    ...lines.sublist(startLine + 1, endLine),
    lines[endLine].substring(0, endOffset),
  ].join('\n');
}
