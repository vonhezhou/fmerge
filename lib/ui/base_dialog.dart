import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../core/files.dart';
import '../core/settings.dart';
import 'code_pane.dart';
import 'document_status.dart';

class BaseDialog extends StatefulWidget {
  const BaseDialog({
    super.key,
    required this.file,
    required this.settings,
    this.language,
    this.onLanguageChanged,
    this.onEncodingChanged,
  });
  final TextFile file;
  final Settings settings;
  final String? language;
  final ValueChanged<String?>? onLanguageChanged;
  final ValueChanged<TextEncoding?>? onEncodingChanged;
  @override
  State<BaseDialog> createState() => _BaseDialogState();
}

class _BaseDialogState extends State<BaseDialog> {
  late final controller = CodeLineEditingController.fromText(widget.file.text);
  late final find = CodeFindController(controller);
  final focus = FocusNode(), scroll = CodeScrollController();
  late String? language = widget.language;
  @override
  void dispose() {
    controller.dispose();
    find.dispose();
    focus.dispose();
    scroll.verticalScroller.dispose();
    scroll.horizontalScroller.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 850,
      height: 600,
      child: Column(
        children: [
          ListTile(
            title: const Row(
              children: [
                Text('共同祖先 · Base'),
                SizedBox(width: 10),
                Text('只读', style: TextStyle(fontSize: 11)),
              ],
            ),
            subtitle: Tooltip(
              message: widget.file.path ?? '未命名',
              child: Text(
                widget.file.path ?? '未命名',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '在共同祖先中查找',
                  onPressed: find.findMode,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: '关闭共同祖先',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: CodePane(
              controller: controller,
              settings: widget.settings,
              focus: focus,
              scroll: scroll,
              language: language ?? languageFor(widget.file.name),
              readOnly: true,
              find: find,
            ),
          ),
          DocumentStatus(
            file: widget.file,
            controller: controller,
            language: language,
            onLanguageChanged: (value) {
              setState(() => language = value);
              widget.onLanguageChanged?.call(value);
            },
            onEncodingChanged: widget.onEncodingChanged,
          ),
        ],
      ),
    ),
  );
}
