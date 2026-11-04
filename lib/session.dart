import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:re_editor/re_editor.dart';

import 'core/diff.dart';
import 'core/compare_task.dart';
import 'core/context_rows.dart';
import 'core/alignment.dart';
import 'core/files.dart';
import 'core/launch.dart';
import 'core/git.dart';
import 'core/merge_labels.dart';
import 'core/merge.dart';
import 'core/merge_session.dart';
import 'palette.dart';

class CompareSession extends ChangeNotifier {
  CompareSession(
    this.left,
    this.right, {
    this.base,
    this.output,
    this.readOnly = false,
    this.mergeLabels = const MergeLabels(),
    CompareRunner? compareRunner,
  }) : _compareRunner = compareRunner ?? _runComparison {
    leftEditor = CodeLineEditingController.fromText(left.text);
    rightEditor = CodeLineEditingController.fromText(right.text);
    if (base != null) {
      merger = MergeSession(planMerge(base!.text, left.text, right.text));
      resultEditor = CodeLineEditingController.fromText(merger!.state.text);
      resultEditor!.addListener(_resultChanged);
    }
    _lastLeft = leftEditor.text;
    _lastRight = rightEditor.text;
    _lastLeftSelection = leftEditor.selection;
    _lastRightSelection = rightEditor.selection;
    leftEditor.addListener(_inputChanged);
    rightEditor.addListener(_inputChanged);
    _lastResult = resultEditor?.text ?? '';
    _savedResult = output?.text ?? '';
  }
  TextFile left, right;
  final TextFile? base;
  TextFile? output;
  String? leftLanguage, rightLanguage, resultLanguage, baseLanguage;
  final saveEncodings = <int, TextEncoding>{};
  final saveEols = <int, String>{};
  final bool readOnly;
  MergeLabels mergeLabels;
  late CodeLineEditingController leftEditor, rightEditor;
  CodeLineEditingController? resultEditor;
  MergeSession? merger;
  final _positions = Expando<CodeLinePosition>();
  DiffDocument? diff;
  ThreeWayAlignment? mergeAlignment;
  List<int> get hunkRows => isMerge
      ? mergeAlignment?.changeRows ?? const []
      : [
          for (final row in diff?.hunkRows ?? <int>[])
            _context?.rows[row] ?? row,
        ];
  String? error;
  bool busy = false,
      savedMerge = false,
      _disposed = false,
      _programmatic = false;
  late String _lastLeft, _lastRight, _lastResult, _savedResult;
  late CodeLineSelection _lastLeftSelection, _lastRightSelection;
  Timer? _timer;
  final CompareRunner _compareRunner;
  Future<void>? _refreshTask;
  bool _refreshPending = false;
  var _generation = 0;
  CompareOptions options = const CompareOptions();
  bool showWhitespace = false;
  bool contextOnly = false;
  int contextLines = 3;
  ContextRows? _context;
  CodeDiffLayout? _fullLeft, _fullRight;
  final _leftChange = _InputChange(), _rightChange = _InputChange();

  void swapSides() {
    if (isMerge || output != null || busy) return;
    final file = left;
    left = right;
    right = file;
    final language = leftLanguage;
    leftLanguage = rightLanguage;
    rightLanguage = language;
    void swap<T>(Map<int, T> values) {
      final left = values.remove(0), right = values.remove(1);
      if (left != null) values[1] = left;
      if (right != null) values[0] = right;
    }

    swap(saveEncodings);
    swap(saveEols);
    final controller = leftEditor;
    leftEditor = rightEditor;
    rightEditor = controller;
    _lastLeft = leftEditor.text;
    _lastRight = rightEditor.text;
    _lastLeftSelection = leftEditor.selection;
    _lastRightSelection = rightEditor.selection;
    diff = null;
    _fullLeft = _fullRight = null;
    refresh();
  }

  void setContextOnly(bool value, {int? context}) {
    contextOnly = value;
    if (context != null) contextLines = context.clamp(0, 1000);
    _applyLayouts();
    notifyListeners();
  }

