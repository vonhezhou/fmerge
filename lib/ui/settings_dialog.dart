import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';
import '../core/diff.dart';
import '../palette.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settings});
  final Settings settings;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('编辑器字号'),
                Expanded(
                  child: Slider(
                    value: s.fontSize,
                    min: 10,
                    max: 24,
                    divisions: 14,
                    label: s.fontSize.round().toString(),
                    onChanged: (v) => setState(() => s.fontSize = v),
                  ),
                ),
                Text('${s.fontSize.round()}'),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('语法高亮'),
              value: s.highlight,
              onChanged: (v) => setState(() => s.highlight = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示空格与制表符'),
              value: s.showWhitespace,
              onChanged: (v) => setState(() => s.showWhitespace = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('保存原文件备份（.bak）'),
              value: s.backup,
              onChanged: (v) => setState(() => s.backup = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('忽略大小写'),
              value: s.ignoreCase,
              onChanged: (v) => setState(() => s.ignoreCase = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('忽略换行符差异'),
              value: s.ignoreEol,
              onChanged: (v) => setState(() => s.ignoreEol = v),
            ),
            Row(
              children: [
                const Text('空白比较'),
                const Spacer(),
                DropdownButton<WhitespaceMode>(
                  value: s.whitespace,
                  items: const [
                    DropdownMenuItem(
                      value: WhitespaceMode.exact,
                      child: Text('精确比较'),
                    ),
                    DropdownMenuItem(
                      value: WhitespaceMode.trailing,
                      child: Text('忽略行尾空白'),
                    ),
                    DropdownMenuItem(
                      value: WhitespaceMode.all,
                      child: Text('忽略空格与 Tab'),
                    ),
                  ],
                  onChanged: (v) => setState(() => s.whitespace = v!),
                ),
              ],
            ),
            if (Platform.isMacOS)
              TextButton(
                onPressed: () async {
                  await const MethodChannel('fmerge/access')
                      .invokeMethod<void>('revoke');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已清除目录授权书签；重启后完全生效')),
                    );
                  }
                },
                child: const Text('撤销已授权目录（重启后完全生效）'),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '忽略规则只改变差异显示；三方合并始终精确判断修改和冲突。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
