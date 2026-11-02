import 'package:flutter/material.dart';

import '../core/files.dart';

class SaveFormat {
  const SaveFormat(this.encoding, this.eol);
  final TextEncoding encoding;
  final String? eol;
}

class FormatDialog extends StatefulWidget {
  const FormatDialog({super.key, required this.encoding});
  final TextEncoding encoding;
  @override
  State<FormatDialog> createState() => _FormatDialogState();
}

class _FormatDialogState extends State<FormatDialog> {
  late TextEncoding encoding = widget.encoding;
  String? eol;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('另存为 · 文本格式'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<TextEncoding>(
            initialValue: encoding,
            decoration: const InputDecoration(labelText: '编码'),
            items: [
              for (final e in TextEncoding.values)
                DropdownMenuItem(value: e, child: Text(e.label)),
            ],
            onChanged: (v) => setState(() => encoding = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: eol,
            decoration: const InputDecoration(labelText: '换行'),
            items: const [
              DropdownMenuItem(value: null, child: Text('保留原文逐行换行')),
              DropdownMenuItem(value: '\n', child: Text('LF')),
              DropdownMenuItem(value: '\r\n', child: Text('CRLF')),
              DropdownMenuItem(value: '\r', child: Text('CR')),
            ],
            onChanged: (v) => setState(() => eol = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, SaveFormat(encoding, eol)),
        child: const Text('选择保存位置'),
      ),
    ],
  );
}