  void _applyLayouts() {
    if (_fullLeft == null || _fullRight == null) return;
    _programmatic = true;
    _context = contextOnly && !isMerge && diff != null
        ? ContextRows(diff!.rows.length, {
            for (var i = 0; i < diff!.rows.length; i++)
              if (diff!.rows[i].changed) i,
          }, context: contextLines)
        : null;
    CodeDiffLayout project(CodeDiffLayout layout) {
      final map = _context;
      if (map == null) return layout;
      return CodeDiffLayout(
        lineRows: [for (final row in layout.lineRows) map.rows[row]],
        totalRows: map.totalRows,
        hiddenLines: {
          for (var i = 0; i < layout.lineRows.length; i++)
            if (map.hidden.contains(layout.lineRows[i])) i,
        },
        rowLabels: map.labels,
        rowColors: {
          for (final entry in layout.rowColors.entries)
            if (!map.hidden.contains(entry.key))
              map.rows[entry.key]: entry.value,
        },
        ranges: layout.ranges,
        showWhitespace: layout.showWhitespace,
      );
    }

    leftEditor.diffLayout = project(_fullLeft!);
    rightEditor.diffLayout = project(_fullRight!);
    _programmatic = false;
  }

  void setShowWhitespace(bool value) {
    showWhitespace = value;
    CodeDiffLayout? update(CodeDiffLayout? layout) => layout == null
        ? null
        : CodeDiffLayout(
            lineRows: layout.lineRows,
            totalRows: layout.totalRows,
            hiddenLines: layout.hiddenLines,
            rowLabels: layout.rowLabels,
            rowColors: layout.rowColors,
            ranges: layout.ranges,
            showWhitespace: value,
          );
    _fullLeft = update(_fullLeft);
    _fullRight = update(_fullRight);
    updateResultLayout();
    _applyLayouts();
    notifyListeners();
  }

  bool get isMerge => base != null;
  Future<void> identifyMergeLabels() async {
    if (!isMerge || output?.path == null) return;
    final labels = await GitMergeLabels.detect(
      left: left,
      right: right,
      base: base!,
      output: output!.path!,
    );
    if (_disposed) return;
    mergeLabels = labels;
    notifyListeners();
  }

  int get pending => merger?.pending ?? 0;
  bool get leftDirty =>
      _leftChange.changed(leftEditor.text, left.original) ||
      saveEncodings.containsKey(0) ||
      saveEols.containsKey(0);
  bool get rightDirty =>
      _rightChange.changed(
        rightEditor.text,
        (!isMerge && output != null ? output! : right).original,
      ) ||
      saveEncodings.containsKey(1) ||
      saveEols.containsKey(1);
  bool get resultDirty =>
      isMerge &&
      (resultEditor!.text != _savedResult ||
          !savedMerge ||
          pending > 0 ||
          saveEncodings.containsKey(2) ||
          saveEols.containsKey(2));
  bool get dirty => !readOnly && (leftDirty || rightDirty || resultDirty);
  int get toolExitCode =>
      isMerge && (!savedMerge || resultDirty || pending > 0) ? 1 : 0;
  static Future<CompareSession> open(
    LaunchOptions args, {
    TextEncoding? encoding,
    TextEncoding? leftEncoding,
    TextEncoding? rightEncoding,
    TextEncoding? baseEncoding,
    TextEncoding? outputEncoding,
    List<TextFile>? inputs,
  }) async {
    if (args.left == null) {
      return CompareSession(
        TextFile.empty(),
        TextFile.empty(),
        readOnly: args.readOnly,
      );
    }
    if (inputs != null && inputs.length != (args.merge ? 3 : 2)) {
      throw ArgumentError('输入文件数量与比较模式不符');
    }
    final files =
        inputs ??
        await Future.wait([
          TextFile.read(args.left!, encoding: leftEncoding ?? encoding),
          TextFile.read(args.right!, encoding: rightEncoding ?? encoding),
          if (args.base != null)
            TextFile.read(args.base!, encoding: baseEncoding ?? encoding),
        ]);
    TextFile? output;
    if (args.output != null) {
      output = await File(args.output!).exists()
          ? await TextFile.read(
              args.output!,
              encoding: outputEncoding ?? encoding,
            )
          : (TextFile.empty(
                args.merge ? files.last.original : files[1].original,
              )
              ..encoding = (args.merge ? files.last : files[1]).encoding
              ..path = File(args.output!).absolute.path
              ..digest = null);
    }
    final labels = args.merge && args.output != null
        ? await GitMergeLabels.detect(
            left: files[0],
            right: files[1],
            base: files[2],
            output: args.output!,
          )
        : const MergeLabels();
    return CompareSession(
      files[0],
      files[1],
      mergeLabels: labels,
      base: files.length == 3 ? files[2] : null,
      output: output,
      readOnly: args.readOnly,
    );
  }

