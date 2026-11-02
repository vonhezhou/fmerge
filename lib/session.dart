import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:re_editor/re_editor.dart';

import 'core/diff.dart';
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
  }) {
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
  var _generation = 0;
  CompareOptions options = const CompareOptions();
  bool showWhitespace = false;
  bool contextOnly = false;
  ContextRows? _context;
  CodeDiffLayout? _fullLeft, _fullRight;

  void swapSides() {
    if (isMerge || output != null || busy) return;
    final file = left;
    left = right;
    right = file;
    final language = leftLanguage;
    leftLanguage = rightLanguage;
    rightLanguage = language;
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

  void setContextOnly(bool value) {
    contextOnly = value;
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
          })
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
  bool get leftDirty => leftEditor.text != left.text;
  bool get rightDirty =>
      rightEditor.text !=
      (!isMerge && output != null ? output!.text : right.text);
  bool get resultDirty =>
      isMerge &&
      (resultEditor!.text != _savedResult || !savedMerge || pending > 0);
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
  }) async {
    if (args.left == null) {
      return CompareSession(
        TextFile.empty(),
        TextFile.empty(),
        readOnly: args.readOnly,
      );
    }
    final files = await Future.wait([
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

  void inputSaved() {
    notifyListeners();
  }

  void schedule() {
    _generation++; // 输入一变化就使旧计算失效，而不是等下一次防抖触发。
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 140), refresh);
  }

  Future<void> refresh([CompareOptions? nextOptions]) async {
    if (_disposed) return;
    if (nextOptions != null) options = nextOptions;
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final inputs = DiffInput(
        left.materialize(leftEditor.text),
        right.materialize(rightEditor.text),
        options,
      );
      final result = await compute(compare, inputs);
      List<DiffDocument>? branches;
      if (isMerge) {
        branches = await compute(_compareBranches, (base!.original, inputs));
      }
      if (_disposed || generation != _generation) return;
      diff = result;
      _programmatic = true;
      if (branches != null) {
        mergeAlignment = alignThreeWay(branches[0], branches[1]);
        _fullLeft = _branchLayout(branches[0], mergeAlignment!.localRows, true);
        _fullRight = _branchLayout(
          branches[1],
          mergeAlignment!.remoteRows,
          false,
        );
      } else {
        _fullLeft = _layout(result, true);
        _fullRight = _layout(result, false);
      }
      _applyLayouts();
      _programmatic = false;
    } catch (e) {
      if (!_disposed && generation == _generation) error = e.toString();
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
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
      if (line != null) {
        ranges[line] = [
          for (final m in left ? row.leftMarks : row.rightMarks)
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
  }) async {
    if (readOnly) throw StateError('当前为只读模式');
    if (pending > 0) throw StateError('还有 $pending 处冲突未处理');
    output ??= (TextFile.empty(base?.original ?? right.original)
      ..encoding = (base ?? right).encoding);
    final snapshot = resultEditor!.text;
    await output!.save(
      snapshot,
      destination: destination,
      backup: backup,
      overwriteExternal: force,
      asEncoding: encoding,
      forcedEol: eol,
    );
    _savedResult = snapshot;
    savedMerge = true;
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

List<DiffDocument> _compareBranches((String, DiffInput) input) => [
  compare(DiffInput(input.$1, input.$2.left, input.$2.options)),
  compare(DiffInput(input.$1, input.$2.right, input.$2.options)),
];
