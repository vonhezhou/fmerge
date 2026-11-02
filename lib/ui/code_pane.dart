import 'dart:io';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../palette.dart';
import '../core/settings.dart';

String languageFor(String name) => switch (name.split('.').last.toLowerCase()) {
  'dart' => 'dart',
  'json' || 'jsonc' => 'json',
  'py' => 'python',
  'ts' || 'tsx' || 'js' || 'jsx' => 'typescript',
  'c' || 'cc' || 'cpp' || 'h' || 'hpp' => 'cpp',
  'java' || 'kt' => 'java',
  'go' => 'go',
  'rs' => 'rust',
  'sh' || 'zsh' || 'bash' => 'bash',
  'yml' || 'yaml' => 'yaml',
  'xml' || 'html' || 'svg' => 'xml',
  'css' || 'scss' => 'css',
  'sql' => 'sql',
  'md' => 'markdown',
  _ => 'text',
};
final Map<String, Mode> _languages = {
  'dart': langDart,
  'json': langJson,
  'python': langPython,
  'typescript': langTypescript,
  'cpp': langCpp,
  'java': langJava,
  'go': langGo,
  'rust': langRust,
  'bash': langBash,
  'yaml': langYaml,
  'xml': langXml,
  'css': langCss,
  'sql': langSql,
  'markdown': langMarkdown,
};

class CodePane extends StatefulWidget {
  const CodePane({
    super.key,
    required this.controller,
    required this.settings,
    required this.focus,
    required this.scroll,
    required this.language,
    required this.readOnly,
    required this.find,
    this.undo,
    this.redo,
    this.onChanged,
    this.onSave,
    this.reservedFindHeight = 0,
  });
  final CodeLineEditingController controller;
  final Settings settings;
  final FocusNode focus;
  final CodeScrollController scroll;
  final String language;
  final bool readOnly;
  final CodeFindController find;
  final VoidCallback? undo, redo;
  final VoidCallback? onSave;
  final double reservedFindHeight;
  final ValueChanged<CodeLineEditingValue>? onChanged;
  @override
  State<CodePane> createState() => _CodePaneState();
}

class _CodePaneState extends State<CodePane> {
  VoidCallback? get onSave => widget.onSave;
  late final _menu = ContextMenuControllerImpl(widget.readOnly);
  CodeLineEditingController get controller => widget.controller;
  Settings get settings => widget.settings;
  FocusNode get focus => widget.focus;
  CodeScrollController get scroll => widget.scroll;
  String get language => widget.language;
  bool get readOnly => widget.readOnly;
  CodeFindController get find => widget.find;
  VoidCallback? get undo => widget.undo;
  VoidCallback? get redo => widget.redo;
  ValueChanged<CodeLineEditingValue>? get onChanged => widget.onChanged;
  @override
  void didUpdateWidget(CodePane old) {
    super.didUpdateWidget(old);
    if (old.readOnly != readOnly) {
      _menu.hide(context);
      _menu.readOnly = readOnly;
    }
  }

  @override
  void dispose() {
    _menu.hide(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: panel,
    child: CodeEditor(
      controller: controller,
      scrollController: scroll,
      focusNode: focus,
      findController: find,
      onChanged: onChanged,
      readOnly: readOnly,
      wordWrap: false,
      autofocus: false,
      maxLengthSingleLineRendering: 32000,
      padding: EdgeInsets.fromLTRB(
        12,
        12 +
            (widget.reservedFindHeight -
                    (find.value == null
                        ? 0
                        : find.value!.replaceMode
                        ? 84
                        : 44))
                .clamp(0, 84),
        16,
        12,
      ),
      chunkAnalyzer: const NonCodeChunkAnalyzer(),
      shortcutOverrideActions: {
        if (onSave != null)
          CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
            onInvoke: (_) {
              onSave!();
              return null;
            },
          ),
        if (undo != null)
          CodeShortcutUndoIntent: CallbackAction<CodeShortcutUndoIntent>(
            onInvoke: (_) {
              undo!();
              return null;
            },
          ),
        if (redo != null)
          CodeShortcutRedoIntent: CallbackAction<CodeShortcutRedoIntent>(
            onInvoke: (_) {
              redo!();
              return null;
            },
          ),
      },
      findBuilder: (context, controller, readonly) => controller.value == null
          ? const PreferredSize(
              preferredSize: Size.zero,
              child: SizedBox.shrink(),
            )
          : _FindPanel(controller, readonly),
      toolbarController: _menu,
      style: CodeEditorStyle(
        fontSize: settings.fontSize,
        fontHeight: 1.65,
        fontFamily: Platform.isMacOS
            ? 'Menlo'
            : Platform.isWindows
            ? 'Consolas'
            : 'monospace',
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei',
          'monospace',
        ],
        textColor: ink,
        backgroundColor: panel,
        cursorColor: accent,
        selectionColor: const Color(0xff365274),
        cursorLineColor: border,
        codeTheme: !settings.highlight || !_languages.containsKey(language)
            ? null
            : CodeHighlightTheme(
                languages: {
                  language: CodeHighlightThemeMode(
                    mode: _languages[language]!,
                    maxSize: 4 * 1024 * 1024,
                    maxLineLength: 32000,
                  ),
                },
                theme: atomOneDarkTheme.map(
                  (key, _) => MapEntry(key, TextStyle(color: tokenColor(key))),
                ),
              ),
      ),
      indicatorBuilder: (context, editing, chunks, notifier) =>
          DefaultCodeLineNumber(
            controller: editing,
            notifier: notifier,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: settings.fontSize - 1,
              color: muted,
            ),
          ),
    ),
  );
}

