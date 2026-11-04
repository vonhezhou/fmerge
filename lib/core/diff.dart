import 'dart:math' as math;
import 'dart:collection';
import 'dart:typed_data';

import 'package:characters/characters.dart';

import 'myers.dart';
import 'line_diff.dart';

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
    this.timedOut, {
    this.movedBlocks = const [],
  });
  final List<String> left, right;
  final List<DiffRow> rows;
  final List<SequenceChange> changes;
  final List<int> hunkRows;
  final int elapsedMicros;
  final bool timedOut;
  final List<MovedBlock> movedBlocks;
  int get added => changes.fold(0, (n, c) => n + c.bEnd - c.bStart);
  int get removed => changes.fold(0, (n, c) => n + c.aEnd - c.aStart);

  Iterable<(int, DiffRow)> get changedRows sync* {
    final source = rows;
    if (source is _CompactDiffRows) {
      for (final entry in source._changed.entries) {
        yield (entry.key, entry.value);
      }
    } else {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].changed) yield (i, rows[i]);
      }
    }
  }

  List<int> lineRows(bool leftSide) {
    final result = Int32List(leftSide ? left.length : right.length);
    final source = rows;
    if (source is _CompactDiffRows) {
      final indices = leftSide ? source._left : source._right;
      for (var i = 0; i < source.length; i++) {
        if (indices[i] >= 0) result[indices[i]] = i;
      }
    } else {
      for (var i = 0; i < rows.length; i++) {
        final line = leftSide ? rows[i].leftLine : rows[i].rightLine;
        if (line != null) result[line] = i;
      }
    }
    return result;
  }
}

// 保留尾部空行，从而让“缺少末尾换行”成为可见差异。输入不做换行归一化。
List<String> splitLines(String text) => text.split('\n');

enum WhitespaceMode { exact, trailing, all, edges }

enum InlineDiffMode { characters, words }

/// 仅标记精确匹配且来源唯一的移动，不参与采用区块或合并判断。
class MovedBlock {
  const MovedBlock(this.leftStart, this.rightStart, this.length);
  final int leftStart, rightStart, length;
}

class CompareOptions {
  const CompareOptions({
    this.whitespace = WhitespaceMode.exact,
    this.ignoreCase = false,
    this.ignoreEol = true,
    this.inlineMode = InlineDiffMode.characters,
    this.detectMoves = true,
  });
  final WhitespaceMode whitespace;
  final bool ignoreCase, ignoreEol;
  final InlineDiffMode inlineMode;
  final bool detectMoves;
  String key(String line) {
    var value = switch (whitespace) {
      WhitespaceMode.exact => line,
      WhitespaceMode.trailing => line.replaceFirst(RegExp(r'[ \t]+$'), ''),
      WhitespaceMode.all => line.replaceAll(RegExp(r'[ \t]'), ''),
      WhitespaceMode.edges => line.replaceAll(RegExp(r'^[ \t]+|[ \t]+$'), ''),
    };
    return ignoreCase ? value.toLowerCase() : value;
  }

  @override
  bool operator ==(Object other) =>
      other is CompareOptions &&
      other.whitespace == whitespace &&
      other.ignoreCase == ignoreCase &&
      other.ignoreEol == ignoreEol &&
      other.inlineMode == inlineMode &&
      other.detectMoves == detectMoves;
  @override
  int get hashCode =>
      Object.hash(whitespace, ignoreCase, ignoreEol, inlineMode, detectMoves);
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
    // 默认忽略换行时无需创建逐行换行列表；精确比较还能直接复用行数组。
    if (input.options.ignoreEol) {
      if (input.options.whitespace == WhitespaceMode.exact &&
          !input.options.ignoreCase) {
        return lines;
      }
      return lines.map(input.options.key).toList();
    }
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

  final result = lineDiff(keys(a, input.left), keys(b, input.right));
  var degraded = result.timedOut;
  final changedRows = result.changes.fold<int>(
    0,
    (n, c) => n + math.max(c.aEnd - c.aStart, c.bEnd - c.bStart),
  );
  final totalRows =
      a.length +
      result.changes.fold<int>(
        0,
        (n, c) => n + math.max(0, (c.bEnd - c.bStart) - (c.aEnd - c.aStart)),
      );
  var ai = 0, bi = 0;
  final List<DiffRow> rows = totalRows > 4096 && changedRows * 4 < totalRows
      ? _CompactDiffRows(a, b, totalRows)
      : <DiffRow>[];
  void unchanged() {
    if (rows is _CompactDiffRows) {
      rows.addUnchanged(ai++, bi++);
    } else {
      rows.add(
        DiffRow(left: a[ai], right: b[bi], leftLine: ai++, rightLine: bi++),
      );
    }
  }

