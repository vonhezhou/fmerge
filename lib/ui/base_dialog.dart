import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../core/files.dart';
import '../core/settings.dart';
import 'code_pane.dart';

class BaseDialog extends StatefulWidget {
  const BaseDialog({super.key, required this.file, required this.settings});
  final TextFile file;
  final Settings settings;
  @override
  State<BaseDialog> createState() => _BaseDialogState();
}

class _BaseDialogState extends State<BaseDialog> {
  late final controller = CodeLineEditingController.fromText(widget.file.text);
  late final find = CodeFindController(controller);
  final focus = FocusNode(), scroll = CodeScrollController();
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
            title: const Text('共同祖先 · Base'),
            subtitle: Text(widget.file.path ?? '未命名'),
            trailing: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Expanded(
            child: CodePane(
              controller: controller,
              settings: widget.settings,
              focus: focus,
              scroll: scroll,
              language: languageFor(widget.file.name),
              readOnly: true,
              find: find,
            ),
          ),
        ],
      ),
    ),
  );
}
