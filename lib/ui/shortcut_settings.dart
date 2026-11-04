import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/shortcuts.dart';
import '../palette.dart';

class ShortcutSettings extends StatefulWidget {
  const ShortcutSettings({super.key, required this.preferences});
  final ShortcutPreferences preferences;
  @override
  State<ShortcutSettings> createState() => _ShortcutSettingsState();
}

class _ShortcutSettingsState extends State<ShortcutSettings> {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '键盘快捷键',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () =>
                setState(() => widget.preferences.overrides.clear()),
            child: const Text('恢复全部默认'),
          ),
        ],
      ),
      Text(
        '点击键位后按下新组合。重复绑定会提示冲突；可清除不需要的快捷键。',
        style: TextStyle(fontSize: 12, color: AppPalette.of(context).muted),
      ),
      const SizedBox(height: 16),
      for (final group
          in AppCommand.values.map((command) => command.group).toSet()) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            group,
            style: TextStyle(
              color: AppPalette.of(context).accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final command in AppCommand.values.where(
          (value) => value.group == group,
        ))
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppPalette.of(context).border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    command.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton(
                  key: ValueKey('shortcut-${command.name}'),
                  onPressed: () async {
                    final result = await showDialog<_ShortcutEdit>(
                      context: context,
                      builder: (_) => _ShortcutRecorder(
                        command: command,
                        preferences: widget.preferences,
                      ),
                    );
                    if (result != null && mounted) {
                      setState(
                        () =>
                            widget.preferences.assign(command, result.binding),
                      );
                    }
                  },
                  child: Text(
                    widget.preferences[command]?.label ?? '未设置',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    ],
  );
}

class _ShortcutEdit {
  const _ShortcutEdit(this.binding);
  final KeyBinding? binding;
}

class _ShortcutRecorder extends StatefulWidget {
  const _ShortcutRecorder({required this.command, required this.preferences});
  final AppCommand command;
  final ShortcutPreferences preferences;
  @override
  State<_ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends State<_ShortcutRecorder> {
  KeyBinding? _candidate;
  String? _error;
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.pop(context);
        return KeyEventResult.handled;
      }
      if (KeyBinding.isModifier(event.logicalKey)) {
        return KeyEventResult.handled;
      }
      setState(() {
        _candidate = KeyBinding.capture(event.logicalKey);
        _error = widget.preferences.validate(widget.command, _candidate);
      });
      return KeyEventResult.handled;
    },
    child: AlertDialog(
      title: Text('设置“${widget.command.label}”快捷键'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请按下新的快捷键组合',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppPalette.of(context).bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _error == null
                      ? AppPalette.of(context).accent
                      : AppPalette.of(context).red,
                ),
              ),
              child: Text(
                _candidate?.label ?? '等待按键…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: AppPalette.of(context).red,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _ShortcutEdit(null)),
          child: const Text('清除快捷键'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _candidate == null || _error != null
              ? null
              : () => Navigator.pop(context, _ShortcutEdit(_candidate)),
          child: const Text('保存快捷键'),
        ),
      ],
    ),
  );
}