  void _inputChanged() {
    if (_programmatic || _disposed) return;
    final a = leftEditor.text, b = rightEditor.text;
    final movedLeft = _lastLeftSelection != leftEditor.selection;
    final movedRight = _lastRightSelection != rightEditor.selection;
    _lastLeftSelection = leftEditor.selection;
    _lastRightSelection = rightEditor.selection;
    if (a == _lastLeft && b == _lastRight) {
      // 查找、跳转或键盘导航进入隐藏行时展开，避免光标落在不可见内容中。
      if (contextOnly &&
          ((movedLeft &&
                  leftEditor.diffLayout?.hiddenLines.contains(
                        leftEditor.selection.extentIndex,
                      ) ==
                      true) ||
              (movedRight &&
                  rightEditor.diffLayout?.hiddenLines.contains(
                        rightEditor.selection.extentIndex,
                      ) ==
                      true))) {
        setContextOnly(false);
      }
      return;
    }
    if (contextOnly) setContextOnly(false);
    _lastLeft = a;
    _lastRight = b;
    schedule();
    notifyListeners();
  }

  void _resultChanged() {
    if (_programmatic || _disposed) return;
    final text = resultEditor!.text;
    if (text == _lastResult) {
      _positions[merger!.state] = resultEditor!.selection.extent;
      return;
    }
    _positions[merger!.state] =
        resultEditor!.preValue?.selection.extent ??
        resultEditor!.selection.extent;
    _lastResult = text;
    merger!.edit(text);
    _positions[merger!.state] = resultEditor!.selection.extent;
    updateResultLayout();
    notifyListeners();
  }

  void inputSaved({int? side}) {
    saveEncodings.remove(side);
    saveEols.remove(side);
    notifyListeners();
  }

  void setSaveEncoding(int side, TextEncoding encoding) {
    if (readOnly || isMerge && side != 2) return;
    final controller = side == 0
        ? leftEditor
        : side == 1
        ? rightEditor
        : resultEditor!;
    TextFile.encode(controller.text, encoding);
    saveEncodings[side] = encoding;
    notifyListeners();
  }

  void setSaveEol(int side, String? eol) {
    if (readOnly || isMerge && side != 2) return;
    if (eol == null) {
      saveEols.remove(side);
    } else {
      saveEols[side] = eol;
    }
    notifyListeners();
  }

  void reloadInput(int side, TextFile file) {
    if (isMerge) throw StateError('合并输入需重新创建合并会话');
    final controller = side == 0 ? leftEditor : rightEditor;
    if (side == 0) {
      left = file;
    } else {
      right = file;
    }
    saveEncodings.remove(side);
    saveEols.remove(side);
    controller.text = file.text;
    controller.clearHistory();
    schedule();
    notifyListeners();
  }