class _FindPanel extends StatelessWidget implements PreferredSizeWidget {
  const _FindPanel(this.controller, this.readOnly);
  final CodeFindController controller;
  final bool readOnly;
  @override
  Size get preferredSize =>
      Size.fromHeight(controller.value?.replaceMode == true ? 84 : 44);
  @override
  Widget build(BuildContext context) => Container(
    color: elevated,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.findInputController,
                  focusNode: controller.findInputFocusNode,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '查找',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => controller.nextMatch(),
                ),
              ),
              Text(
                '${(controller.value?.result?.index ?? -1) + 1}/${controller.value?.result?.matches.length ?? 0}',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              IconButton(
                tooltip: '区分大小写',
                onPressed: controller.toggleCaseSensitive,
                icon: Icon(
                  Icons.text_fields,
                  size: 16,
                  color: controller.value?.option.caseSensitive == true
                      ? accent
                      : muted,
                ),
              ),
              IconButton(
                tooltip: '正则表达式',
                onPressed: controller.toggleRegex,
                icon: Icon(
                  Icons.data_object,
                  size: 16,
                  color: controller.value?.option.regex == true
                      ? accent
                      : muted,
                ),
              ),
              IconButton(
                tooltip: '上一处',
                onPressed: controller.previousMatch,
                icon: const Icon(Icons.keyboard_arrow_up, size: 16),
              ),
              IconButton(
                tooltip: '下一处',
                onPressed: controller.nextMatch,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              ),
              if (!readOnly)
                IconButton(
                  tooltip: '替换',
                  onPressed: controller.toggleMode,
                  icon: const Icon(Icons.find_replace, size: 16),
                ),
              IconButton(
                tooltip: '关闭查找',
                onPressed: controller.close,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
        if (controller.value?.replaceMode == true)
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.replaceInputController,
                    focusNode: controller.replaceInputFocusNode,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '替换为',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: readOnly ? null : controller.replaceMatch,
                  child: const Text('替换'),
                ),
                TextButton(
                  onPressed: readOnly ? null : controller.replaceAllMatches,
                  child: const Text('全部替换'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class ContextMenuControllerImpl implements SelectionToolbarController {
  ContextMenuControllerImpl(this.readOnly);
  bool readOnly;
  OverlayEntry? _entry;
  @override
  void hide(BuildContext context) {
    _entry?.remove();
    _entry = null;
  }

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    hide(context);
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: anchors.primaryAnchor.dx.clamp(
          0,
          MediaQuery.sizeOf(context).width - 240,
        ),
        top: anchors.primaryAnchor.dy.clamp(
          0,
          MediaQuery.sizeOf(context).height - 60,
        ),
        child: Material(
          elevation: 8,
          color: elevated,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  controller.copy();
                  hide(context);
                },
                child: const Text('复制'),
              ),
              if (!readOnly)
                TextButton(
                  onPressed: () {
                    controller.cut();
                    hide(context);
                  },
                  child: const Text('剪切'),
                ),
              if (!readOnly)
                TextButton(
                  onPressed: () {
                    controller.paste();
                    hide(context);
                  },
                  child: const Text('粘贴'),
                ),
              TextButton(
                onPressed: () {
                  controller.selectAll();
                  hide(context);
                },
                child: const Text('全选'),
              ),
            ],
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }
}