  final starts = <int>[];
  for (var h = 0; h < result.changes.length; h++) {
    final c = result.changes[h];
    while (ai < c.aStart) {
      unchanged();
    }
    starts.add(rows.length);
    final length = math.max(c.aEnd - c.aStart, c.bEnd - c.bStart);
    for (var i = 0; i < length; i++) {
      final l = c.aStart + i < c.aEnd ? c.aStart + i : null;
      final r = c.bStart + i < c.bEnd ? c.bStart + i : null;
      final refine =
          l != null &&
          r != null &&
          length <= 2048 &&
          watch.elapsedMilliseconds < 400 &&
          a[l].length + b[r].length <= 24000;
      if (l != null && r != null && !refine) degraded = true;
      final marks = refine
          ? _inline(a[l], b[r], input.options.inlineMode)
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
    unchanged();
  }
  return DiffDocument(
    a,
    b,
    rows,
    result.changes,
    starts,
    watch.elapsedMicroseconds,
    degraded,
    movedBlocks: input.options.detectMoves
        ? _movedBlocks(a, b, result.changes)
        : const [],
  );
}

(List<TextRangeMark>, List<TextRangeMark>) _inline(
  String a,
  String b,
  InlineDiffMode mode,
) {
  if (a == b) return (const [], const []);
  // 使用字素簇避免高亮切开 Emoji、代理对或组合字符。
  List<String> tokens(String text) {
    final chars = text.characters;
    if (mode == InlineDiffMode.characters) return chars.toList();
    // 标识符/数字作为一个词；符号和字素独立，空白连续成组。
    final result = <String>[];
    final word = RegExp(r'^[\p{L}\p{N}_]+$', unicode: true);
    final whitespace = RegExp(r'^\s+$', unicode: true);
    var buffer = StringBuffer(), previous = -1;
    for (final char in chars) {
      final kind = word.hasMatch(char)
          ? 0
          : whitespace.hasMatch(char)
          ? 1
          : 2;
      if (kind != previous || kind == 2) {
        if (buffer.isNotEmpty) result.add(buffer.toString());
        buffer = StringBuffer();
      }
      buffer.write(char);
      previous = kind;
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  final ac = tokens(a), bc = tokens(b);
  final result = myers(ac, bc, budget: const Duration(milliseconds: 4));
  List<int> offsets(List<String> chars) {
    final list = [0];
    for (final c in chars) {
      list.add(list.last + c.length);
    }
    return list;
  }

  final ao = offsets(ac), bo = offsets(bc);
  // 保留零长度的插入/删除边界，让两侧可逐片段导航；绘制时自然没有填充面积。
  return (
    [for (final c in result.changes) TextRangeMark(ao[c.aStart], ao[c.aEnd])],
    [for (final c in result.changes) TextRangeMark(bo[c.bStart], bo[c.bEnd])],
  );
}

List<MovedBlock> _movedBlocks(
  List<String> a,
  List<String> b,
  List<SequenceChange> changes,
) {
  if (changes.length < 2) return const [];
  final removed = <int>{}, added = <int>{};
  for (final c in changes) {
    for (var i = c.aStart; i < c.aEnd; i++) {
      removed.add(i);
    }
    for (var i = c.bStart; i < c.bEnd; i++) {
      added.add(i);
    }
  }
  // 以整份输入中的唯一非空行作锚点，避免把重复代码或复制误报为移动。
  Map<String, int> unique(List<String> lines) {
    final result = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      result.update(lines[i], (_) => -1, ifAbsent: () => i);
    }
    return result;
  }

  final left = unique(a), right = unique(b);
  final usedA = <int>{}, usedB = <int>{};
  final blocks = <MovedBlock>[];
  for (final i in removed) {
    final j = right[a[i]];
    if (left[a[i]] != i ||
        j == null ||
        j < 0 ||
        !added.contains(j) ||
        usedA.contains(i) ||
        usedB.contains(j)) {
      continue;
    }
    var startA = i, startB = j, endA = i + 1, endB = j + 1;
    while (removed.contains(startA - 1) &&
        added.contains(startB - 1) &&
        !usedA.contains(startA - 1) &&
        !usedB.contains(startB - 1) &&
        a[startA - 1] == b[startB - 1]) {
      startA--;
      startB--;
    }
    while (removed.contains(endA) &&
        added.contains(endB) &&
        !usedA.contains(endA) &&
        !usedB.contains(endB) &&
        a[endA] == b[endB]) {
      endA++;
      endB++;
    }
    // 单个短行（如括号）不足以说明代码移动。
    if (endA - startA < 2 ||
        a.sublist(startA, endA).join().trim().length < 16) {
      continue;
    }
    blocks.add(MovedBlock(startA, startB, endA - startA));
    for (var k = startA; k < endA; k++) {
      usedA.add(k);
    }
    for (var k = startB; k < endB; k++) {
      usedB.add(k);
    }
  }
  return blocks;
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

/// 大量未修改行只保留紧凑索引，按读取创建行视图；变化行保留完整高亮。
class _CompactDiffRows extends ListBase<DiffRow> {
  _CompactDiffRows(this.left, this.right, int capacity)
    : _left = Int32List(capacity),
      _right = Int32List(capacity);
  final List<String> left, right;
  final Int32List _left, _right;
  final _changed = <int, DiffRow>{};
  int _length = 0;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('只读差异行');
  @override
  DiffRow operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final changed = _changed[index];
    if (changed != null) return changed;
    final l = _left[index], r = _right[index];
    return DiffRow(left: left[l], right: right[r], leftLine: l, rightLine: r);
  }

  @override
  void operator []=(int index, DiffRow value) =>
      throw UnsupportedError('只读差异行');
  void addUnchanged(int left, int right) {
    _left[_length] = left;
    _right[_length++] = right;
  }

  @override
  void add(DiffRow row) {
    _changed[_length] = row;
    _left[_length] = row.leftLine ?? -1;
    _right[_length++] = row.rightLine ?? -1;
  }
}