  void schedule() {
    if (_disposed) return;
    _generation++; // 输入一变化就使旧计算失效，而不是等下一次防抖触发。
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 140), refresh);
  }

  Future<void> refresh([CompareOptions? nextOptions]) {
    if (_disposed) return Future<void>.value();
    _timer?.cancel();
    if (nextOptions != null) options = nextOptions;
    ++_generation;
    _refreshPending = true;
    busy = true;
    error = null;
    final running = _refreshTask;
    if (running != null) {
      notifyListeners();
      return running;
    }
    final completion = Completer<void>();
    _refreshTask = completion.future;
    notifyListeners();
    unawaited(_drainRefresh(completion));
    return completion.future;
  }

  Future<void> _drainRefresh(Completer<void> completion) async {
    try {
      // 等待期间只记录“需要重算”，不捕获文本或再启动 isolate。
      while (_refreshPending && !_disposed) {
        _refreshPending = false;
        _timer?.cancel();
        final generation = _generation;
        try {
          final result = await _compareRunner(
            CompareTask(
              left: leftEditor.text,
              right: rightEditor.text,
              options: options,
              leftOriginal: options.ignoreEol ? null : left.original,
              rightOriginal: options.ignoreEol ? null : right.original,
              base: base?.original,
            ),
          );
          if (_disposed || generation != _generation) continue;
          diff = result.diff;
          _programmatic = true;
          try {
            final branches = result.branches;
            if (branches != null) {
              mergeAlignment = alignThreeWay(branches[0], branches[1]);
              _fullLeft = _branchLayout(
                branches[0],
                mergeAlignment!.localRows,
                true,
              );
              _fullRight = _branchLayout(
                branches[1],
                mergeAlignment!.remoteRows,
                false,
              );
            } else {
              _fullLeft = _layout(result.diff, true);
              _fullRight = _layout(result.diff, false);
            }
            _applyLayouts();
          } finally {
            _programmatic = false;
          }
        } catch (e) {
          if (!_disposed && generation == _generation) error = e.toString();
        }
      }
    } finally {
      _refreshTask = null;
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
      completion.complete();
    }
  }

  CodeDiffLayout _layout(DiffDocument diff, bool left) {
    final rows = <int>[],
        colors = <int, Color>{},
        ranges = <int, List<CodeDiffRange>>{};
    for (var i = 0; i < diff.rows.length; i++) {
      final row = diff.rows[i],
          line = left ? diff.rows[i].leftLine : diff.rows[i].rightLine;
      if (line != null) rows.add(i);
      if (row.changed) {
        colors[i] = line == null ? bg : (left ? removedBg : addedBg);
      }
      final marks = left ? row.leftMarks : row.rightMarks;
      if (line != null && marks.isNotEmpty) {
        ranges[line] = [
          for (final m in marks)
            CodeDiffRange(m.start, m.end, left ? removedInline : addedInline),
        ];
      }
    }
    return CodeDiffLayout(
      lineRows: rows,
      totalRows: diff.rows.length,
      rowColors: colors,
      ranges: ranges,
      showWhitespace: showWhitespace,
    );
  }

  CodeDiffLayout _branchLayout(
    DiffDocument branch,
    List<int> rows,
    bool local,
  ) {
    final colors = <int, Color>{};
    final ranges = <int, List<CodeDiffRange>>{};
    for (final row in branch.rows) {
      final line = row.rightLine;
      if (line == null) continue;
      if (row.changed) colors[rows[line]] = local ? removedBg : addedBg;
      if (row.rightMarks.isEmpty) continue;
      ranges[line] = [
        for (final mark in row.rightMarks)
          CodeDiffRange(
            mark.start,
            mark.end,
            local ? removedInline : addedInline,
          ),
      ];
    }
    final realRows = rows.toSet();
    for (var i = 0; i < mergeAlignment!.totalRows; i++) {
      if (!realRows.contains(i)) colors[i] = bg;
    }
    return CodeDiffLayout(
      lineRows: rows,
      totalRows: mergeAlignment!.totalRows,
      rowColors: colors,
      ranges: ranges,
      showWhitespace: showWhitespace,
    );
  }

  void applyHunk(int hunk, {bool toRight = true, int combine = 0}) {
    if (readOnly ||
        diff == null ||
        hunk < 0 ||
        hunk >= diff!.changes.length ||
        busy) {
      return;
    }
    final c = diff!.changes[hunk];
    final source = toRight
        ? diff!.left.sublist(c.aStart, c.aEnd)
        : diff!.right.sublist(c.bStart, c.bEnd);
    final target = toRight ? rightEditor : leftEditor;
    final lines = target.text.split('\n');
    final start = toRight ? c.bStart : c.aStart,
        end = toRight ? c.bEnd : c.aEnd;
    final old = lines.sublist(start, end);
    lines.replaceRange(
      start,
      end,
      combine == 1
          ? [...source, ...old]
          : combine == 2
          ? [...old, ...source]
          : source,
    );
    target.runRevocableOp(() => target.text = lines.join('\n'));
  }

  void choose(int id, MergeChoice choice, {bool reverse = false}) {
    if (readOnly) return;
    _positions[merger!.state] = resultEditor!.selection.extent;
    merger!.choose(id, choice, reverse: reverse);
    _positions[merger!.state] = CodeLinePosition(
      index: merger!.state.regions.firstWhere((r) => r.chunk.id == id).start,
      offset: 0,
    );
    _setMergeState();
  }

  void markResolved(int id, bool resolved) {
    if (readOnly) return;
    final position = resultEditor!.selection.extent;
    _positions[merger!.state] = position;
    merger!.markResolved(id, resolved);
    _positions[merger!.state] = position;
    _setMergeState();
  }

  void undoMerge() {
    if (readOnly) return;
    _positions[merger!.state] = resultEditor!.selection.extent;
    merger!.undo();
    _setMergeState();
  }

  void redoMerge() {
    if (readOnly) return;
    _positions[merger!.state] = resultEditor!.selection.extent;
    merger!.redo();
    _setMergeState();
  }

  void _setMergeState() {
    _programmatic = true;
    final position = _positions[merger!.state];
    if (resultEditor!.text != merger!.state.text) {
      resultEditor!.text = merger!.state.text;
    }
    if (position != null) {
      final line = position.index.clamp(0, resultEditor!.lineCount - 1);
      resultEditor!.selection = CodeLineSelection.collapsed(
        index: line,
        offset: position.offset.clamp(
          0,
          resultEditor!.codeLines[line].text.length,
        ),
      );
    }
    _lastResult = resultEditor!.text;
    updateResultLayout();
    _programmatic = false;
    notifyListeners();
  }

  void updateResultLayout() {
    if (resultEditor == null) return;
    final length = resultEditor!.lineCount;
    final colors = <int, Color>{};
    for (final r in merger!.state.regions) {
      for (var i = r.start; i < r.end && i < length; i++) {
        colors[i] = r.resolved ? addedBg : const Color(0xff3c3020);
      }
    }
    resultEditor!.diffLayout = CodeDiffLayout(
      lineRows: List.generate(length, (i) => i),
      totalRows: length,
      rowColors: colors,
      showWhitespace: showWhitespace,
    );
  }

  Future<void> saveResult({
    String? destination,
    bool backup = true,
    bool force = false,
    TextEncoding? encoding,
    String? eol,
    bool usePendingFormat = true,
  }) async {
    if (readOnly) throw StateError('当前为只读模式');
    if (pending > 0) throw StateError('还有 $pending 处冲突未处理');
    output ??= (TextFile.empty(base?.original ?? right.original)
      ..encoding = (base ?? right).encoding);
    final snapshot = resultEditor!.text;
    final pendingEncoding = saveEncodings[2], pendingEol = saveEols[2];
    final saveEncoding =
        encoding ?? (usePendingFormat ? pendingEncoding : null);
    final saveEol = eol ?? (usePendingFormat ? pendingEol : null);
    await output!.save(
      snapshot,
      destination: destination,
      backup: backup,
      overwriteExternal: force,
      asEncoding: saveEncoding,
      forcedEol: saveEol,
    );
    _savedResult = snapshot;
    savedMerge = true;
    if (saveEncodings[2] == pendingEncoding) saveEncodings.remove(2);
    if (saveEols[2] == pendingEol) saveEols.remove(2);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    leftEditor.dispose();
    rightEditor.dispose();
    resultEditor?.dispose();
    super.dispose();
  }
}

Future<CompareResult> _runComparison(CompareTask task) =>
    compute(runCompareTask, task, debugLabel: 'fmerge.compare');

/// 光标移动时复用判断；只有正文或保存基线变化才重新规范化、比较全文。
class _InputChange {
  String? _edited, _original;
  bool _changed = false;

  bool changed(String edited, String original) {
    if (!identical(edited, _edited) || !identical(original, _original)) {
      _changed = edited != normalize(original);
      _edited = edited;
      _original = original;
    }
    return _changed;
  }
}
