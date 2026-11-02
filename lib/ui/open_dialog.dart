import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../core/launch.dart';
import '../core/access.dart';
import '../core/files.dart';
import '../session.dart';
import '../palette.dart';

class OpenDialog extends StatefulWidget {
  const OpenDialog({super.key, this.merge = false, this.nativeAccess = false});
  final bool nativeAccess;
  final bool merge;
  @override
  State<OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends State<OpenDialog> {
  late bool merge = widget.merge;
  final left = TextEditingController(),
      right = TextEditingController(),
      base = TextEditingController(),
      output = TextEditingController();
  String? error;
  TextEncoding? inputEncoding;
  bool busy = false;
  @override
  void dispose() {
    left.dispose();
    right.dispose();
    base.dispose();
    output.dispose();
    super.dispose();
  }

  Future<void> browse(
    TextEditingController controller, {
    bool save = false,
  }) async {
    try {
      final path = save
          ? (await getSaveLocation(
              suggestedName: 'merged.txt',
              confirmButtonText: '选择输出位置',
            ))?.path
          : (await openFile(confirmButtonText: '打开文本文件'))?.path;
      if (path != null && mounted) setState(() => controller.text = path);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> submit() async {
    if (left.text.trim().isEmpty ||
        right.text.trim().isEmpty ||
        merge && base.text.trim().isEmpty) {
      setState(() => error = '请选择完整的输入文件');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.nativeAccess) {
        for (final input in [
          left.text.trim(),
          right.text.trim(),
          if (merge) base.text.trim(),
        ]) {
          await DirectoryAccess.read(input);
        }
        if (output.text.trim().isNotEmpty) {
          await DirectoryAccess.write(output.text.trim());
        }
      }
      final session = await CompareSession.open(
        LaunchOptions(
          left: left.text.trim(),
          right: right.text.trim(),
          base: merge ? base.text.trim() : null,
          output: output.text.trim().isEmpty ? null : output.text.trim(),
        ),
        encoding: inputEncoding,
      );
      if (!mounted) {
        session.dispose();
        return;
      }
      Navigator.pop(context, session);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: panel,
    title: Text(merge ? '打开三方合并' : '打开文件比较'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('文件比较')),
                ButtonSegment(value: true, label: Text('三方合并')),
              ],
              selected: {merge},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() => merge = v.first),
            ),
            const SizedBox(height: 18),
            if (merge) field('共同祖先 · Base', base),
            field(merge ? '本地文件 · Local' : '左侧 · 原始文件', left),
            field(merge ? '远端文件 · Remote' : '右侧 · 修改文件', right),
            field('输出位置（可留空，保存时选择）', output, save: true),
            DropdownButton<TextEncoding?>(
              hint: const Text('编码：自动识别 UTF-8 / UTF-16'),
              value: inputEncoding,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('编码：自动识别 UTF-8 / UTF-16'),
                ),
                DropdownMenuItem(
                  value: TextEncoding.latin1,
                  child: Text('编码：Latin-1（旧式西文文件）'),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => inputEncoding = v),
            ),
            const Text(
              '原文件仅在你保存时写入；无法识别的编码会报错，不会替换字符。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? '正在打开…' : '打开'),
      ),
    ],
  );
  Widget field(
    String title,
    TextEditingController controller, {
    bool save = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            decoration: InputDecoration(labelText: title),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (_) => submit(),
          ),
        ),
        IconButton(
          tooltip: save ? '选择输出位置' : '选择文件',
          onPressed: busy ? null : () => browse(controller, save: save),
          icon: const Icon(Icons.folder_open_outlined, size: 20),
        ),
      ],
    ),
  );
}
