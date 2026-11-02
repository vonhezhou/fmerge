import 'diff.dart';
import 'merge.dart';
import 'myers.dart';

class ConflictRegion {
  const ConflictRegion(this.chunk, this.start, this.end, this.resolved);
  final MergeChunk chunk;
  final int start, end;
  final bool resolved;
  ConflictRegion copy({int? start, int? end, bool? resolved}) => ConflictRegion(
    chunk,
    start ?? this.start,
    end ?? this.end,
    resolved ?? this.resolved,
  );
}

class MergeSnapshot {
  const MergeSnapshot(this.text, this.regions);
  final String text;
  final List<ConflictRegion> regions;
}

class MergeSession {
  MergeSession(MergePlan plan) {
    final lines = <String>[];
    final regions = <ConflictRegion>[];
    var cursor = 0;
    for (final c in plan.chunks) {
      lines.addAll(plan.base.sublist(cursor, c.start));
      final start = lines.length;
      lines.addAll(c.resolve(null));
      if (c.conflict) {
        regions.add(ConflictRegion(c, start, lines.length, false));
      }
      cursor = c.end;
    }
    lines.addAll(plan.base.sublist(cursor));
    _history.add(MergeSnapshot(lines.join('\n'), regions));
  }
  final _history = <MergeSnapshot>[];
  var _index = 0;
  MergeSnapshot get state => _history[_index];
  int get pending => state.regions.where((r) => !r.resolved).length;
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _history.length - 1;
  void undo() {
    if (canUndo) _index--;
  }

  void redo() {
    if (canRedo) _index++;
  }

  void _push(MergeSnapshot next) {
    _history.removeRange(_index + 1, _history.length);
    _history.add(next);
    _index++;
    // 限制历史内存；保留至少当前状态。
    while (_history.length > 1 &&
        (_history.length > 300 ||
            _history.fold<int>(0, (sum, s) => sum + s.text.length) >
                32 * 1024 * 1024)) {
      _history.removeAt(0);
      _index--;
    }
  }

  void edit(String next) {
    if (next == state.text) return;
    final changes = myers(splitLines(state.text), splitLines(next)).changes;
    int map(int line, bool end) {
      var delta = 0;
      for (final c in changes) {
        if (line < c.aStart || line == c.aStart && !end) break;
        if (line <= c.aEnd) return end ? c.bEnd : c.bStart;
        delta += c.bEnd - c.bStart - (c.aEnd - c.aStart);
      }
      return line + delta;
    }

    final length = splitLines(next).length;
    _push(
      MergeSnapshot(next, [
        for (final r in state.regions)
          r.copy(
            start: map(r.start, false).clamp(0, length),
            end: map(r.end, true).clamp(0, length),
          ),
      ]),
    );
  }

  void choose(int id, MergeChoice choice, {bool reverse = false}) {
    final region = state.regions.firstWhere((r) => r.chunk.id == id);
    final replacement = choice == MergeChoice.both && reverse
        ? [...region.chunk.right, ...region.chunk.left]
        : region.chunk.resolve(choice);
    final lines = splitLines(state.text);
    final start = region.start.clamp(0, lines.length),
        end = region.end.clamp(start, lines.length);
    lines.replaceRange(start, end, replacement);
    final delta = replacement.length - (end - start);
    _push(
      MergeSnapshot(lines.join('\n'), [
        for (final r in state.regions)
          r.chunk.id == id
              ? r.copy(
                  start: start,
                  end: start + replacement.length,
                  resolved: true,
                )
              : r.start >= end
              ? r.copy(start: r.start + delta, end: r.end + delta)
              : r,
      ]),
    );
  }

  void markResolved(int id, bool resolved) => _push(
    MergeSnapshot(state.text, [
      for (final r in state.regions)
        r.chunk.id == id ? r.copy(resolved: resolved) : r,
    ]),
  );
}
