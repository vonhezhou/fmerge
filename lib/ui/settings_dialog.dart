import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';
import '../palette.dart';
import 'git_settings.dart';
import 'shortcut_settings.dart';

enum SettingsSection { comparison, editor, shortcuts, git, files }

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    this.initialSection = SettingsSection.comparison,
  });
  final Settings settings;
  final SettingsSection initialSection;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _scroll = ScrollController();
  final _accessNoticeKey = GlobalKey();
  late final _contextLines = TextEditingController(
    text: '${widget.settings.contextLines}',
  );
  final _contextFocus = FocusNode();
  late SettingsSection _selected = widget.initialSection;
  bool _revoking = false;
  String? _accessNotice;
  bool _accessFailed = false;
  Settings get s => widget.settings;

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
    _contextLines.dispose();
    _contextFocus.dispose();
    super.dispose();
  }

  bool get _validContext {
    final value = int.tryParse(_contextLines.text);
    return value != null && value >= 0 && value <= 1000;
  }

  void _done() {
    if (!_validContext) {
      setState(() => _selected = SettingsSection.comparison);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _contextFocus.requestFocus();
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 880,
      height: 620,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '比较、显示、快捷键与 Git 集成',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭设置',
                  onPressed: _done,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: bg,
                  child: Container(
                    width: 154,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        for (final item in const [
                          (
                            SettingsSection.comparison,
                            Icons.compare_arrows,
                            '比较',
                          ),
                          (SettingsSection.editor, Icons.code, '编辑器与外观'),
                          (
                            SettingsSection.shortcuts,
                            Icons.keyboard_outlined,
                            '快捷键',
                          ),
                          (
                            SettingsSection.git,
                            Icons.account_tree_outlined,
                            'Git 集成',
                          ),
                          (
                            SettingsSection.files,
                            Icons.folder_outlined,
                            '文件与权限',
                          ),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              dense: true,
                              minLeadingWidth: 18,
                              horizontalTitleGap: 9,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                              selected: _selected == item.$1,
                              selectedTileColor: accent.withValues(alpha: .12),
                              selectedColor: accent,
                              leading: Icon(item.$2, size: 18),
                              title: Text(
                                item.$3,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () {
                                if (_scroll.hasClients) _scroll.jumpTo(0);
                                setState(() => _selected = item.$1);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(24),
                      child: switch (_selected) {
                        SettingsSection.comparison => _comparison(),
                        SettingsSection.editor => _editor(),
                        SettingsSection.shortcuts => ShortcutSettings(
                          preferences: s.shortcuts,
                        ),
                        SettingsSection.git => const GitSettings(),
                        SettingsSection.files => _files(),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '关闭后应用并记住设置',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
                FilledButton(onPressed: _done, child: const Text('完成')),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _heading(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(description, style: const TextStyle(fontSize: 12, color: muted)),
      ],
    ),
  );
  Widget _card(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Column(children: children),
      ),
    ),
  );
  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> change,
  ) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: subtitle.isEmpty
        ? null
        : Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
    value: value,
    onChanged: (value) => setState(() => change(value)),
  );
  Widget _comparison() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('比较与差异显示', '只影响差异显示；三方合并始终精确判断修改和冲突。'),
      _card([
        _toggle(
          '忽略行首、行尾空白',
          '忽略两端的空格与 Tab，保留行内空白差异。',
          s.ignoreWhitespace,
          (value) => s.ignoreWhitespace = value,
        ),
        const Divider(indent: 16, endIndent: 16),
        _toggle(
          '忽略大小写',
          '例如将 Name 与 name 视为相同。',
          s.ignoreCase,
          (value) => s.ignoreCase = value,
        ),
        const Divider(indent: 16, endIndent: 16),
        _toggle(
          '忽略换行符差异',
          '将 LF、CRLF 与 CR 视为相同，不改写文件。',
          s.ignoreEol,
          (value) => s.ignoreEol = value,
        ),
      ]),
      _card([
        _toggle(
          '仅显示差异及附近行',
          '记住此偏好；仅用于双栏比较，三方合并保持完整视图。',
          s.contextOnly,
          (value) => s.contextOnly = value,
        ),
        const Divider(indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text('差异前后各保留', style: TextStyle(fontSize: 12)),
              ),
              IconButton(
                tooltip: '减少上下文行数',
                onPressed: s.contextLines == 0
                    ? null
                    : () => setState(() {
                        s.contextLines--;
                        _contextLines.text = '${s.contextLines}';
                      }),
                icon: const Icon(Icons.remove, size: 16),
              ),
              SizedBox(
                width: 76,
                child: TextField(
                  key: const ValueKey('context-lines'),
                  controller: _contextLines,
                  focusNode: _contextFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    errorText: _validContext ? null : '0–1000',
                  ),
                  onChanged: (_) => setState(() {
                    if (_validContext) {
                      s.contextLines = int.parse(_contextLines.text);
                    }
                  }),
                ),
              ),
              IconButton(
                tooltip: '增加上下文行数',
                onPressed: s.contextLines == 1000
                    ? null
                    : () => setState(() {
                        s.contextLines++;
                        _contextLines.text = '${s.contextLines}';
                      }),
                icon: const Icon(Icons.add, size: 16),
              ),
              const Text('行', style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ),
      ]),
    ],
  );
  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('编辑器与外观', '常用显示操作也可从工具栏和更多菜单快速切换。'),
      _card([
        _toggle(
          '显示工具栏文字',
          '在操作图标下方显示名称。',
          s.toolbarLabels,
          (value) => s.toolbarLabels = value,
        ),
        const Divider(indent: 16, endIndent: 16),
        _toggle(
          '显示空白字符',
          '显示空格与制表符的位置，不改变比较规则。',
          s.showWhitespace,
          (value) => s.showWhitespace = value,
        ),
        const Divider(indent: 16, endIndent: 16),
        _toggle(
          '语法高亮',
          '根据各文件底部选择的语言显示代码颜色。',
          s.highlight,
          (value) => s.highlight = value,
        ),
      ]),
      _card([
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('编辑器字号', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text(
                    '${s.fontSize.round()} px',
                    style: const TextStyle(color: accent),
                  ),
                ],
              ),
              Slider(
                value: s.fontSize,
                min: 10,
                max: 24,
                divisions: 14,
                label: '${s.fontSize.round()}',
                onChanged: (value) => setState(() => s.fontSize = value),
              ),
            ],
          ),
        ),
      ]),
    ],
  );
  Widget _files() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('文件与权限', '安全保存与系统文件访问。'),
      _card([
        _toggle(
          '保存原文件备份（.bak）',
          '保存时在同目录保留上一次的文件内容。',
          s.backup,
          (value) => s.backup = value,
        ),
      ]),
      if (Platform.isMacOS)
        _card([
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已授权文件与目录',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '只记住你在系统选择器中授予的访问权限。撤销后，下次读写相关文件时需重新授权。',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _revoking ? null : _revokeAccess,
                  child: Text(_revoking ? '正在撤销文件授权…' : '撤销已授权文件与目录'),
                ),
                const SizedBox(height: 8),
                const Text(
                  '重启后完全生效。',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                if (_accessNotice != null)
                  Padding(
                    key: _accessNoticeKey,
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      _accessNotice!,
                      style: TextStyle(
                        color: _accessFailed ? red : green,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
    ],
  );
}
