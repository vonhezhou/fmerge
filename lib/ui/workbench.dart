import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import '../core/access.dart';
import '../core/files.dart';
import '../core/diff.dart';
import '../core/launch.dart';
import '../core/merge.dart';
import '../core/settings.dart';
import '../session.dart';
import '../palette.dart';
import 'code_pane.dart';
import 'open_dialog.dart';
import 'git_dialog.dart';
import 'settings_dialog.dart';
import 'format_dialog.dart';
import 'base_dialog.dart';

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
      _diskChanged = false;
  int _active = 1, _hunk = 0, _conflict = 0;
  double _topFraction = .50;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _notice = widget.startupError;
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
    next.showWhitespace = settings.showWhitespace;
    next.updateResultLayout();
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

  Future<void> _open({bool merge = false, LaunchOptions? options}) async {
    if (!await _leave() || !mounted) return;
    try {
      final next = options == null
          ? await showDialog<CompareSession>(
              context: context,
              builder: (_) =>
                  OpenDialog(merge: merge, nativeAccess: widget.nativeWindow),
            )
          : await CompareSession.open(options);
      if (next != null && mounted) setState(() => _attach(next));
    } catch (e) {
      _message('打开失败：$e');
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
        builder: (_) =>
            FormatDialog(encoding: file?.encoding ?? TextEncoding.utf8),
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
          encoding: format?.encoding,
          eol: format?.eol,
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
          asEncoding: format?.encoding,
          forcedEol: format?.eol,
        );
        s.inputSaved();
      }
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

  void _toggleWhitespace() {
    settings.whitespace = settings.whitespace == WhitespaceMode.exact
        ? WhitespaceMode.all
        : WhitespaceMode.exact;
    session?.refresh(settings.comparison);
    _saveSettings();
  }

  Future<void> _git() async {
    final s = session;
    await showDialog(
      context: context,
      builder: (_) => GitDialog(
        path: s?.isMerge == true ? s?.output?.path : s?.right.path,
        nativeAccess: widget.nativeWindow,
      ),
    );
  }

  Future<void> _settings() async {
    await showDialog(
      context: context,
      builder: (_) => SettingsDialog(settings: settings),
    );
    if (!mounted) return;
    setState(() {});
    session?.showWhitespace = settings.showWhitespace;
    session?.updateResultLayout();
    session?.refresh(settings.comparison);
    _saveSettings();
  }

  Future<void> _goToLine() async {
    final field = TextEditingController();
    final line = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到行'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(field.text)),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    field.dispose();
    if (line == null || editor == null) return;
    editor!.selection = CodeLineSelection.collapsed(
      index: (line - 1).clamp(0, editor!.lineCount - 1),
      offset: 0,
    );
    editor!.makeCursorCenterIfInvisible();
  }

  @override
  void dispose() {
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
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
            _open(),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            _open(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            _save(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(),
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: true,
          shift: true,
        ): () =>
            _save(saveAs: true),
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () =>
            _save(saveAs: true),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): _goToLine,
        const SingleActivator(LogicalKeyboardKey.keyG, control: true):
            _goToLine,
        const SingleActivator(LogicalKeyboardKey.f7): () => _navigate(1),
        const SingleActivator(LogicalKeyboardKey.f7, shift: true): () =>
            _navigate(-1),
        const SingleActivator(LogicalKeyboardKey.f8): () =>
            _navigate(1, conflicts: true),
        const SingleActivator(LogicalKeyboardKey.f8, shift: true): () =>
            _navigate(-1, conflicts: true),
      },
      child: Focus(
        autofocus: session == null,
        child: Scaffold(
          body: Column(
            children: [
              _header(),
              if (session != null) _toolbar(),
              if (_notice != null)
                _banner(_notice!, () => setState(() => _notice = null)),
              if (_diskChanged)
                _banner(
                  '磁盘文件发生变化。保存前会再次检查，避免覆盖其他程序的修改。',
                  () => setState(() => _diskChanged = false),
                  action: _reload,
                ),
              Expanded(child: session == null ? _welcome() : _workspace()),
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
                onSelected: _settings,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
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
                onSelected: () => _open(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '打开三方合并…',
                onSelected: () => _open(merge: true),
              ),
              PlatformMenuItem(
                label: '保存',
                onSelected: () => _save(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '另存为…',
                onSelected: () => _save(saveAs: true),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                  shift: true,
                ),
              ),
              PlatformMenuItem(
                label: '关闭',
                onSelected: _close,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                ),
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
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '重做',
                onSelected: () => _editAction(
                  const CodeShortcutRedoIntent(),
                  text: const RedoTextIntent(SelectionChangedCause.keyboard),
                ),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  meta: true,
                  shift: true,
                ),
              ),
              PlatformMenuItem(
                label: '复制',
                onSelected: () => _editAction(
                  const CodeShortcutCopyIntent(),
                  text: CopySelectionTextIntent.copy,
                ),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '剪切',
                onSelected: () => _editAction(
                  const CodeShortcutCutIntent(),
                  text: const CopySelectionTextIntent.cut(
                    SelectionChangedCause.keyboard,
                  ),
                ),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyX,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '粘贴',
                onSelected: () => _editAction(
                  const CodeShortcutPasteIntent(),
                  text: const PasteTextIntent(SelectionChangedCause.keyboard),
                ),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '全选',
                onSelected: () => _editAction(
                  const CodeShortcutSelectAllIntent(),
                  text: const SelectAllTextIntent(
                    SelectionChangedCause.keyboard,
                  ),
                ),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyA,
                  meta: true,
                ),
              ),
              PlatformMenuItem(
                label: '查找…',
                onSelected: () => _editAction(const CodeShortcutFindIntent()),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  meta: true,
                ),
              ),
            ],
          ),
        ],
        child: body,
      );
    }
    return body;
  }

  Widget _header() => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: border)),
    ),
    child: Row(
      children: [
        const Icon(Icons.difference_outlined, color: accent, size: 24),
        const SizedBox(width: 10),
        const Text(
          'fmerge',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Text(
          session?.isMerge == true ? '三方合并' : '文件比较',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => _open(),
          icon: const Icon(Icons.folder_open, size: 17),
          label: const Text('打开比较'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _open(merge: true),
          icon: const Icon(Icons.merge, size: 17),
          label: const Text('三方合并'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: session == null || session!.readOnly || _saving
              ? null
              : () => _save(),
          icon: Icon(
            _saving ? Icons.hourglass_empty : Icons.save_outlined,
            size: 17,
          ),
          label: const Text('保存'),
        ),
        PopupMenuButton<String>(
          tooltip: '更多操作',
          onSelected: (v) {
            switch (v) {
              case 'as':
                _save(saveAs: true);
              case 'reload':
                _reload();
              case 'find':
                finder?.findMode();
              case 'goto':
                _goToLine();
              case 'settings':
                _settings();
              case 'about':
                _about();
              case 'close':
                _close();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'as', child: Text('另存为…')),
            PopupMenuItem(value: 'reload', child: Text('从磁盘重新加载')),
            PopupMenuItem(value: 'find', child: Text('查找 / 替换')),
            PopupMenuItem(value: 'goto', child: Text('跳转到行…')),
            PopupMenuItem(value: 'settings', child: Text('设置…')),
            PopupMenuItem(value: 'about', child: Text('关于 / Git 配置')),
            PopupMenuItem(value: 'close', child: Text('关闭')),
          ],
        ),
      ],
    ),
  );
  Widget _toolbar() {
    final s = session!, d = s.diff;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1020,
          child: Row(
            children: [
              IconButton(
                tooltip: '撤销',
                onPressed: s.readOnly ? null : _undo,
                icon: const Icon(Icons.undo, size: 18),
              ),
              IconButton(
                tooltip: '重做',
                onPressed: s.readOnly ? null : _redo,
                icon: const Icon(Icons.redo, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '查找 / 替换',
                onPressed: () => finder?.findMode(),
                icon: const Icon(Icons.search, size: 18),
              ),
              IconButton(
                tooltip: s.showWhitespace ? '隐藏空白字符' : '显示空白字符',
                onPressed: () {
                  settings.showWhitespace = !settings.showWhitespace;
                  s.showWhitespace = settings.showWhitespace;
                  s.updateResultLayout();
                  s.refresh(settings.comparison);
                  _saveSettings();
                },
                icon: Icon(
                  Icons.space_bar,
                  size: 18,
                  color: s.showWhitespace ? accent : muted,
                ),
              ),
              IconButton(
                tooltip: settings.whitespace == WhitespaceMode.exact
                    ? '隐藏空白字符差异'
                    : '显示空白字符差异',
                onPressed: _toggleWhitespace,
                icon: Icon(
                  Icons.format_clear,
                  size: 18,
                  color: settings.whitespace != WhitespaceMode.exact
                      ? accent
                      : muted,
                ),
              ),
              IconButton(
                tooltip: s.contextOnly ? '显示整个文件' : '仅显示差异及前后 3 行',
                onPressed: s.isMerge || s.busy
                    ? null
                    : () => s.setContextOnly(!s.contextOnly),
                icon: Icon(
                  s.contextOnly ? Icons.unfold_more : Icons.unfold_less,
                  size: 18,
                  color: s.contextOnly ? accent : muted,
                ),
              ),
              IconButton(
                tooltip: s.output != null ? '指定输出位置时不能交换左右' : '交换左右文件',
                onPressed: s.isMerge || s.output != null || s.busy || _saving
                    ? null
                    : _swapSides,
                icon: const Icon(Icons.swap_horiz, size: 18),
              ),
              IconButton(
                tooltip: 'Git · 按块暂存 / 取消暂存',
                onPressed: _saving || s.readOnly ? null : _git,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
              ),
              const VerticalDivider(indent: 12, endIndent: 12),
              IconButton(
                tooltip: '上一处差异 · Shift F7',
                onPressed: () => _navigate(-1),
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              ),
              Text(
                d == null
                    ? '正在比较…'
                    : s.hunkRows.isEmpty
                    ? '文件相同'
                    : '${_hunk + 1} / ${s.hunkRows.length} 处差异',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              IconButton(
                tooltip: '下一处差异 · F7',
                onPressed: () => _navigate(1),
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              ),
              if (!s.isMerge) ...[
                IconButton(
                  tooltip: '使用左侧差异块',
                  onPressed:
                      s.readOnly || s.busy || d == null || d.changes.isEmpty
                      ? null
                      : () => s.applyHunk(_hunk),
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: accent,
                    size: 19,
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: '组合当前差异块',
                  onSelected: (v) => s.applyHunk(_hunk, combine: v),
                  enabled:
                      !s.readOnly && !s.busy && d?.changes.isNotEmpty == true,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 1, child: Text('左侧在前，右侧在后')),
                    PopupMenuItem(value: 2, child: Text('右侧在前，左侧在后')),
                  ],
                  icon: const Icon(Icons.playlist_add, size: 19, color: muted),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: s.readOnly
                      ? null
                      : () => setState(() => _leftEditable = !_leftEditable),
                  icon: Icon(
                    _leftEditable ? Icons.lock_open : Icons.lock_outline,
                    size: 14,
                  ),
                  label: Text(
                    _leftEditable ? '左侧可编辑' : '启用左侧编辑',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ] else ...[
                const Spacer(),
                _tag(
                  s.pending > 0 ? '${s.pending} 处冲突待确认' : '全部冲突已处理',
                  s.pending > 0 ? amber : green,
                ),
              ],
              if (s.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspace() {
    final s = session!;
    final top = Row(
      children: [
        Expanded(
          child: _pane(
            0,
            s.left,
            s.leftEditor,
            _leftFocus,
            _leftScroll,
            _leftFind!,
            s.isMerge ? '本地 · Local' : '原始 · Left',
            readOnly: s.readOnly || s.isMerge || !_leftEditable,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _pane(
            1,
            s.right,
            s.rightEditor,
            _rightFocus,
            _rightScroll,
            _rightFind!,
            s.isMerge ? '远端 · Remote' : '修改 · Right',
            readOnly: s.readOnly || s.isMerge,
          ),
        ),
      ],
    );
    if (!s.isMerge) return top;
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
                color: border,
                alignment: Alignment.center,
                child: Container(width: 38, height: 2, color: muted),
              ),
            ),
          ),
          _mergeToolbar(),
          Expanded(
            child: _pane(
              2,
              s.output ?? TextFile.empty(),
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
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: elevated,
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Row(
          children: [
            Icon(
              readOnly ? Icons.lock_outline : Icons.edit_outlined,
              size: 13,
              color: side == 0
                  ? red
                  : side == 1
                  ? green
                  : accent,
            ),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(fontSize: 11, color: muted)),
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
              const Padding(
                padding: EdgeInsets.only(left: 5),
                child: Text('●', style: TextStyle(color: amber, fontSize: 10)),
              ),
            if (side == 2 && session!.base != null)
              TextButton(
                onPressed: () => _showBase(),
                child: const Text('查看祖先', style: TextStyle(fontSize: 10)),
              ),
          ],
        ),
      ),
      Expanded(
        child: CodePane(
          key: ValueKey((session, side, controller)),
          controller: controller,
          settings: settings,
          focus: focus,
          scroll: scroll,
          language: languageFor(
            file.path ?? (side == 2 ? session!.left.name : file.name),
          ),
          readOnly: readOnly,
          find: find,
          reservedFindHeight: side < 2 ? _sharedFindHeight : 0,
          onSave: () => _save(),
          undo: side == 2 ? session!.undoMerge : null,
          redo: side == 2 ? session!.redoMerge : null,
        ),
      ),
    ],
  );
  Widget _mergeToolbar() {
    final s = session!, regions = s.merger!.state.regions;
    if (regions.isEmpty) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: Text(
            '双方修改没有冲突，可检查结果并保存。',
            style: TextStyle(fontSize: 12, color: green),
          ),
        ),
      );
    }
    _conflict = _conflict.clamp(0, regions.length - 1);
    final r = regions[_conflict];
    return Container(
      height: 48,
      color: elevated,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一处冲突 · Shift F8',
            onPressed: () => _navigate(-1, conflicts: true),
            icon: const Icon(Icons.chevron_left, size: 18),
          ),
          Text(
            '${_conflict + 1}/${regions.length} · 祖先 L${r.chunk.start + 1}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          IconButton(
            tooltip: '下一处冲突 · F8',
            onPressed: () => _navigate(1, conflicts: true),
            icon: const Icon(Icons.chevron_right, size: 18),
          ),
          for (final item in const [
            (MergeChoice.left, '采用本地'),
            (MergeChoice.right, '采用远端'),
            (MergeChoice.both, '本地 + 远端'),
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
              const PopupMenuItem(value: 'reverse', child: Text('远端在前，本地在后')),
              PopupMenuItem(
                value: 'mark',
                child: Text(r.resolved ? '标记为未处理' : '标记为已手工解决'),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: s.readOnly
                ? null
                : () => s.markResolved(r.chunk.id, !r.resolved),
            icon: Icon(
              r.resolved ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 15,
              color: r.resolved ? green : amber,
            ),
            label: Text(
              r.resolved ? '已确认' : '标记解决',
              style: TextStyle(fontSize: 11, color: r.resolved ? green : amber),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBase() => showDialog(
    context: context,
    builder: (_) => BaseDialog(file: session!.base!, settings: settings),
  );
  Widget _welcome() => Center(
    child: SingleChildScrollView(
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.difference_outlined, size: 44, color: accent),
            const SizedBox(height: 20),
            const Text(
              '看清每一次修改',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '比较文本，逐块采用修改，完成三方合并。',
              style: TextStyle(color: muted, fontSize: 15),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('打开两个文件'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _open(merge: true),
                  icon: const Icon(Icons.merge),
                  label: const Text('打开三方合并'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    if (session == null) {
                      setState(
                        () => _attach(
                          CompareSession(TextFile.empty(), TextFile.empty()),
                        ),
                      );
                    }
                  },
                  child: const Text('粘贴文本比较'),
                ),
              ],
            ),
            if (settings.recent.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Text('最近打开', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 8),
              for (final r in settings.recent.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    r['base'] == null ? Icons.compare_arrows : Icons.merge,
                    color: muted,
                    size: 19,
                  ),
                  title: Text(
                    '${r['left']}  ↔  ${r['right']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _open(
                    options: LaunchOptions(
                      left: r['left'],
                      right: r['right'],
                      base: r['base'],
                      output: r['output'],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _status() {
    final s = session;
    final file = s == null
        ? null
        : _active == 0
        ? s.left
        : _active == 2
        ? s.output
        : s.right;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: border)),
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
                : '已保存',
            style: TextStyle(
              fontSize: 11,
              color: s?.dirty == true ? amber : muted,
            ),
          ),
          if (file != null) ...[
            const SizedBox(width: 16),
            Text(
              '${file.encoding.name.toUpperCase()} · ${file.eol}',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ],
          if (editor != null) ...[
            const SizedBox(width: 16),
            ValueListenableBuilder<CodeLineEditingValue>(
              valueListenable: editor!,
              builder: (context, value, _) => Text(
                '行 ${value.selection.extentIndex + 1}，列 ${value.selection.extentOffset + 1}',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ),
          ],
          const Spacer(),
          if (s?.error != null)
            Text(s!.error!, style: const TextStyle(color: red, fontSize: 11)),
          if (s?.diff?.timedOut == true)
            const Text(
              '差异计算已降级为较粗的区间',
              style: TextStyle(color: amber, fontSize: 11),
            ),
          const SizedBox(width: 12),
          const Text(
            'F7 差异 · F8 冲突 · ⌘/Ctrl S 保存',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10)),
  );
  Widget _banner(
    String text,
    VoidCallback dismiss, {
    VoidCallback? action,
  }) => Container(
    color: const Color(0xff3c3020),
    padding: const EdgeInsets.only(left: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: amber)),
        ),
        if (action != null)
          TextButton(onPressed: action, child: const Text('重新加载')),
        IconButton(onPressed: dismiss, icon: const Icon(Icons.close, size: 16)),
      ],
    ),
  );
  void _about() => showAboutDialog(
    context: context,
    applicationName: 'fmerge',
    applicationVersion: '0.1.0',
    applicationLegalese: '原生桌面文本比较与三方合并',
    children: [
      const SizedBox(height: 14),
      const SelectableText(
        'Git 外部工具配置请参阅工程 README。\n快捷键：F7 差异，F8 冲突，⌘/Ctrl F 查找，⌘/Ctrl G 跳转。\n\nDiff 核心基于 MIT 许可的 VS Code Myers 算法。',
      ),
    ],
  );
}
