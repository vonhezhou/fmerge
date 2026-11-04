import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import '../core/access.dart';
import '../core/git.dart';
import '../core/files.dart';
import '../core/diff_navigation.dart';
import '../core/diff.dart' show InlineDiffMode;
import '../core/launch.dart';
import '../core/merge.dart';
import '../core/merge_labels.dart';
import '../core/settings.dart';
import '../core/shortcuts.dart';
import '../session.dart';
import '../palette.dart';
import 'code_pane.dart';
import 'document_status.dart';
import 'diff_overview.dart';
import 'line_details.dart';
import 'toolbar_action.dart';
import 'settings_dialog.dart';
import 'format_dialog.dart';
import 'go_to_line_dialog.dart';
import 'base_dialog.dart';
import 'welcome_view.dart';

class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.settings,
    this.initial,
    this.options = const LaunchOptions(),
    this.startupError,
    this.nativeWindow = false,
    this.onExit,
  });
  final Settings settings;
  final CompareSession? initial;
  final LaunchOptions options;
  final String? startupError;
  final bool nativeWindow;
  final ValueChanged<int>? onExit;
  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> with WindowListener {
  CompareSession? session;
  final _leftFocus = FocusNode(),
      _rightFocus = FocusNode(),
      _resultFocus = FocusNode();
  final _leftScroll = CodeScrollController(),
      _rightScroll = CodeScrollController(),
      _resultScroll = CodeScrollController();
  CodeFindController? _leftFind, _rightFind, _resultFind;
  bool _syncing = false,
      _leftEditable = false,
      _closing = false,
      _saving = false,
      _opening = false,
      _staging = false,
      _settingsOpen = false,
      _identifyingSource = false,
      _diskChanged = false;
  int _active = 1, _hunk = 0, _conflict = 0;
  double _topFraction = .50;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _notice = widget.startupError;
    settings.addListener(_appearanceChanged);
    _leftFocus.addListener(() => _focus(0));
    _rightFocus.addListener(() => _focus(1));
    _resultFocus.addListener(() => _focus(2));
    _leftScroll.verticalScroller.addListener(
      () => _sync(_leftScroll.verticalScroller, _rightScroll.verticalScroller),
    );
    _rightScroll.verticalScroller.addListener(
      () => _sync(_rightScroll.verticalScroller, _leftScroll.verticalScroller),
    );
    _leftScroll.horizontalScroller.addListener(
      () => _sync(
        _leftScroll.horizontalScroller,
        _rightScroll.horizontalScroller,
      ),
    );
    _rightScroll.horizontalScroller.addListener(
      () => _sync(
        _rightScroll.horizontalScroller,
        _leftScroll.horizontalScroller,
      ),
    );
    if (widget.nativeWindow) {
      windowManager.addListener(this);
      const MethodChannel('fmerge/lifecycle')
          .setMethodCallHandler((call) async {
            if (call.method == 'requestClose') {
              await _close();
              return false;
            }
            return null;
          });
    }
    if (widget.initial != null) _attach(widget.initial!);
  }

  Settings get settings => widget.settings;
  AppPalette _palette = palettes[ColorTheme.fmergeDark]!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _palette = AppPalette.of(context);
    session?.setPalette(_palette);
    _appearanceChanged();
  }

  (AppPalette, ThemeMode)? _nativeAppearance;
  void _appearanceChanged() {
    if (!widget.nativeWindow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final appearance = (_palette, settings.themeMode);
      if (_nativeAppearance == appearance) return;
      _nativeAppearance = appearance;
      try {
        if (Platform.isMacOS) {
          await const MethodChannel('fmerge/appearance')
              .invokeMethod<void>('setMode', settings.themeMode.name);
        } else {
          await windowManager.setBrightness(_palette.brightness);
        }
        await windowManager.setBackgroundColor(_palette.bg);
      } catch (error) {
        if (mounted) _message('更新窗口外观失败：$error');
      }
    });
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || from.positions.length != 1 || to.positions.length != 1) {
      return;
    }
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  void _focus(int index) {
    if ((index == 0
                ? _leftFocus
                : index == 1
                ? _rightFocus
                : _resultFocus)
            .hasFocus &&
        mounted) {
      setState(() => _active = index);
    }
  }

  CodeLineEditingController? get editor => session == null
      ? null
      : _active == 0
      ? session!.leftEditor
      : _active == 2
      ? session!.resultEditor
      : session!.rightEditor;
  CodeFindController? get finder => _active == 0
      ? _leftFind
      : _active == 2
      ? _resultFind
      : _rightFind;
  void _attach(CompareSession next) {
    final old = session;
    old?.removeListener(_changed);
    _leftFind?.dispose();
    _rightFind?.dispose();
    _resultFind?.dispose();
    session = next;
    next.setPalette(_palette);
    _leftFind = CodeFindController(next.leftEditor);
    _rightFind = CodeFindController(next.rightEditor);
    _leftFind!.addListener(_findChanged);
    _rightFind!.addListener(_findChanged);
    _resultFind = next.resultEditor == null
        ? null
        : CodeFindController(next.resultEditor!);
    _active = next.isMerge ? 2 : 1;
    _hunk = 0;
    _conflict = 0;
    _leftEditable =
        next.left.text.isEmpty && next.right.text.isEmpty && !next.isMerge;
    _diskChanged = false;
    next.addListener(_changed);
    next.setShowWhitespace(settings.showWhitespace);
    next.setContextOnly(
      settings.contextOnly && !next.isMerge,
      context: settings.contextLines,
    );
    next.refresh(settings.comparison);
    settings.remember(
      next.left.path,
      next.right.path,
      next.base?.path,
      next.output?.path,
    );
    _saveSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(session, next)) {
        (next.isMerge ? _resultFocus : _rightFocus).requestFocus();
      }
    });
    // 延后销毁旧控制器，让旧编辑视图先退出树。
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
      });
    }
  }

  Future<void> _saveSettings() async {
    try {
      await settings.save();
    } catch (e) {
      if (mounted) _message('设置保存失败：$e');
    }
  }

  void _findChanged() {
    if (mounted) setState(() {});
  }

  double get _sharedFindHeight {
    double height(CodeFindController? c) => c?.value == null
        ? 0
        : c!.value!.replaceMode
        ? 84
        : 44;
    final a = height(_leftFind), b = height(_rightFind);
    return a > b ? a : b;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (session?.diff != null) {
        _hunk = _hunk.clamp(
          0,
          (session!.hunkRows.length - 1).clamp(0, 1 << 30),
        );
      }
    });
    if (widget.nativeWindow) {
      windowManager.setTitle(
        '${session!.dirty ? '● ' : ''}fmerge · ${session!.isMerge ? '三方合并' : session!.right.name}',
      );
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _leave() async {
    if (session?.dirty != true) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有尚未保存的修改'),
        content: Text(
          session!.pending > 0
              ? '还有 ${session!.pending} 处冲突未确认。离开会丢弃当前结果。'
              : '离开前保存修改？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: session!.pending > 0
                ? null
                : () => Navigator.pop(context, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (choice == 'discard') return true;
    if (choice != 'save') return false;
    if (session!.isMerge) return _save();
    if (session!.leftDirty && !await _save(side: 0)) return false;
    if (session!.rightDirty && !await _save(side: 1)) return false;
    return true;
  }

  @override
  void onWindowClose() {
    _close();
  }

  Future<void> _close() async {
    if (_closing || _saving || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _closing = true;
    if (!await _leave()) {
      _closing = false;
      return;
    }
    final code = session?.toolExitCode ?? (widget.startupError == null ? 0 : 1);
    if (widget.onExit != null) {
      widget.onExit!(code);
      _closing = false;
      return;
    }
    if (widget.nativeWindow) {
      await windowManager.setPreventClose(false);
      // 本工具每次调用拥有独立进程；直接以结果状态退出，让 Git 得到准确退出码。
      exit(code);
    }
    _closing = false;
  }

  @override
  void onWindowFocus() {
    _checkDisk();
  }

  Future<void> _checkDisk() async {
    final current = session;
    if (current == null) return;
    try {
      var changed = false;
      for (final file in [
        current.left,
        current.right,
        if (current.base != null) current.base!,
        if (current.output != null) current.output!,
      ]) {
        if (file.path == null || file.digest == null) continue;
        final disk = File(file.path!);
        if (!await disk.exists() ||
            sha256.convert(await disk.readAsBytes()).toString() !=
                file.digest) {
          changed = true;
        }
      }
      if (mounted && current == session) setState(() => _diskChanged = changed);
    } catch (_) {
      /* 保存路径仍执行独立外部改动校验，焦点检查不打断编辑。 */
    }
  }

  Future<TextFile?> _readInput(String path, TextEncoding? encoding) async {
    while (mounted) {
      try {
        return await TextFile.read(path, encoding: encoding);
      } on FormatException catch (error) {
        if (error.message.contains('32 MiB') || error.message.contains('二进制')) {
          rethrow;
        }
        if (!mounted) return null;
        encoding = await showDialog<TextEncoding>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text('无法读取 ${File(path).uri.pathSegments.last}，请选择编码'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error.message,
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final value in TextEncoding.values)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, value),
                  child: Text(value.label),
                ),
            ],
          ),
        );
        if (encoding == null) return null;
      }
    }
    return null;
  }

  Future<void> _open({
    LaunchOptions? options,
    CompareSession? previous,
    int? encodingSide,
    TextEncoding? encoding,
  }) async {
    if (_opening || _saving) return;
    setState(() => _opening = true);
    try {
      if (!await _leave() || !mounted) return;
      if (options == null) {
        final files = await openFiles(confirmButtonText: '选择比较文件（可多选两个）');
        if (files.isEmpty || !mounted) return;
        if (files.length > 2) {
          _message('一次比较两个文件，请选择两个文件');
          return;
        }
        if (widget.nativeWindow) {
          await DirectoryAccess.rememberFiles(files.map((file) => file.path));
        }
        var right = files.length == 2 ? files[1] : null;
        if (right == null) {
          right = await openFile(
            initialDirectory: File(files.first.path).parent.path,
            confirmButtonText: '选择右侧文件',
          );
          if (right == null) return;
          if (widget.nativeWindow) {
            await DirectoryAccess.rememberFiles([right.path]);
          }
        }
        options = LaunchOptions(left: files.first.path, right: right.path);
      }
      if (widget.nativeWindow) {
        for (final path in [
          options.left!,
          options.right!,
          if (options.base != null) options.base!,
        ]) {
          await DirectoryAccess.read(path);
        }
        if (options.output != null) {
          await DirectoryAccess.write(options.output!);
        }
      }
      final left = await _readInput(
        options.left!,
        encodingSide == 0 ? encoding : previous?.left.encoding,
      );
      if (left == null) return;
      final right = await _readInput(
        options.right!,
        encodingSide == 1 ? encoding : previous?.right.encoding,
      );
      if (right == null) return;
      final base = options.base == null
          ? null
          : await _readInput(
              options.base!,
              encodingSide == 3 ? encoding : previous?.base?.encoding,
            );
      if (options.base != null && base == null) return;
      final next = await CompareSession.open(
        options,
        inputs: [left, right, ?base],
        leftEncoding: left.encoding,
        rightEncoding: right.encoding,
        baseEncoding: base?.encoding,
        outputEncoding: previous?.output?.encoding,
      );
      if (previous != null) {
        next.leftEditor.displayTabSize = previous.leftEditor.displayTabSize;
        next.rightEditor.displayTabSize = previous.rightEditor.displayTabSize;
        if (next.resultEditor != null) {
          next.resultEditor!.displayTabSize =
              previous.resultEditor?.displayTabSize ?? 4;
        }
        next.leftLanguage = previous.leftLanguage;
        next.rightLanguage = previous.rightLanguage;
        next.resultLanguage = previous.resultLanguage;
        next.baseLanguage = previous.baseLanguage;
      }
      if (mounted) {
        setState(() => _attach(next));
      } else {
        next.dispose();
      }
    } catch (e) {
      _message('打开失败：$e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _reload() async {
    final s = session;
    if (s == null) return;
    if (s.left.path == null || s.right.path == null) {
      _message('当前为未命名文本，无法从磁盘重新加载');
      return;
    }
    await _open(
      previous: s,
      options: LaunchOptions(
        left: s.left.path,
        right: s.right.path,
        base: s.base?.path,
        output: s.output?.path,
        readOnly: s.readOnly,
      ),
    );
  }

  Future<bool> _save({
    int? side,
    bool saveAs = false,
    bool force = false,
    String? destinationOverride,
    SaveFormat? format,
  }) async {
    final s = session;
    if (s == null ||
        _saving ||
        s.readOnly ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    if ((s.isMerge ? s.resultEditor : editor)?.isComposing == true) {
      _message('请先完成输入法输入，再保存');
      return false;
    }
    if (s.isMerge && s.pending > 0) {
      _message('请先确认剩余 ${s.pending} 处冲突');
      return false;
    }
    final targetSide =
        side ?? (_active == 0 && !_leftEditable && !s.isMerge ? 1 : _active);
    final file = s.isMerge
        ? s.output
        : (targetSide == 0 ? s.left : (s.output ?? s.right));
    String? destination = destinationOverride;
    if (saveAs && format == null) {
      format = await showDialog<SaveFormat>(
        context: context,
        builder: (_) => FormatDialog(
          encoding:
              s.saveEncodings[s.isMerge ? 2 : targetSide] ??
              file?.encoding ??
              TextEncoding.utf8,
          eol: s.saveEols[s.isMerge ? 2 : targetSide],
        ),
      );
      if (format == null || !mounted) return false;
    }
    if (destination == null && (saveAs || file?.path == null)) {
      final location = await getSaveLocation(
        suggestedName: s.isMerge ? 'merged-${s.left.name}' : file!.name,
        confirmButtonText: '保存',
      );
      if (location == null) return false;
      destination = location.path;
    }
    final formatSide = s.isMerge ? 2 : targetSide;
    // 未显式转换编码时传 null，让文件模型保留 UTF-16 无 BOM 等原始格式。
    final saveEncoding = format?.encoding ?? s.saveEncodings[formatSide];
    final saveEol = format == null ? s.saveEols[formatSide] : format.eol;
    setState(() => _saving = true);
    try {
      final targetPath = destination ?? file?.path;
      if (widget.nativeWindow && targetPath != null) {
        await DirectoryAccess.write(targetPath);
      }
      if (s.isMerge) {
        await s.saveResult(
          destination: destination,
          backup: settings.backup,
          force: force,
          encoding: saveEncoding,
          eol: saveEol,
          usePendingFormat: format == null,
        );
      } else {
        final output = targetSide == 0 ? s.leftEditor : s.rightEditor;
        // 比较模式的 --output 指定右侧另存目标，绝不意外覆盖 Git 临时输入。
        final specified = targetSide != 0 ? s.output?.path : null;
        await file!.save(
          output.text,
          destination: destination ?? specified,
          backup: settings.backup,
          overwriteExternal: force,
          asEncoding: saveEncoding,
          forcedEol: saveEol,
        );
      }
      s.inputSaved(side: formatSide);
      if (!mounted) return true;
      setState(() => _diskChanged = false);
      _message('已保存 ${s.isMerge ? s.output!.name : file!.name}');
      if (widget.options.autoClose && widget.nativeWindow) {
        _saving = false;
        await _close();
      }
      return true;
    } on FileConflict catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('磁盘文件已经改变'),
          content: Text('${e.path}\n\n为避免覆盖其他程序的修改，请选择处理方式。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'as'),
              child: const Text('另存为'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'force'),
              child: const Text('覆盖磁盘版本'),
            ),
          ],
        ),
      );
      if (action == 'as') {
        return _save(side: side, saveAs: true, format: format);
      }
      if (action == 'force') {
        return _save(
          side: side,
          force: true,
          destinationOverride: destination,
          format: format,
        );
      }
      return false;
    } catch (e) {
      _message('保存失败：$e');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editAction(Intent code, {Intent? text}) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return;
    if (Actions.maybeFind<Intent>(focused, intent: code) != null) {
      Actions.maybeInvoke(focused, code);
    } else if (text != null) {
      Actions.maybeInvoke(focused, text);
    }
  }

  bool get _activeReadOnly =>
      session == null ||
      session!.readOnly ||
      (_active == 0 && (session!.isMerge || !_leftEditable)) ||
      (_active == 1 && session!.isMerge);
  void _undo() {
    final s = session;
    if (s == null || _activeReadOnly) return;
    if (_active == 2) {
      s.undoMerge();
    } else {
      editor?.undo();
    }
  }

  void _redo() {
    final s = session;
    if (s == null || _activeReadOnly) return;
    if (_active == 2) {
      s.redoMerge();
    } else {
      editor?.redo();
    }
  }

  void _navigate(int step, {bool conflicts = false}) {
    final s = session;
    if (s == null) return;
    if (conflicts && s.isMerge) {
      final regions = s.merger!.state.regions;
      if (regions.isEmpty) return;
      setState(() => _conflict = (_conflict + step) % regions.length);
      s.resultEditor!.selection = CodeLineSelection.collapsed(
        index: regions[_conflict].start.clamp(0, s.resultEditor!.lineCount - 1),
        offset: 0,
      );
      _resultScroll.makeVisible(
        CodeLinePosition(
          index: regions[_conflict].start.clamp(
            0,
            s.resultEditor!.lineCount - 1,
          ),
          offset: 0,
        ),
      );
      _resultFocus.requestFocus();
      return;
    }
    final rows = s.hunkRows;
    if (rows.isEmpty) return;
    setState(() => _hunk = (_hunk + step) % rows.length);
    final row = rows[_hunk];
    final leftRows = s.leftEditor.diffLayout?.lineRows ?? const <int>[];
    final rightRows = s.rightEditor.diffLayout?.lineRows ?? const <int>[];
    final a = leftRows.indexWhere((r) => r >= row),
        b = rightRows.indexWhere((r) => r >= row);
    if (b >= 0 && (a < 0 || rightRows[b] < leftRows[a])) {
      _rightScroll.makeVisible(
        CodeLinePosition(
          index: b.clamp(0, s.rightEditor.lineCount - 1),
          offset: 0,
        ),
      );
    } else if (a >= 0) {
      _leftScroll.makeVisible(
        CodeLinePosition(
          index: a.clamp(0, s.leftEditor.lineCount - 1),
          offset: 0,
        ),
      );
    }
  }

  void _swapSides() {
    final s = session;
    if (s == null || s.isMerge || s.output != null || s.busy || _saving) return;
    _leftFind?.dispose();
    _rightFind?.dispose();
    s.swapSides();
    _leftFind = CodeFindController(s.leftEditor)..addListener(_findChanged);
    _rightFind = CodeFindController(s.rightEditor)..addListener(_findChanged);
    setState(() {
      _active = 1 - _active;
      _hunk = 0;
      _leftEditable = !s.readOnly && s.leftDirty;
    });
  }

  void _navigateInline(int step) {
    final s = session;
    if (s == null || !s.comparisonCurrent) return;
    final side = _active == 0 ? 0 : 1;
    final source = side == 0 ? s.leftEditor : s.rightEditor;
    final selection = source.selection;
    final target = adjacentInlineTarget(
      s.inlineChanges(side),
      _active == 2 ? -1 : s.fullRow(side, selection.startIndex) ?? -1,
      _active == 2 ? -1 : selection.startOffset,
      step,
    );
    if (target == null) return;
    final controller = target.side == 0 ? s.leftEditor : s.rightEditor;
    controller.selection = CodeLineSelection(
      baseIndex: target.line,
      baseOffset: target.start,
      extentIndex: target.line,
      extentOffset: target.end,
    );
    (target.side == 0 ? _leftScroll : _rightScroll).makeVisible(
      CodeLinePosition(index: target.line, offset: target.start),
    );
    (target.side == 0 ? _leftFocus : _rightFocus).requestFocus();
    final hunk = s.hunkRows.lastIndexWhere(
      (row) => row <= (controller.diffLayout?.lineRows[target.line] ?? 0),
    );
    if (hunk >= 0) setState(() => _hunk = hunk);
  }

  void _seekOverview(double fraction) {
    final scroll = _leftScroll.verticalScroller;
    if (scroll.positions.length != 1 || !scroll.position.hasContentDimensions) {
      return;
    }
    final position = scroll.position;
    scroll.jumpTo(
      (fraction * (position.maxScrollExtent + position.viewportDimension) -
              position.viewportDimension / 2)
          .clamp(0, position.maxScrollExtent),
    );
  }

  void _toggleWhitespace() {
    settings.ignoreWhitespace = !settings.ignoreWhitespace;
    session?.refresh(settings.comparison);
    _saveSettings();
  }

  void _toggleWhitespaceCharacters() {
    settings.showWhitespace = !settings.showWhitespace;
    session?.setShowWhitespace(settings.showWhitespace);
    _saveSettings();
  }

  void _toggleContext() {
    final s = session;
    if (s == null || s.isMerge || s.busy) return;
    settings.contextOnly = !s.contextOnly;
    s.setContextOnly(settings.contextOnly, context: settings.contextLines);
    _saveSettings();
  }

  Future<void> _stageSelection(int side) async {
    final s = session;
    if (s == null || s.isMerge || s.readOnly || _staging || _saving) return;
    final file = side == 0 ? s.left : s.right;
    final controller = side == 0 ? s.leftEditor : s.rightEditor;
    final selection = controller.selection;
    final start = selection.startIndex;
    final end = selection.isCollapsed
        ? start + 1
        : selection.endIndex + (selection.end.offset == 0 ? 0 : 1);
    if (file.path == null) {
      _message('请先将当前文件保存到 Git 工作区');
      return;
    }
    if ((side == 0 ? s.leftDirty : s.rightDirty)) {
      _message('请先保存当前文件，再暂存所选代码块');
      return;
    }
    final text = controller.text;
    setState(() => _staging = true);
    try {
      final review = await GitReview.open(file.path!);
      final disk = await TextFile.read(file.path!, encoding: file.encoding);
      if (disk.text != text || controller.text != text) {
        throw StateError('文件内容已变化，请保存或重新加载后再暂存');
      }
      final hunks = review.patch.hunksForLines(start, end);
      if (hunks.isEmpty) {
        _message('所选行没有未暂存修改；请选择修改过的代码块');
        return;
      }
      await review.apply(hunks);
      _message('已暂存 ${hunks.length} 个 Git 差异块，其余修改保留在工作区');
    } catch (error) {
      if (!mounted) return;
      final permissions =
          widget.nativeWindow &&
          (error.toString().contains('Operation not permitted') ||
              error.toString().contains('Permission denied'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('暂存失败：$error'),
          action: permissions
              ? SnackBarAction(
                  label: '授权仓库',
                  onPressed: () async {
                    if (await DirectoryAccess.grant(
                          File(file.path!).parent.path,
                        ) &&
                        mounted &&
                        identical(session, s)) {
                      await _stageSelection(side);
                    }
                  },
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _staging = false);
    }
  }

  Future<void> _changeEncoding(int side, TextEncoding? encoding) async {
    final s = session;
    if (s == null || _saving || _opening) return;
    final file = side == 0
        ? s.left
        : side == 1
        ? s.right
        : side == 3
        ? s.base!
        : s.output;
    if (side == 2 || file?.path == null) {
      if (encoding != null) {
        try {
          s.setSaveEncoding(side, encoding);
        } catch (error) {
          _message('无法使用该编码保存：$error');
        }
      }
      return;
    }
    if (s.isMerge) {
      await _open(
        previous: s,
        encodingSide: side,
        encoding: encoding,
        options: LaunchOptions(
          left: s.left.path,
          right: s.right.path,
          base: s.base!.path,
          output: s.output?.path,
          readOnly: s.readOnly,
        ),
      );
      return;
    }
    final dirty = side == 0 ? s.leftDirty : s.rightDirty;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新按编码读取文件'),
          content: Text('${file!.name} 有未保存修改。重新读取会丢弃此文件的修改，另一侧保持不变。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('丢弃并重新读取'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted || !identical(s, session)) return;
    }
    setState(() => _opening = true);
    try {
      final next = await TextFile.read(file!.path!, encoding: encoding);
      if (mounted && identical(s, session)) s.reloadInput(side, next);
    } catch (error) {
      _message('重新读取失败：$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _settings({
    SettingsSection section = SettingsSection.comparison,
  }) async {
    if (_settingsOpen) return;
    final beforeContext = settings.contextOnly,
        beforeLines = settings.contextLines;
    setState(() => _settingsOpen = true);
    await showDialog(
      context: context,
      builder: (_) =>
          SettingsDialog(settings: settings, initialSection: section),
    );
    if (!mounted) return;
    setState(() => _settingsOpen = false);
    final s = session;
    if (s != null) {
      if (s.showWhitespace != settings.showWhitespace) {
        s.setShowWhitespace(settings.showWhitespace);
      }
      if (beforeContext != settings.contextOnly ||
          beforeLines != settings.contextLines) {
        s.setContextOnly(
          settings.contextOnly && !s.isMerge,
          context: settings.contextLines,
        );
      }
      if (s.options != settings.comparison) s.refresh(settings.comparison);
    }
    _saveSettings();
  }

  SingleActivator? _menuShortcut(AppCommand command) =>
      _settingsOpen ? null : settings.shortcuts[command]?.activator;

  String _shortcutHint(String text, AppCommand command) {
    final binding = settings.shortcuts[command];
    return binding == null ? text : '$text · ${binding.label}';
  }

  bool _enabled(AppCommand command) {
    final s = session;
    return switch (command) {
      AppCommand.open => !_opening && !_saving,
      AppCommand.save ||
      AppCommand.saveAs => s != null && !s.readOnly && !_saving,
      AppCommand.reload =>
        s?.left.path != null && s?.right.path != null && !_saving && !_opening,
      AppCommand.nextDiff ||
      AppCommand.previousDiff => s != null && !s.busy && s.hunkRows.isNotEmpty,
      AppCommand.nextConflict || AppCommand.previousConflict =>
        s?.isMerge == true && s!.merger!.state.regions.isNotEmpty,
      AppCommand.nextInlineDiff || AppCommand.previousInlineDiff =>
        s != null && s.inlineChanges(_active == 0 ? 0 : 1).isNotEmpty,
      AppCommand.swapSides =>
        s != null && !s.isMerge && s.output == null && !s.busy && !_saving,
      AppCommand.contextOnly => s != null && !s.isMerge && !s.busy,
      AppCommand.takeLeft || AppCommand.takeRight =>
        s != null &&
            !s.isMerge &&
            !s.readOnly &&
            !s.busy &&
            s.diff?.changes.isNotEmpty == true &&
            (command != AppCommand.takeRight || _leftEditable),
      AppCommand.toggleLeftEdit => s != null && !s.isMerge && !s.readOnly,
      AppCommand.undo =>
        !_activeReadOnly &&
            (_active == 2 ? s!.merger!.canUndo : editor!.canUndo),
      AppCommand.redo =>
        !_activeReadOnly &&
            (_active == 2 ? s!.merger!.canRedo : editor!.canRedo),
      AppCommand.find ||
      AppCommand.replace ||
      AppCommand.goToLine ||
      AppCommand.ignoreWhitespace ||
      AppCommand.showWhitespace => s != null,
      AppCommand.stage =>
        s != null && !s.isMerge && !s.readOnly && !_staging && !_saving,
      _ => true,
    };
  }

  void _runCommand(AppCommand command) {
    if (!_enabled(command) || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    switch (command) {
      case AppCommand.open:
        _open();
      case AppCommand.save:
        _save();
      case AppCommand.saveAs:
        _save(saveAs: true);
      case AppCommand.reload:
        _reload();
      case AppCommand.close:
        _close();
      case AppCommand.undo:
        _undo();
      case AppCommand.redo:
        _redo();
      case AppCommand.copy:
        _editAction(
          const CodeShortcutCopyIntent(),
          text: CopySelectionTextIntent.copy,
        );
      case AppCommand.cut:
        _editAction(
          const CodeShortcutCutIntent(),
          text: const CopySelectionTextIntent.cut(
            SelectionChangedCause.keyboard,
          ),
        );
      case AppCommand.paste:
        _editAction(
          const CodeShortcutPasteIntent(),
          text: const PasteTextIntent(SelectionChangedCause.keyboard),
        );
      case AppCommand.selectAll:
        _editAction(
          const CodeShortcutSelectAllIntent(),
          text: const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
      case AppCommand.find:
        finder?.findMode();
      case AppCommand.replace:
        finder?.replaceMode();
      case AppCommand.goToLine:
        _goToLine();
      case AppCommand.nextDiff:
        _navigate(1);
      case AppCommand.previousDiff:
        _navigate(-1);
      case AppCommand.nextConflict:
        _navigate(1, conflicts: true);
      case AppCommand.previousConflict:
        _navigate(-1, conflicts: true);
      case AppCommand.nextInlineDiff:
        _navigateInline(1);
      case AppCommand.previousInlineDiff:
        _navigateInline(-1);
      case AppCommand.toggleOverview:
        setState(() => settings.showOverview = !settings.showOverview);
        _saveSettings();
      case AppCommand.toggleLineDetails:
        setState(() => settings.showLineDetails = !settings.showLineDetails);
        _saveSettings();
      case AppCommand.toggleWordWrap:
        setState(() => settings.wordWrap = !settings.wordWrap);
        _saveSettings();
      case AppCommand.toggleWordDiff:
        setState(
          () =>
              settings.inlineMode = settings.inlineMode == InlineDiffMode.words
              ? InlineDiffMode.characters
              : InlineDiffMode.words,
        );
        session?.refresh(settings.comparison);
        _saveSettings();
      case AppCommand.toggleMovedBlocks:
        setState(() => settings.detectMoves = !settings.detectMoves);
        session?.refresh(settings.comparison);
        _saveSettings();
      case AppCommand.swapSides:
        _swapSides();
      case AppCommand.takeLeft:
        session!.applyHunk(_hunk);
      case AppCommand.takeRight:
        session!.applyHunk(_hunk, toRight: false);
      case AppCommand.toggleLeftEdit:
        setState(() => _leftEditable = !_leftEditable);
      case AppCommand.ignoreWhitespace:
        _toggleWhitespace();
      case AppCommand.contextOnly:
        _toggleContext();
      case AppCommand.showWhitespace:
        _toggleWhitespaceCharacters();
      case AppCommand.stage:
        _stageSelection(_active == 0 ? 0 : 1);
      case AppCommand.settings:
        _settings();
      case AppCommand.gitSettings:
        _settings(section: SettingsSection.git);
    }
  }

  Future<void> _goToLine() async {
    final target = editor;
    if (target == null) return;
    final focus = _active == 0
        ? _leftFocus
        : _active == 2
        ? _resultFocus
        : _rightFocus;
    final line = await showDialog<int>(
      context: context,
      builder: (_) => GoToLineDialog(
        lineCount: target.lineCount,
        currentLine: target.selection.extentIndex + 1,
      ),
    );
    if (line == null || !mounted || !identical(editor, target)) return;
    target.selection = CodeLineSelection.collapsed(index: line - 1, offset: 0);
    target.makeCursorCenterIfInvisible();
    focus.requestFocus();
  }

  @override
  void dispose() {
    settings.removeListener(_appearanceChanged);
    if (widget.nativeWindow) {
      windowManager.removeListener(this);
      const MethodChannel('fmerge/lifecycle').setMethodCallHandler(null);
    }
    session?.removeListener(_changed);
    session?.dispose();
    _leftFind?.dispose();
    _rightFind?.dispose();
    _resultFind?.dispose();
    for (final f in [_leftFocus, _rightFocus, _resultFocus]) {
      f.dispose();
    }
    for (final s in [_leftScroll, _rightScroll, _resultScroll]) {
      s.verticalScroller.dispose();
      s.horizontalScroller.dispose();
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = CallbackShortcuts(
      bindings: {
        for (final command in AppCommand.values)
          if (settings.shortcuts[command] case final KeyBinding binding)
            binding.activator: () => _runCommand(command),
      },
      child: Focus(
        autofocus: session == null,
        child: Scaffold(
          body: Column(
            children: [
              _toolbar(),
              if (session?.isMerge == true) _mergeContext(),
              if (_notice != null)
                _banner(_notice!, () => setState(() => _notice = null)),
              if (_diskChanged)
                _banner(
                  '磁盘文件发生变化。保存前会再次检查，避免覆盖其他程序的修改。',
                  () => setState(() => _diskChanged = false),
                  action: _reload,
                ),
              Expanded(child: session == null ? _welcome() : _workspace()),
              if (session != null && settings.showLineDetails) _lineDetails(),
              _status(),
            ],
          ),
        ),
      ),
    );
    if (widget.nativeWindow && Platform.isMacOS) {
      body = PlatformMenuBar(
        menus: [
          PlatformMenu(
            label: 'fmerge',
            menus: [
              PlatformMenuItem(label: '关于 fmerge', onSelected: _about),
              PlatformMenuItem(
                label: '设置…',
                onSelected: _settingsOpen ? null : _settings,
                shortcut: _menuShortcut(AppCommand.settings),
              ),
              PlatformMenuItem(
                label: '退出 fmerge',
                onSelected: _close,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyQ,
                  meta: true,
                ),
              ),
            ],
          ),
          PlatformMenu(
            label: '文件',
            menus: [
              PlatformMenuItem(
                label: '打开比较…',
                onSelected: _settingsOpen ? null : () => _open(),
                shortcut: _menuShortcut(AppCommand.open),
              ),
              PlatformMenuItem(
                label: '保存',
                onSelected: () => _save(),
                shortcut: _menuShortcut(AppCommand.save),
              ),
              PlatformMenuItem(
                label: '另存为…',
                onSelected: () => _save(saveAs: true),
                shortcut: _menuShortcut(AppCommand.saveAs),
              ),
              PlatformMenuItem(
                label: '关闭',
                onSelected: _close,
                shortcut: _menuShortcut(AppCommand.close),
              ),
            ],
          ),
          PlatformMenu(
            label: '编辑',
            menus: [
              PlatformMenuItem(
                label: '撤销',
                onSelected: () => _editAction(
                  const CodeShortcutUndoIntent(),
                  text: const UndoTextIntent(SelectionChangedCause.keyboard),
                ),
                shortcut: _menuShortcut(AppCommand.undo),
              ),
              PlatformMenuItem(
                label: '重做',
                onSelected: () => _editAction(
                  const CodeShortcutRedoIntent(),
                  text: const RedoTextIntent(SelectionChangedCause.keyboard),
                ),
                shortcut: _menuShortcut(AppCommand.redo),
              ),
              PlatformMenuItem(
                label: '复制',
                onSelected: () => _editAction(
                  const CodeShortcutCopyIntent(),
                  text: CopySelectionTextIntent.copy,
                ),
                shortcut: _menuShortcut(AppCommand.copy),
              ),
              PlatformMenuItem(
                label: '剪切',
                onSelected: () => _editAction(
                  const CodeShortcutCutIntent(),
                  text: const CopySelectionTextIntent.cut(
                    SelectionChangedCause.keyboard,
                  ),
                ),
                shortcut: _menuShortcut(AppCommand.cut),
              ),
              PlatformMenuItem(
                label: '粘贴',
                onSelected: () => _editAction(
                  const CodeShortcutPasteIntent(),
                  text: const PasteTextIntent(SelectionChangedCause.keyboard),
                ),
                shortcut: _menuShortcut(AppCommand.paste),
              ),
              PlatformMenuItem(
                label: '全选',
                onSelected: () => _editAction(
                  const CodeShortcutSelectAllIntent(),
                  text: const SelectAllTextIntent(
                    SelectionChangedCause.keyboard,
                  ),
                ),
                shortcut: _menuShortcut(AppCommand.selectAll),
              ),
              PlatformMenuItem(
                label: '查找…',
                onSelected: () => _editAction(const CodeShortcutFindIntent()),
                shortcut: _menuShortcut(AppCommand.find),
              ),
            ],
          ),
        ],
        child: body,
      );
    }
    return body;
  }

  Widget _commandTool(
    AppCommand command,
    IconData icon,
    String label, {
    bool selected = false,
    String? title,
  }) => ToolbarAction(
    key: ValueKey('command-${command.name}'),
    icon: icon,
    label: label,
    tooltip: _shortcutHint(title ?? command.label, command),
    onPressed: _enabled(command) ? () => _runCommand(command) : null,
    showLabel: settings.toolbarLabels,
    selected: selected,
  );

  Widget _menuLabel(String text, AppCommand command) => Row(
    children: [
      Expanded(child: Text(text)),
      const SizedBox(width: 20),
      Text(
        settings.shortcuts[command]?.label ?? '',
        style: TextStyle(fontSize: 10, color: AppPalette.of(context).muted),
      ),
    ],
  );

  void _toggleRule(String value) {
    switch (value) {
      case 'case':
        settings.ignoreCase = !settings.ignoreCase;
      case 'eol':
        settings.ignoreEol = !settings.ignoreEol;
      case 'highlight':
        settings.highlight = !settings.highlight;
    }
    setState(() {});
    if (value != 'highlight') session?.refresh(settings.comparison);
    _saveSettings();
  }

  Widget _menuFace(IconData icon, String label) => SizedBox(
    width: settings.toolbarLabels ? 50 : 34,
    height: settings.toolbarLabels ? 58 : 34,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 19, color: AppPalette.of(context).muted),
        if (settings.toolbarLabels) ...[
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: AppPalette.of(context).muted, fontSize: 10),
          ),
        ],
      ],
    ),
  );

  Widget _viewMenu() {
    CheckedPopupMenuItem<String> command(
      AppCommand command,
      String label,
      bool checked,
    ) => CheckedPopupMenuItem(
      key: ValueKey('command-${command.name}'),
      height: 36,
      value: command.name,
      enabled: _enabled(command),
      checked: checked,
      child: _menuLabel(label, command),
    );
    return PopupMenuButton<String>(
      key: const ValueKey('view-menu'),
      tooltip: '视图',
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 430),
      onSelected: (value) {
        switch (value) {
          case 'labels':
            setState(() => settings.toolbarLabels = !settings.toolbarLabels);
            _saveSettings();
          case 'case' || 'eol' || 'highlight':
            _toggleRule(value);
          default:
            _runCommand(AppCommand.values.byName(value));
        }
      },
      itemBuilder: (_) => [
        command(AppCommand.toggleOverview, '差异概览条', settings.showOverview),
        command(
          AppCommand.toggleLineDetails,
          '底部行详情',
          settings.showLineDetails,
        ),
        command(AppCommand.toggleWordWrap, '长行自动换行', settings.wordWrap),
        command(
          AppCommand.contextOnly,
          '仅显示差异及附近行',
          session?.contextOnly ?? settings.contextOnly,
        ),
        const PopupMenuDivider(height: 8),
        command(
          AppCommand.toggleWordDiff,
          '按单词显示行内差异',
          settings.inlineMode == InlineDiffMode.words,
        ),
        command(AppCommand.toggleMovedBlocks, '识别移动代码块', settings.detectMoves),
        command(
          AppCommand.ignoreWhitespace,
          '忽略行首、行尾空白',
          settings.ignoreWhitespace,
        ),
        CheckedPopupMenuItem(
          height: 36,
          value: 'case',
          checked: settings.ignoreCase,
          child: const Text('忽略大小写'),
        ),
        CheckedPopupMenuItem(
          height: 36,
          value: 'eol',
          checked: settings.ignoreEol,
          child: const Text('忽略换行符差异'),
        ),
        const PopupMenuDivider(height: 8),
        command(AppCommand.showWhitespace, '显示空白字符', settings.showWhitespace),
        CheckedPopupMenuItem(
          height: 36,
          value: 'highlight',
          checked: settings.highlight,
          child: const Text('语法高亮'),
        ),
        CheckedPopupMenuItem(
          height: 36,
          value: 'labels',
          checked: settings.toolbarLabels,
          child: const Text('显示工具栏文字'),
        ),
      ],
      child: _menuFace(Icons.visibility_outlined, '视图'),
    );
  }

  Widget _moreMenu() {
    final s = session;
    final canApply = _enabled(AppCommand.takeLeft);
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      constraints: const BoxConstraints(minWidth: 290, maxWidth: 430),
      onSelected: (value) {
        switch (value) {
          case 'copy' || 'paste' || 'previousInlineDiff' || 'nextInlineDiff':
            _runEditorCommand(AppCommand.values.byName(value));
          case 'as':
            _runCommand(AppCommand.saveAs);
          case 'reload':
            _runCommand(AppCommand.reload);
          case 'goto':
            _runCommand(AppCommand.goToLine);
          case 'both-left':
            s!.applyHunk(_hunk, combine: 1);
          case 'both-right':
            s!.applyHunk(_hunk, combine: 2);
          case 'git':
            _runCommand(AppCommand.gitSettings);
          case 'about':
            _about();
          case 'close':
            _runCommand(AppCommand.close);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          height: 40,
          value: 'as',
          enabled: _enabled(AppCommand.saveAs),
          child: _menuLabel('另存为…', AppCommand.saveAs),
        ),
        PopupMenuItem(
          height: 40,
          value: 'reload',
          enabled: _enabled(AppCommand.reload),
          child: _menuLabel('从磁盘重新加载', AppCommand.reload),
        ),
        PopupMenuItem(
          height: 40,
          value: 'goto',
          key: const ValueKey('command-goToLine'),
          enabled: s != null,
          child: _menuLabel('跳转到行…', AppCommand.goToLine),
        ),
        for (final command in [
          AppCommand.copy,
          AppCommand.paste,
          AppCommand.previousInlineDiff,
          AppCommand.nextInlineDiff,
        ])
          PopupMenuItem(
            key: ValueKey('command-${command.name}'),
            height: 40,
            value: command.name,
            enabled: _editorCommandEnabled(command),
            child: _menuLabel(command.label, command),
          ),
        if (s != null && !s.isMerge) ...[
          const PopupMenuDivider(height: 12),
          PopupMenuItem(
            height: 40,
            value: 'both-left',
            enabled: canApply,
            child: const Text('组合：左侧在前，右侧在后'),
          ),
          PopupMenuItem(
            height: 40,
            value: 'both-right',
            enabled: canApply,
            child: const Text('组合：右侧在前，左侧在后'),
          ),
        ],
        const PopupMenuDivider(height: 12),
        PopupMenuItem(
          height: 40,
          value: 'git',
          child: _menuLabel('Git 集成…', AppCommand.gitSettings),
        ),
        const PopupMenuItem(
          height: 40,
          value: 'about',
          child: Text('关于 fmerge'),
        ),
        PopupMenuItem(
          height: 40,
          value: 'close',
          child: _menuLabel('关闭', AppCommand.close),
        ),
      ],
      child: _menuFace(Icons.more_horiz, '更多'),
    );
  }

  bool _editorCommandEnabled(AppCommand command) => switch (command) {
    AppCommand.copy => editor?.selection.isCollapsed == false,
    AppCommand.paste => session != null && !_activeReadOnly,
    _ => _enabled(command),
  };

  void _runEditorCommand(AppCommand command) {
    if (!_editorCommandEnabled(command)) return;
    if (command == AppCommand.copy || command == AppCommand.paste) {
      // 菜单操作会改变焦点，直接对当前文档操作，避免把剪贴板交给菜单项。
      final target = editor!;
      if (command == AppCommand.copy) {
        unawaited(target.copy());
      } else {
        target.paste();
      }
      (_active == 0
              ? _leftFocus
              : _active == 2
              ? _resultFocus
              : _rightFocus)
          .requestFocus();
      return;
    }
    _runCommand(command);
  }

  Widget _lineDetails() {
    final s = session!;
    return ListenableBuilder(
      listenable: Listenable.merge([
        s.leftEditor,
        s.rightEditor,
        if (s.resultEditor != null) s.resultEditor!,
      ]),
      builder: (_, _) {
        final side = _active == 0 ? 0 : 1;
        final line =
            (side == 0 ? s.leftEditor : s.rightEditor).selection.extentIndex;
        final counterpart = s.movedCounterpart(side, line);
        return LineDetails(
          movementLabel: counterpart == null
              ? null
              : '移动代码 · ${side == 0 ? "右" : "左"} L${counterpart + 1}',
          onFollowMove: counterpart == null
              ? null
              : () {
                  final target = side == 0 ? s.rightEditor : s.leftEditor;
                  target.selection = CodeLineSelection.collapsed(
                    index: counterpart,
                    offset: 0,
                  );
                  (side == 0 ? _rightScroll : _leftScroll).makeVisible(
                    CodeLinePosition(index: counterpart, offset: 0),
                  );
                  (side == 0 ? _rightFocus : _leftFocus).requestFocus();
                },
          row: _active == 2
              ? s.conflictDetails(s.resultEditor!.selection.extentIndex)
              : s.lineDetails(side, line),
          tabSizes: [s.leftEditor.displayTabSize, s.rightEditor.displayTabSize],
          fontSize: settings.fontSize,
          merge: s.isMerge,
          conflict: _active == 2,
          onClose: () => _runCommand(AppCommand.toggleLineDetails),
        );
      },
    );
  }

  Widget _toolbar() {
    final s = session;
    Widget divider() =>
        const VerticalDivider(width: 6, indent: 10, endIndent: 10);
    return Container(
      height: settings.toolbarLabels ? 66 : 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppPalette.of(context).bg,
        border: Border(
          bottom: BorderSide(color: AppPalette.of(context).border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: IntrinsicWidth(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: Row(
                        children: [
                          _commandTool(
                            AppCommand.open,
                            Icons.folder_open,
                            '打开',
                          ),
                          _commandTool(
                            AppCommand.save,
                            _saving
                                ? Icons.hourglass_empty
                                : Icons.save_outlined,
                            '保存',
                          ),
                          if (s != null) ...[
                            _commandTool(
                              AppCommand.reload,
                              Icons.refresh,
                              '重新加载',
                              title: '从磁盘重新加载，读取外部编辑器的修改',
                            ),
                            divider(),
                            _commandTool(AppCommand.undo, Icons.undo, '撤销'),
                            _commandTool(AppCommand.redo, Icons.redo, '重做'),
                            _commandTool(
                              AppCommand.find,
                              Icons.search,
                              '查找',
                              title: '查找 / 替换',
                            ),
                            divider(),
                            _commandTool(
                              AppCommand.previousDiff,
                              Icons.keyboard_arrow_up,
                              '上一处',
                            ),
                            Text(
                              s.error != null
                                  ? '比较失败'
                                  : s.busy || s.diff == null
                                  ? '正在比较…'
                                  : s.hunkRows.isEmpty
                                  ? '文件相同'
                                  : '${_hunk + 1} / ${s.hunkRows.length}',
                              style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontSize: 11,
                              ),
                            ),
                            _commandTool(
                              AppCommand.nextDiff,
                              Icons.keyboard_arrow_down,
                              '下一处',
                            ),
                            if (s.isMerge) ...[
                              divider(),
                              _commandTool(
                                AppCommand.previousConflict,
                                Icons.skip_previous,
                                '上一处冲突',
                              ),
                              _commandTool(
                                AppCommand.nextConflict,
                                Icons.skip_next,
                                '下一处冲突',
                              ),
                            ],
                            if (!s.isMerge) ...[
                              divider(),
                              _commandTool(
                                AppCommand.takeLeft,
                                Icons.arrow_forward,
                                '采用左侧',
                              ),
                              _commandTool(
                                AppCommand.takeRight,
                                Icons.arrow_back,
                                '采用右侧',
                              ),
                              _commandTool(
                                AppCommand.toggleLeftEdit,
                                _leftEditable
                                    ? Icons.lock_open
                                    : Icons.lock_outline,
                                '左侧编辑',
                                selected: _leftEditable,
                                title: _leftEditable ? '锁定左侧编辑' : '启用左侧编辑',
                              ),
                              divider(),
                              _commandTool(
                                AppCommand.swapSides,
                                Icons.swap_horiz,
                                '交换左右',
                              ),
                            ],
                            const Spacer(),
                            if (s.isMerge)
                              _tag(
                                s.pending > 0
                                    ? '${s.pending} 处冲突待确认'
                                    : '全部冲突已处理',
                                s.pending > 0
                                    ? AppPalette.of(context).amber
                                    : AppPalette.of(context).green,
                              ),
                          ] else
                            const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          divider(),
          _viewMenu(),
          _moreMenu(),
          _commandTool(AppCommand.settings, Icons.tune, '设置'),
        ],
      ),
    );
  }

  Widget _workspace() {
    final s = session!;
    CodeDiffLayout? overviewLayout(int side) {
      final layout = (side == 0 ? s.leftEditor : s.rightEditor).diffLayout;
      if (!s.isMerge || layout == null || s.branchDiffs == null) return layout;
      return CodeDiffLayout(
        lineRows: layout.lineRows,
        totalRows: layout.totalRows,
        wrap: layout.wrap,
        rowColors: {
          ...layout.rowColors,
          for (final (_, row) in s.branchDiffs![side].changedRows)
            if (row.rightLine == null && row.leftLine != null)
              s.mergeAlignment!.baseRows[row.leftLine!]: AppPalette.of(context)
                  .amber,
        },
      );
    }

    final top = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        if (mounted) setState(() {});
        return false;
      },
      child: Row(
        children: [
          if (settings.showOverview)
            Padding(
              padding: EdgeInsets.only(
                top: (s.isMerge ? 70 : 42) + _sharedFindHeight,
                bottom: 32,
              ),
              child: DiffOverview(
                wordWrap: settings.wordWrap,
                left: overviewLayout(0),
                right: overviewLayout(1),
                scroll: _leftScroll.verticalScroller,
                onSeek: s.comparisonCurrent ? _seekOverview : null,
              ),
            ),
          Expanded(
            child: _pane(
              0,
              s.left,
              s.leftEditor,
              _leftFocus,
              _leftScroll,
              _leftFind!,
              s.isMerge ? s.mergeLabels.leftTitle : '原始 · Left',
              readOnly: s.readOnly || s.isMerge || !_leftEditable,
            ),
          ),
          const VerticalDivider(width: 6, thickness: 1),
          Expanded(
            child: _pane(
              1,
              s.right,
              s.rightEditor,
              _rightFocus,
              _rightScroll,
              _rightFind!,
              s.isMerge ? s.mergeLabels.rightTitle : '修改 · Right',
              readOnly: s.readOnly || s.isMerge,
            ),
          ),
        ],
      ),
    );
    if (!s.isMerge) {
      if (!s.contextOnly) return top;
      final colors = Theme.of(context).colorScheme;
      final hidden = s.leftEditor.diffLayout?.rowLabels.length ?? 0;
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .10),
              border: Border(bottom: BorderSide(color: colors.outline)),
            ),
            child: Row(
              children: [
                Icon(Icons.unfold_less, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '仅看差异 · 前后各 ${s.contextLines} 行'
                    ' · ${!s.comparisonCurrent
                        ? '计算中…'
                        : hidden > 0
                        ? '已省略 $hidden 段未改动内容'
                        : '当前无可省略内容'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.primary),
                  ),
                ),
                TextButton(
                  onPressed: () => _toggleContext(),
                  child: const Text('显示全文'),
                ),
              ],
            ),
          ),
          Expanded(child: top),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, c) => Column(
        children: [
          SizedBox(height: (c.maxHeight - 91) * _topFraction, child: top),
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              onVerticalDragUpdate: (d) => setState(
                () => _topFraction = (_topFraction + d.delta.dy / c.maxHeight)
                    .clamp(.25, .75),
              ),
              child: Container(
                height: 7,
                color: AppPalette.of(context).border,
                alignment: Alignment.center,
                child: Container(
                  width: 38,
                  height: 2,
                  color: AppPalette.of(context).muted,
                ),
              ),
            ),
          ),
          _mergeToolbar(),
          Expanded(
            child: _pane(
              2,
              s.output ??
                  (TextFile.empty(s.base!.original)
                    ..encoding = s.base!.encoding),
              s.resultEditor!,
              _resultFocus,
              _resultScroll,
              _resultFind!,
              '合并结果',
              readOnly: s.readOnly,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pane(
    int side,
    TextFile file,
    CodeLineEditingController controller,
    FocusNode focus,
    CodeScrollController scroll,
    CodeFindController find,
    String title, {
    required bool readOnly,
  }) => Column(
    children: [
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _active == side
              ? AppPalette.of(context).elevated
              : AppPalette.of(context).panel,
          border: Border(
            top: BorderSide(
              color: _active == side
                  ? AppPalette.of(context).accent
                  : Colors.transparent,
              width: 2,
            ),
            bottom: BorderSide(color: AppPalette.of(context).border),
          ),
        ),
        child: Row(
          children: [
            Icon(
              readOnly ? Icons.lock_outline : Icons.edit_outlined,
              size: 13,
              color: side == 0
                  ? AppPalette.of(context).red
                  : side == 1
                  ? AppPalette.of(context).green
                  : AppPalette.of(context).accent,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Tooltip(
                message: title,
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppPalette.of(context).muted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: file.path ?? '未命名文本',
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (side == 0
                ? session!.leftDirty
                : side == 1
                ? session!.rightDirty
                : session!.resultDirty)
              Padding(
                padding: EdgeInsets.only(left: 5),
                child: Text(
                  '●',
                  style: TextStyle(
                    color: AppPalette.of(context).amber,
                    fontSize: 10,
                  ),
                ),
              ),
            if (side == 2 && session!.base != null)
              TextButton(
                onPressed: () => _showBase(),
                child: const Text('查看祖先', style: TextStyle(fontSize: 10)),
              ),
          ],
        ),
      ),
      if (session!.isMerge && side < 2)
        Container(
          height: 28,
          color: AppPalette.of(context).elevated,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Tooltip(
            message:
                '${session!.mergeLabels.detail(side == 0)}\n${file.path ?? '未命名文本'}',
            child: Text(
              session!.mergeLabels.operation == MergeOperation.files
                  ? file.path ?? '未命名文本'
                  : side == 0
                  ? session!.mergeLabels.leftSource
                  : session!.mergeLabels.rightSource,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.of(context).muted,
                fontSize: 11,
              ),
            ),
          ),
        ),
      Expanded(
        child: CodePane(
          key: ValueKey((session, side, controller)),
          controller: controller,
          settings: settings,
          focus: focus,
          scroll: scroll,
          language:
              _languageOverride(side) ??
              languageFor(
                file.path ?? (side == 2 ? session!.left.name : file.name),
              ),
          readOnly: readOnly,
          find: find,
          reservedFindHeight: side < 2 ? _sharedFindHeight : 0,
          onSave: () => _save(),
          onStage:
              !session!.isMerge &&
                  !session!.readOnly &&
                  file.path != null &&
                  !_staging
              ? () => _stageSelection(side)
              : null,
          undo: side == 2 ? session!.undoMerge : null,
          redo: side == 2 ? session!.redoMerge : null,
        ),
      ),
      DocumentStatus(
        file: file,
        controller: controller,
        changeSummary: side == 2
            ? null
            : !session!.comparisonCurrent
            ? '…'
            : session!.isMerge
            ? '+${session!.branchDiffs![side].added} −${session!.branchDiffs![side].removed}'
            : side == 0
            ? '−${session!.diff!.removed}'
            : '+${session!.diff!.added}',
        changeTooltip: session!.isMerge
            ? '本侧相对共同祖先的新增 / 删除行数；遵循当前比较规则'
            : '相对另一侧的变化行数；遵循当前比较规则',
        language: _languageOverride(side),
        languageName: side == 2
            ? session!.output?.path ?? session!.left.name
            : null,
        onLanguageChanged: (value) => setState(() {
          switch (side) {
            case 0:
              session!.leftLanguage = value;
            case 1:
              session!.rightLanguage = value;
            default:
              session!.resultLanguage = value;
          }
        }),
        encoding: session!.saveEncodings[side],
        eol: session!.saveEols[side],
        saveEncoding: side == 2 || file.path == null,
        onEncodingChanged:
            _saving ||
                _opening ||
                (readOnly && (side == 2 || file.path == null))
            ? null
            : (value) => _changeEncoding(side, value),
        onEolChanged: readOnly || _saving
            ? null
            : (value) => session!.setSaveEol(side, value),
      ),
    ],
  );
  String? _languageOverride(int side) => switch (side) {
    0 => session!.leftLanguage,
    1 => session!.rightLanguage,
    _ => session!.resultLanguage,
  };
  Widget _mergeContext() {
    final s = session!, labels = s.mergeLabels;
    return Container(
      color: AppPalette.of(context).elevated,
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              labels.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).accent,
              ),
            ),
          ),
          if (labels.operation == MergeOperation.files &&
              s.output?.path != null)
            TextButton(
              onPressed: _identifyingSource ? null : _identifyMergeSource,
              child: Text(_identifyingSource ? '正在识别…' : '识别 Git 来源'),
            ),
          IconButton(
            tooltip: '查看合并来源与角色',
            icon: const Icon(Icons.info_outline, size: 17),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('合并来源'),
                content: SingleChildScrollView(
                  child: SelectableText(
                    '${labels.summary}\n\n'
                    '${labels.leftTitle}\n${labels.leftSource}\n${labels.detail(true)}\n${s.left.path ?? '未命名文本'}\n\n'
                    '${labels.rightTitle}\n${labels.rightSource}\n${labels.detail(false)}\n${s.right.path ?? '未命名文本'}\n\n'
                    '共同祖先\n${s.base?.path ?? '未命名文本'}\n\n'
                    'ours / theirs 表示当前 Git 操作的双方角色，不固定表示“我的 / 别人的代码”。'
                    'rebase 时，左侧是目标历史，右侧是正在重放的提交。',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _identifyMergeSource() async {
    final s = session;
    if (s == null || _identifyingSource || s.output?.path == null) return;
    setState(() => _identifyingSource = true);
    try {
      if (widget.nativeWindow &&
          !await DirectoryAccess.grant(
            File(s.output!.path!).absolute.parent.path,
          )) {
        return;
      }
      await s.identifyMergeLabels();
      if (mounted &&
          s == session &&
          s.mergeLabels.operation == MergeOperation.files) {
        _message('未确认当前输入对应的 Git 冲突，继续按左右文件路径区分来源。');
      }
    } catch (e) {
      _message('来源识别失败：$e');
    } finally {
      if (mounted) setState(() => _identifyingSource = false);
    }
  }

  Widget _mergeToolbar() {
    final s = session!, regions = s.merger!.state.regions;
    if (regions.isEmpty) {
      return SizedBox(
        height: 36,
        child: Center(
          child: Text(
            '双方修改没有冲突，可检查结果并保存。',
            style: TextStyle(fontSize: 12, color: AppPalette.of(context).green),
          ),
        ),
      );
    }
    _conflict = _conflict.clamp(0, regions.length - 1);
    final r = regions[_conflict];
    return Container(
      height: 48,
      color: AppPalette.of(context).elevated,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _shortcutHint('上一处冲突', AppCommand.previousConflict),
              onPressed: () => _runCommand(AppCommand.previousConflict),
              icon: const Icon(Icons.chevron_left, size: 18),
            ),
            Text(
              '${_conflict + 1}/${regions.length} · 祖先 L${r.chunk.start + 1}',
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.of(context).muted,
              ),
            ),
            IconButton(
              tooltip: _shortcutHint('下一处冲突', AppCommand.nextConflict),
              onPressed: () => _runCommand(AppCommand.nextConflict),
              icon: const Icon(Icons.chevron_right, size: 18),
            ),
            for (final item in [
              (MergeChoice.left, s.mergeLabels.leftAction),
              (MergeChoice.right, s.mergeLabels.rightAction),
              (MergeChoice.both, '左右组合'),
              (MergeChoice.base, '保留祖先'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: OutlinedButton(
                  onPressed: s.readOnly
                      ? null
                      : () => s.choose(r.chunk.id, item.$1),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(item.$2, style: const TextStyle(fontSize: 11)),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: '其他冲突操作',
              enabled: !s.readOnly,
              onSelected: (v) {
                if (v == 'reverse') {
                  s.choose(r.chunk.id, MergeChoice.both, reverse: true);
                } else {
                  s.markResolved(r.chunk.id, !r.resolved);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reverse', child: Text('右侧在前，左侧在后')),
                PopupMenuItem(
                  value: 'mark',
                  child: Text(r.resolved ? '标记为未处理' : '标记为已手工解决'),
                ),
              ],
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: s.readOnly
                  ? null
                  : () => s.markResolved(r.chunk.id, !r.resolved),
              icon: Icon(
                r.resolved ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 15,
                color: r.resolved
                    ? AppPalette.of(context).green
                    : AppPalette.of(context).amber,
              ),
              label: Text(
                r.resolved ? '已确认' : '标记解决',
                style: TextStyle(
                  fontSize: 11,
                  color: r.resolved
                      ? AppPalette.of(context).green
                      : AppPalette.of(context).amber,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBase() => showDialog(
    context: context,
    builder: (_) => BaseDialog(
      file: session!.base!,
      settings: settings,
      language: session!.baseLanguage,
      onLanguageChanged: (value) => session!.baseLanguage = value,
      onEncodingChanged: (value) {
        Navigator.pop(context);
        _changeEncoding(3, value);
      },
    ),
  );
  Widget _welcome() => WelcomeView(
    onCompare: () => _open(),
    onPaste: () => setState(
      () => _attach(CompareSession(TextFile.empty(), TextFile.empty())),
    ),
    recent: settings.recent,
    onRecent: (r) => _open(
      options: LaunchOptions(
        left: r['left'],
        right: r['right'],
        base: r['base'],
        output: r['output'],
      ),
    ),
  );
  Widget _status() {
    final s = session;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppPalette.of(context).border)),
      ),
      child: Row(
        children: [
          Text(
            s == null
                ? '就绪'
                : s.readOnly
                ? '只读模式'
                : s.dirty
                ? '有未保存修改'
                : (s.isMerge ? s.output?.path : s.right.path) == null
                ? '未命名文本'
                : '已保存',
            style: TextStyle(
              fontSize: 11,
              color: s?.dirty == true
                  ? AppPalette.of(context).amber
                  : AppPalette.of(context).muted,
            ),
          ),
          const Spacer(),
          if (s?.error != null)
            Flexible(
              child: Tooltip(
                message: s!.error!,
                child: Text(
                  s.error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.of(context).red,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          if (s?.diff?.timedOut == true)
            Flexible(
              child: Tooltip(
                message: '差异计算已降级为较粗的区间',
                child: Text(
                  '差异计算已降级为较粗的区间',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.of(context).amber,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Text(
            '${settings.shortcuts[AppCommand.nextDiff]?.label ?? "未设置"} 差异 · ${settings.shortcuts[AppCommand.nextConflict]?.label ?? "未设置"} 冲突 · ${settings.shortcuts[AppCommand.save]?.label ?? "未设置"} 保存',
            style: TextStyle(fontSize: 11, color: AppPalette.of(context).muted),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10)),
  );
  Widget _banner(String text, VoidCallback dismiss, {VoidCallback? action}) =>
      Container(
        color: AppPalette.of(context).conflictBg,
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: AppPalette.of(context).amber,
                ),
              ),
            ),
            if (action != null)
              TextButton(onPressed: action, child: const Text('重新加载')),
            IconButton(
              tooltip: '关闭提示',
              onPressed: dismiss,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      );
  void _about() => showAboutDialog(
    context: context,
    applicationName: 'fmerge',
    applicationVersion: '0.1.0',
    applicationLegalese: '原生桌面文本比较与三方合并',
    children: const [
      SizedBox(height: 16),
      Text('Git 外部工具配置位于“设置 → Git 集成”。\n\nDiff 核心基于 MIT 许可的 VS Code Myers 算法。'),
    ],
  );
}
