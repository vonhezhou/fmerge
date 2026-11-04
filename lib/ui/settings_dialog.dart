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
  final _scroll = ScrollController();
  final _accessNoticeKey = GlobalKey();
  bool _revoking = false;
  String? _accessNotice;
  bool _accessFailed = false;

  Future<void> _revokeAccess() async {
    if (_revoking) return;
    setState(() {
      _revoking = true;
      _accessNotice = null;
    });
    try {
      await const MethodChannel('fmerge/access').invokeMethod<void>('revoke');
      if (!mounted) return;
      setState(() {
        _accessFailed = false;
        _accessNotice = '已清除文件与目录授权书签；重启后完全生效。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _accessFailed = true;
        _accessNotice = '撤销目录授权失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() => _revoking = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = _accessNoticeKey.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: 1,
              duration: const Duration(milliseconds: 180),
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 470,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section('编辑器', Icons.code),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('显示工具栏文字'),
                  subtitle: const Text('在操作图标下方显示名称。'),
                  value: s.toolbarLabels,
                  onChanged: (value) => setState(() => s.toolbarLabels = value),
                ),
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
                const SizedBox(height: 16),
                _section('比较规则', Icons.compare_arrows),
                const Text(
                  '忽略规则只改变差异显示；三方合并始终精确判断修改和冲突。',
                  style: TextStyle(color: muted, fontSize: 12),
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
                const SizedBox(height: 16),
                _section('文件与权限', Icons.shield_outlined),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('保存原文件备份（.bak）'),
                  subtitle: const Text('保存时在同目录保留上一次的文件内容。'),
                  value: s.backup,
                  onChanged: (v) => setState(() => s.backup = v),
                ),
                if (Platform.isMacOS) ...[
                  TextButton(
                    onPressed: _revoking ? null : _revokeAccess,
                    child: Text(_revoking ? '正在撤销文件授权…' : '撤销已授权文件与目录'),
                  ),
                  const Text(
                    '重启后完全生效；下次读写相关目录时需重新授权。',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  if (_accessNotice != null)
                    Padding(
                      key: _accessNoticeKey,
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        _accessNotice!,
                        style: TextStyle(
                          color: _accessFailed ? red : green,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
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

  Widget _section(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(child: Divider()),
      ],
    ),
  );
}
