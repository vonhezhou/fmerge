import 'package:flutter/material.dart';

import '../core/files.dart';

class SaveFormat {
  const SaveFormat(this.encoding, this.eol);
  final TextEncoding encoding;
  final String? eol;
}

class FormatDialog extends StatefulWidget {
  const FormatDialog({super.key, required this.encoding, this.eol});
  final TextEncoding encoding;
  final String? eol;
  @override
  State<FormatDialog> createState() => _FormatDialogState();
}

class _FormatDialogState extends State<FormatDialog> {
  late TextEncoding encoding = widget.encoding;
  late String? eol = widget.eol;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('另存为 · 文本格式'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<TextEncoding>(
              initialValue: encoding,
              isExpanded: true,
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
              isExpanded: true,
              decoration: const InputDecoration(labelText: '换行'),
              items: const [
                DropdownMenuItem(value: null, child: Text('保留原文逐行换行')),
                DropdownMenuItem(value: '\n', child: Text('LF')),
                DropdownMenuItem(value: '\r\n', child: Text('CRLF')),
                DropdownMenuItem(value: '\r', child: Text('CR')),
              ],
              onChanged: (v) => setState(() => eol = v),
            ),
            const SizedBox(height: 16),
            Text(
              '转换会检查文本是否能无损保存；选择 LF、CRLF 或 CR 将统一整份文件的换行。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
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
