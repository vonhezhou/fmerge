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
  final encodings = <TextEditingController, TextEncoding?>{};
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

  Future<void> browsePair() async {
    try {
      final files = await openFiles(confirmButtonText: '选择两个文件');
      if (!mounted || files.isEmpty) return;
      setState(() {
        if (files.length != 2) {
          error = '请一次选择恰好两个文件';
        } else {
          left.text = files[0].path;
          right.text = files[1].path;
          error = null;
        }
      });
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
        leftEncoding: encodings[left],
        rightEncoding: encodings[right],
        baseEncoding: encodings[base],
        outputEncoding: encodings[output],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: busy ? null : browsePair,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('同时选择两个文件'),
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          final path = left.text;
                          left.text = right.text;
                          right.text = path;
                          final encoding = encodings[left];
                          encodings[left] = encodings[right];
                          encodings[right] = encoding;
                        }),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('交换左右'),
                ),
              ],
            ),
            if (merge) field('共同祖先 · Base', base),
            field(merge ? '左侧输入 · --local' : '左侧 · 原始文件', left),
            field(merge ? '右侧输入 · --remote' : '右侧 · 修改文件', right),
            field('输出位置（可留空，保存时选择）', output, save: true),
            const Text(
              '编码可逐文件选择。自动：按 BOM 识别 UTF-8 / UTF-16，无 BOM 按 UTF-8。\n'
              '旧编码请手动选择；不能无损转换时会报错。GB18030 请先转为 UTF-8。\n'
              '原文件仅在保存时写入。',
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
        SizedBox(
          width: 155,
          child: DropdownButtonFormField<TextEncoding?>(
            key: ValueKey((controller, encodings[controller])),
            initialValue: encodings[controller],
            decoration: InputDecoration(labelText: save ? '已有输出编码' : '读取编码'),
            isExpanded: true,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('自动（BOM / UTF-8）'),
              ),
              for (final encoding in TextEncoding.values)
                DropdownMenuItem(value: encoding, child: Text(encoding.label)),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() => encodings[controller] = value),
          ),
        ),
      ],
    ),
  );
}
