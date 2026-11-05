import 'dart:io';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/c.dart';
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
import '../core/shortcuts.dart';

String languageFor(String name) => switch (name.split('.').last.toLowerCase()) {
  'dart' => 'dart',
  'json' => 'json',
  'jsonc' => 'jsonc',
  'py' => 'python',
  'ts' || 'tsx' || 'js' || 'jsx' => 'typescript',
  'c' || 'h' => 'c',
  'cc' || 'cpp' || 'cxx' || 'hh' || 'hpp' || 'hxx' => 'cpp',
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
  // re_highlight 的 JSON 规则已包含行注释和块注释。
  'jsonc': langJson,
  'python': langPython,
  'typescript': langTypescript,
  'cpp': langCpp,
  'c': langC,
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

const languageLabels = {
  'text': '纯文本',
  'json': 'JSON',
  'jsonc': 'JSONC',
  'c': 'C',
  'cpp': 'C++',
  'rust': 'Rust',
  'dart': 'Dart',
  'python': 'Python',
  'typescript': 'JavaScript / TypeScript',
  'java': 'Java / Kotlin',
  'go': 'Go',
  'bash': 'Shell',
  'yaml': 'YAML',
  'xml': 'XML / HTML',
  'css': 'CSS / SCSS',
  'sql': 'SQL',
  'markdown': 'Markdown',
};

class LanguageMenu extends StatelessWidget {
  const LanguageMenu({
    super.key,
    required this.name,
    required this.value,
    required this.onChanged,
  });
  final String name;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final detected = languageFor(name);
    final label = languageLabels[value ?? detected] ?? '纯文本';
    return PopupMenuButton<String>(
      tooltip: '选择语言或格式（仅影响语法高亮）',
      initialValue: value ?? 'auto',
      onSelected: (value) => onChanged(value == 'auto' ? null : value),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'auto',
          checked: value == null,
          child: Text('自动识别（${languageLabels[detected]}）'),
        ),
        const PopupMenuDivider(),
        for (final entry in languageLabels.entries)
          CheckedPopupMenuItem(
            value: entry.key,
            checked: value == entry.key,
            child: Text(entry.value),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 95),
                  child: Text(
                    value == null ? '自动 · $label' : label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: constraints.maxWidth.clamp(0.0, 16.0),
                color: AppPalette.of(context).muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    this.onStage,
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
  final VoidCallback? onStage;
  final double reservedFindHeight;
  final ValueChanged<CodeLineEditingValue>? onChanged;
  @override
  State<CodePane> createState() => _CodePaneState();
}

class _CodePaneState extends State<CodePane> {
  VoidCallback? get onSave => widget.onSave;
  late final _menu = ContextMenuControllerImpl(
    widget.readOnly,
    onStage: widget.onStage,
  );
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
    _menu.onStage = widget.onStage;
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
    color: AppPalette.of(context).panel,
    child: CodeEditor(
      controller: controller,
      scrollController: scroll,
      focusNode: focus,
      findController: find,
      onChanged: onChanged,
      readOnly: readOnly,
      wordWrap: settings.wordWrap,
      autofocus: false,
      shortcutsActivatorsBuilder: _AppEditorShortcuts(settings.shortcuts),
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
        textColor: AppPalette.of(context).ink,
        backgroundColor: AppPalette.of(context).panel,
        cursorColor: AppPalette.of(context).accent,
        selectionColor: AppPalette.of(context).selection,
        cursorLineColor: focus.hasFocus
            ? AppPalette.of(context).accent.withValues(alpha: .5)
            : AppPalette.of(context).border,
        codeTheme: !settings.highlight || !_languages.containsKey(language)
            ? null
            : CodeHighlightTheme(
                languages: {
                  language: CodeHighlightThemeMode(
                    mode: _languages[language]!,
                    // 按 UTF-16 代码单元计数，并非文件字节数。高亮仍需全文解析和
                    // 构建逐行结果，后台执行不会消除 CPU 与内存成本；超限改用纯文本，
                    // 保留差异标记、编辑和保存。放宽前需单独测量开启高亮的表现。
                    maxSize: 4 * 1024 * 1024,
                    maxLineLength: 32000,
                  ),
                },
                theme: atomOneDarkTheme.map(
                  (key, _) => MapEntry(
                    key,
                    TextStyle(color: AppPalette.of(context).tokenColor(key)),
                  ),
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
              color: AppPalette.of(context).muted,
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
  Widget build(BuildContext context) {
    final value = controller.value;
    final invalidRegex =
        value?.option.regex == true && value?.option.regExp == null;
    final result = value?.result;
    final hasMatches =
        !invalidRegex &&
        value?.searching == false &&
        result != null &&
        !result.dirty &&
        result.matches.isNotEmpty;
    final status = value == null || value.option.pattern.isEmpty
        ? ''
        : invalidRegex
        ? '正则无效'
        : value.searching || result?.dirty == true
        ? '查找中…'
        : hasMatches
        ? '${result.index + 1}/${result.matches.length}'
        : '无结果';
    return Container(
      height: preferredSize.height,
      color: AppPalette.of(context).elevated,
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
                    decoration: InputDecoration(
                      hintText: '查找',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => controller.nextMatch(),
                  ),
                ),
                Tooltip(
                  message: invalidRegex ? '正则表达式格式无效，请检查后重试' : status,
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      color: invalidRegex
                          ? AppPalette.of(context).red
                          : AppPalette.of(context).muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '区分大小写',
                  onPressed: controller.toggleCaseSensitive,
                  icon: Icon(
                    Icons.text_fields,
                    size: 16,
                    color: controller.value?.option.caseSensitive == true
                        ? AppPalette.of(context).accent
                        : AppPalette.of(context).muted,
                  ),
                ),
                IconButton(
                  tooltip: '正则表达式',
                  onPressed: controller.toggleRegex,
                  icon: Icon(
                    Icons.data_object,
                    size: 16,
                    color: controller.value?.option.regex == true
                        ? AppPalette.of(context).accent
                        : AppPalette.of(context).muted,
                  ),
                ),
                IconButton(
                  tooltip: '上一处',
                  onPressed: hasMatches ? controller.previousMatch : null,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                ),
                IconButton(
                  tooltip: '下一处',
                  onPressed: hasMatches ? controller.nextMatch : null,
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
                      decoration: InputDecoration(
                        hintText: '替换为',
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: !readOnly && hasMatches
                        ? controller.replaceMatch
                        : null,
                    child: const Text('替换'),
                  ),
                  TextButton(
                    onPressed: !readOnly && hasMatches
                        ? controller.replaceAllMatches
                        : null,
                    child: const Text('全部替换'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ContextMenuControllerImpl implements SelectionToolbarController {
  ContextMenuControllerImpl(this.readOnly, {this.onStage});
  bool readOnly;
  VoidCallback? onStage;
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
          (MediaQuery.sizeOf(context).height - 240).clamp(0, double.infinity),
        ),
        child: Material(
          elevation: 8,
          color: AppPalette.of(context).elevated,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                if (onStage != null) ...[
                  const Divider(),
                  TextButton(
                    onPressed: () {
                      hide(context);
                      onStage!();
                    },
                    child: const Text('暂存所选代码块'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }
}

/// 编辑器与工作台使用同一份键位；已分配给 App 操作的键不再被光标快捷键吞掉。
class _AppEditorShortcuts extends CodeShortcutsActivatorsBuilder {
  _AppEditorShortcuts(this.preferences)
    : signature = AppCommand.values
          .map((command) => preferences[command]?.signature ?? '-')
          .join('|');
  final ShortcutPreferences preferences;
  final String signature;
  @override
  bool operator ==(Object other) =>
      other is _AppEditorShortcuts && other.signature == signature;
  @override
  int get hashCode => signature.hashCode;
  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    final command = const {
      CodeShortcutType.save: AppCommand.save,
      CodeShortcutType.find: AppCommand.find,
      CodeShortcutType.replace: AppCommand.replace,
      CodeShortcutType.undo: AppCommand.undo,
      CodeShortcutType.redo: AppCommand.redo,
      CodeShortcutType.copy: AppCommand.copy,
      CodeShortcutType.cut: AppCommand.cut,
      CodeShortcutType.paste: AppCommand.paste,
      CodeShortcutType.selectAll: AppCommand.selectAll,
    }[type];
    if (command != null) {
      final binding = preferences[command];
      return binding == null ? [] : [binding.activator];
    }
    final defaults = const DefaultCodeShortcutsActivatorsBuilder().build(type);
    return defaults?.where((activator) {
      if (activator is! SingleActivator) return true;
      return !AppCommand.values.any((command) {
        final binding = preferences[command]?.activator;
        return binding != null &&
            binding.trigger == activator.trigger &&
            binding.control == activator.control &&
            binding.meta == activator.meta &&
            binding.shift == activator.shift &&
            binding.alt == activator.alt;
      });
    }).toList();
  }
}
