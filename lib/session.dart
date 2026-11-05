import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart' show Color;
import 'package:re_editor/re_editor.dart';

import 'core/diff.dart';
import 'core/editor_changes.dart';
import 'core/diff_navigation.dart';
import 'core/compare_task.dart';
import 'core/compare_worker.dart';
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
    this.compareRunner,
    MergePlan? initialPlan,
  }) {
    leftEditor = CodeLineEditingController.fromText(left.text);
    rightEditor = CodeLineEditingController.fromText(right.text);
    if (base != null) {
      merger = MergeSession(
        initialPlan ?? planMerge(base!.text, left.text, right.text),
      );
      resultEditor = CodeLineEditingController.fromText(merger!.state.text);
      resultEditor!.addListener(_resultChanged);
    }
    _lastLeft = leftEditor.codeLines;
    _lastRight = rightEditor.codeLines;
    _lastLeftSelection = leftEditor.selection;
    _lastRightSelection = rightEditor.selection;
    _leftChange.seed(left.original, leftEditor.codeLines);
    if (isMerge || output == null) {
      _rightChange.seed(right.original, rightEditor.codeLines);
    }
    leftEditor.addListener(_inputChanged);
    rightEditor.addListener(_inputChanged);
    _lastResultLines = resultEditor?.codeLines;
    _savedResult = output?.text ?? '';
  }
  AppPalette palette = palettes[ColorTheme.fmergeDark]!;

  void setPalette(AppPalette value) {
    if (palette == value) return;
    palette = value;
    // 只重建显示颜色，保留比较结果、折叠状态、选择及撤销历史。
    final current = diff;
    final alignment = mergeAlignment;
    final branches = branchDiffs;
    if (current != null) {
      if (alignment != null && branches != null) {
        _fullLeft = _branchLayout(branches[0], alignment.localRows, true);
        _fullRight = _branchLayout(branches[1], alignment.remoteRows, false);
      } else {
        _fullLeft = _layout(current, true);
        _fullRight = _layout(current, false);
      }
      _applyLayouts();
    }
    updateResultLayout();
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
  List<DiffDocument>? branchDiffs;
  List<List<InlineTarget>> _inlineTargets = const [[], []];
  bool get comparisonCurrent =>
      diff != null && !busy && error == null && _timer?.isActive != true;
  List<InlineTarget> inlineChanges(int side) =>
      comparisonCurrent ? _inlineTargets[side] : const [];

  /// 移动提示只用于双栏精确匹配，不改变差异块的采用语义。
  int? movedCounterpart(int side, int line) {
    if (!comparisonCurrent || isMerge) return null;
    for (final block in diff!.movedBlocks) {
      final start = side == 0 ? block.leftStart : block.rightStart;
      if (line >= start && line < start + block.length) {
        return (side == 0 ? block.rightStart : block.leftStart) + line - start;
      }
    }
    return null;
  }

  /// 始终使用未折叠的映射，避免把折叠提示或虚拟占位当作真实文本。
  int? fullRow(int side, int line) {
    final rows = (side == 0 ? _fullLeft : _fullRight)?.lineRows;
    return rows != null && line >= 0 && line < rows.length ? rows[line] : null;
  }

  DiffRow? lineDetails(int side, int line) {
    if (!comparisonCurrent) return null;
    final row = fullRow(side, line);
    if (row == null) return null;
    if (!isMerge) return diff!.rows[row];
    final a = lineAtRow(mergeAlignment!.localRows, row);
    final b = lineAtRow(mergeAlignment!.remoteRows, row);
    return _inputDetails(a, b);
  }

  DiffRow _inputDetails(int? a, int? b) {
    List<TextRangeMark> marks(CodeDiffLayout? layout, int? line) => [
      if (line != null)
        for (final range in layout?.ranges[line] ?? const <CodeDiffRange>[])
          TextRangeMark(range.start, range.end),
    ];
    return DiffRow(
      leftLine: a,
      rightLine: b,
      left: a == null ? null : leftEditor.codeLines[a].text,
      right: b == null ? null : rightEditor.codeLines[b].text,
      leftMarks: marks(_fullLeft, a),
      rightMarks: marks(_fullRight, b),
    );
  }

  DiffRow? conflictDetails(int resultLine) {
    if (!comparisonCurrent || !isMerge) return null;
    final regions = merger!.state.regions.where(
      (r) =>
          resultLine >= r.start &&
          (resultLine < r.end || r.start == r.end && resultLine == r.start),
    );
    if (regions.isEmpty) return null;
    final chunk = regions.first.chunk;
    int? inputLine(int side) {
      if ((side == 0 ? chunk.left : chunk.right).isEmpty) return null;
      var delta = 0;
      for (final change in branchDiffs![side].changes) {
        if (change.aStart > chunk.start) break;
        if (change.aEnd > chunk.start || change.aStart == chunk.start) {
          return change.bStart;
        }
        delta += change.bEnd - change.bStart - (change.aEnd - change.aStart);
      }
      return chunk.start + delta;
    }

    return _inputDetails(inputLine(0), inputLine(1));
  }

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
  late CodeLines _lastLeft, _lastRight;
  late String _savedResult;
  CodeLines? _lastResultLines;
  late CodeLineSelection _lastLeftSelection, _lastRightSelection;
  Timer? _timer;
  final CompareRunner? compareRunner;
  Future<void>? _refreshTask;
  bool _refreshPending = false;
  var _generation = 0;
  CompareOptions options = const CompareOptions();
  int revision = 0;
  bool showWhitespace = false;
  bool contextOnly = false;
  int contextLines = 3;
  ContextRows? _context;
  CodeDiffLayout? _fullLeft, _fullRight;
  final inputWrap = CodeDiffWrap();
  final _leftChange = _InputChange(), _rightChange = _InputChange();

  void swapSides() {
    if (isMerge || output != null || busy) return;
    revision++;
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
    _lastLeft = leftEditor.codeLines;
    _lastRight = rightEditor.codeLines;
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
        ? ContextRows(
            diff!.rows.length,
            {for (final entry in diff!.changedRows) entry.$1},
            context: contextLines,
            placeholderRows: 2,
          )
        : null;
    CodeDiffLayout project(CodeDiffLayout layout, int side) {
      final map = _context;
      if (map == null) return layout;
      return CodeDiffLayout(
        lineRows: [for (final row in layout.lineRows) map.rows[row]],
        totalRows: map.totalRows,
        hiddenLines: map.projectHidden(layout.lineRows),
        visibleLines: [
          for (var i = 0; i < layout.lineRows.length; i++)
            if (!map.hidden.contains(layout.lineRows[i])) i,
        ],
        rowLabels: map.labelsFor(layout.lineRows),
        placeholderRows: map.placeholderRows,
        placeholderColor: palette.accent,
        onRevealHidden: (row) => revealHiddenContext(side, row),
        rowColors: {
          for (final entry in layout.rowColors.entries)
            if (!map.hidden.contains(entry.key))
              map.rows[entry.key]: entry.value,
        },
        ranges: layout.ranges,
        showWhitespace: layout.showWhitespace,
        wrap: inputWrap,
      );
    }

    leftEditor.diffLayout = project(_fullLeft!, 0);
    rightEditor.diffLayout = project(_fullRight!, 1);
    _programmatic = false;
  }

  /// 省略带进入全文，并定位所点击范围的第一条真实行；不改写下次打开的折叠偏好。
  void revealHiddenContext(int side, int displayRow) {
    if (_disposed || !contextOnly || !comparisonCurrent) return;
    final range = _context?.hiddenRanges[displayRow];
    if (range == null) return;
    final full = side == 0 ? _fullLeft : _fullRight;
    final controller = side == 0 ? leftEditor : rightEditor;
    final line = full?.lineRows.indexWhere((row) => row >= range.$1) ?? -1;
    setContextOnly(false);
    final target = line < 0 ? controller.lineCount - 1 : line;
    controller.selection = CodeLineSelection.collapsed(
      index: target,
      offset: 0,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && controller.selection.extentIndex == target) {
        controller.makeCursorCenterIfInvisible();
      }
    });
  }

  void setShowWhitespace(bool value) {
    showWhitespace = value;
    CodeDiffLayout? update(CodeDiffLayout? layout) => layout == null
        ? null
        : CodeDiffLayout(
            lineRows: layout.lineRows,
            totalRows: layout.totalRows,
            hiddenLines: layout.hiddenLines,
            visibleLines: layout.visibleLines,
            rowLabels: layout.rowLabels,
            placeholderRows: layout.placeholderRows,
            placeholderColor: layout.placeholderColor,
            onRevealHidden: layout.onRevealHidden,
            rowColors: layout.rowColors,
            ranges: layout.ranges,
            showWhitespace: value,
            wrap: inputWrap,
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
      _leftChange.changed(leftEditor.codeLines, left.original) ||
      saveEncodings.containsKey(0) ||
      saveEols.containsKey(0);
  bool get rightDirty =>
      _rightChange.changed(
        rightEditor.codeLines,
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
  Map<String, dynamic> recoverySnapshot() => {
    'left': left.snapshot(),
    'right': right.snapshot(),
    'base': base?.snapshot(),
    'output': output?.snapshot(),
    'leftText': leftEditor.text,
    'rightText': rightEditor.text,
    'resultText': resultEditor?.text,
    'regions': [
      for (final r in merger?.state.regions ?? <ConflictRegion>[])
        {
          'id': r.chunk.id,
          'start': r.start,
          'end': r.end,
          'resolved': r.resolved,
          // 保存原冲突来源，恢复不重新运行有时间预算的算法，避免块编号漂移。
          'chunk': {
            'id': r.chunk.id,
            'start': r.chunk.start,
            'end': r.chunk.end,
            'base': r.chunk.base,
            'left': r.chunk.left,
            'right': r.chunk.right,
          },
        },
    ],
    'encodings': {
      for (final e in saveEncodings.entries) '${e.key}': e.value.name,
    },
    'eols': {for (final e in saveEols.entries) '${e.key}': e.value},
  };

  static Future<CompareSession> recover(Map<String, dynamic> data) async {
    TextFile file(String key) =>
        TextFile.fromSnapshot(data[key] as Map<String, dynamic>);
    final left = file('left'), right = file('right');
    final base = data['base'] == null ? null : file('base');
    final plan = base == null ? null : const MergePlan([], []);
    final session = CompareSession(
      left,
      right,
      base: base,
      output: data['output'] == null ? null : file('output'),
      initialPlan: plan,
    );
    try {
      session._programmatic = true;
      session.leftEditor.text = data['leftText'] as String;
      session.rightEditor.text = data['rightText'] as String;
      if (plan != null) {
        final text = data['resultText'] as String;
        final length = splitLines(text).length;
        MergeChunk chunk(Map<String, dynamic> raw) => MergeChunk(
          raw['id'] as int,
          raw['start'] as int,
          raw['end'] as int,
          (raw['base'] as List).cast<String>(),
          (raw['left'] as List).cast<String>(),
          (raw['right'] as List).cast<String>(),
          true,
          const [],
        );
        final regions = [
          for (final raw in data['regions'] as List)
            ConflictRegion(
              chunk(raw['chunk'] as Map<String, dynamic>),
              raw['start'] as int,
              raw['end'] as int,
              raw['resolved'] as bool,
            ),
        ];
        if (regions.map((r) => r.chunk.id).toSet().length != regions.length ||
            regions.any(
              (r) => r.start < 0 || r.end < r.start || r.end > length,
            )) {
          throw const FormatException('恢复记录的冲突范围无效');
        }
        session.merger = MergeSession.restore(MergeSnapshot(text, regions));
        session.resultEditor!.text = text;
        session._lastResultLines = session.resultEditor!.codeLines;
        session.updateResultLayout();
      }
      for (final e in (data['encodings'] as Map).entries) {
        final side = int.parse(e.key as String);
        if (side < 0 || side > 2) throw const FormatException('恢复编码侧别无效');
        session.saveEncodings[side] = TextEncoding.values.byName(
          e.value as String,
        );
      }
      for (final e in (data['eols'] as Map).entries) {
        if (!['\n', '\r', '\r\n'].contains(e.value)) {
          throw const FormatException('恢复换行格式无效');
        }
        session.saveEols[int.parse(e.key as String)] = e.value as String;
      }
      session._lastLeft = session.leftEditor.codeLines;
      session._lastRight = session.rightEditor.codeLines;
      session._programmatic = false;
      return session;
    } catch (_) {
      session.dispose();
      rethrow;
    }
  }

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
    final plan = args.merge
        ? await Isolate.run(
            () => planMerge(files[2].text, files[0].text, files[1].text),
          )
        : null;
    return CompareSession(
      files[0],
      files[1],
      mergeLabels: labels,
      base: files.length == 3 ? files[2] : null,
      output: output,
      readOnly: args.readOnly,
      initialPlan: plan,
    );
  }

  void _inputChanged() {
    if (_programmatic || _disposed) return;
    final a = leftEditor.codeLines, b = rightEditor.codeLines;
    final movedLeft = _lastLeftSelection != leftEditor.selection;
    final movedRight = _lastRightSelection != rightEditor.selection;
    _lastLeftSelection = leftEditor.selection;
    _lastRightSelection = rightEditor.selection;
    if (a.contentEquals(_lastLeft) && b.contentEquals(_lastRight)) {
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
    revision++;
    schedule();
    notifyListeners();
  }

  void _resultChanged() {
    if (_programmatic || _disposed) return;
    final lines = resultEditor!.codeLines;
    if (lines.contentEquals(_lastResultLines!)) {
      _positions[merger!.state] = resultEditor!.selection.extent;
      return;
    }
    final changes = editorChanges(_lastResultLines!, lines);
    final text = resultEditor!.text;
    _lastResultLines = lines;
    _positions[merger!.state] =
        resultEditor!.preValue?.selection.extent ??
        resultEditor!.selection.extent;
    revision++;
    merger!.edit(text, changes: changes, lineCount: lines.lineCount);
    _positions[merger!.state] = resultEditor!.selection.extent;
    updateResultLayout();
    notifyListeners();
  }

  void inputSaved({int? side}) {
    revision++;
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
    revision++;
    notifyListeners();
  }

  void setSaveEol(int side, String? eol) {
    if (readOnly || isMerge && side != 2) return;
    revision++;
    if (eol == null) {
      saveEols.remove(side);
    } else {
      saveEols[side] = eol;
    }
    notifyListeners();
  }

  void reloadInput(int side, TextFile file) {
    if (isMerge) throw StateError('合并输入需重新创建合并会话');
    revision++;
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
        var generation = _generation;
        try {
          CompareTask snapshot() {
            // 等待全局计算槽期间的新请求一起合并，代次与真正读取的正文一致。
            generation = _generation;
            _refreshPending = false;
            _timer?.cancel();
            return CompareTask(
              left: leftEditor.text,
              right: rightEditor.text,
              options: options,
              leftOriginal: options.ignoreEol ? null : left.original,
              rightOriginal: options.ignoreEol ? null : right.original,
              base: base?.original,
            );
          }

          final runner = compareRunner;
          final result = await (runner == null
              ? compareWorker.run(this, snapshot)
              : runner(snapshot()));
          if (_disposed || generation != _generation) continue;
          diff = result.diff;
          branchDiffs = result.branches;
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
            _inlineTargets = [
              for (var side = 0; side < 2; side++)
                if (!isMerge)
                  inlineTargets(result.diff, side)
                else
                  [
                    for (final (line, ranges)
                        in (side == 0 ? _fullLeft! : _fullRight!).ranges.entries
                            .map((e) => (e.key, e.value)))
                      for (final range in ranges)
                        InlineTarget(
                          side,
                          line,
                          range.start,
                          range.end,
                          fullRow(side, line)!,
                        ),
                  ],
            ];
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
    final rows = diff.lineRows(left),
        colors = <int, Color>{},
        ranges = <int, List<CodeDiffRange>>{};
    for (final (i, row) in diff.changedRows) {
      final line = left ? row.leftLine : row.rightLine;
      colors[i] = line == null
          ? palette.bg
          : (left ? palette.removedBg : palette.addedBg);
      final marks = left ? row.leftMarks : row.rightMarks;
      if (line != null && marks.isNotEmpty) {
        ranges[line] = [
          for (final m in marks)
            CodeDiffRange(
              m.start,
              m.end,
              left ? palette.removedInline : palette.addedInline,
            ),
        ];
      }
    }
    for (final block in diff.movedBlocks) {
      final start = left ? block.leftStart : block.rightStart;
      for (var i = 0; i < block.length; i++) {
        colors[rows[start + i]] = palette.movedBg;
      }
    }
    return CodeDiffLayout(
      lineRows: rows,
      totalRows: diff.rows.length,
      rowColors: colors,
      ranges: ranges,
      showWhitespace: showWhitespace,
      wrap: inputWrap,
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
      if (row.changed) {
        colors[rows[line]] = local ? palette.removedBg : palette.addedBg;
      }
      if (row.rightMarks.isEmpty) continue;
      ranges[line] = [
        for (final mark in row.rightMarks)
          CodeDiffRange(
            mark.start,
            mark.end,
            local ? palette.removedInline : palette.addedInline,
          ),
      ];
    }
    final realRows = rows.toSet();
    for (var i = 0; i < mergeAlignment!.totalRows; i++) {
      if (!realRows.contains(i)) colors[i] = palette.bg;
    }
    return CodeDiffLayout(
      lineRows: rows,
      totalRows: mergeAlignment!.totalRows,
      rowColors: colors,
      ranges: ranges,
      showWhitespace: showWhitespace,
      wrap: inputWrap,
    );
  }

  void applyHunk(int hunk, {bool toRight = true, int combine = 0}) {
    if (readOnly ||
        diff == null ||
        hunk < 0 ||
        hunk >= diff!.changes.length ||
        !comparisonCurrent) {
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
    revision++;
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
    revision++;
    final position = resultEditor!.selection.extent;
    _positions[merger!.state] = position;
    merger!.markResolved(id, resolved);
    _positions[merger!.state] = position;
    _setMergeState();
  }

  void undoMerge() {
    if (readOnly) return;
    revision++;
    _positions[merger!.state] = resultEditor!.selection.extent;
    merger!.undo();
    _setMergeState();
  }

  void redoMerge() {
    if (readOnly) return;
    revision++;
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
    _lastResultLines = resultEditor!.codeLines;
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
        colors[i] = r.resolved ? palette.addedBg : palette.conflictBg;
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
    compareWorker.cancel(this);
    _timer?.cancel();
    leftEditor.dispose();
    rightEditor.dispose();
    resultEditor?.dispose();
    super.dispose();
  }
}

/// 复用保存基线的分段文档，局部输入只比较实际改变的段，不读取全文字符串。
class _InputChange {
  String? _original;
  CodeLines? _baseline, _edited;
  bool _changed = false;

  void seed(String original, CodeLines baseline) {
    _original = original;
    _baseline = _edited = baseline;
    _changed = false;
  }

  bool changed(CodeLines edited, String original) {
    if (!identical(original, _original)) {
      _original = original;
      _baseline = CodeLines.fromText(normalize(original));
      _edited = null;
    }
    if (!identical(edited, _edited)) {
      _changed = !edited.contentEquals(_baseline!);
      _edited = edited;
    }
    return _changed;
  }
}
