import 'package:flutter/material.dart';

import '../core/custom_theme.dart';
import '../palette.dart';

/// 编辑保存在局部草稿中；取消不会改动正在使用的主题。
class ThemeEditor extends StatefulWidget {
  const ThemeEditor({super.key, required this.name, required this.palette});
  final String name;
  final AppPalette palette;

  @override
  State<ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<ThemeEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _nameFocus = FocusNode();
  final _colorFocus = {
    for (final color in ThemeColor.values) color.name: FocusNode(),
  };
  late final _name = TextEditingController(text: widget.name);
  late final _fields = {
    for (final entry in widget.palette.colors.entries)
      entry.key: TextEditingController(text: formatThemeColor(entry.value)),
  };

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    for (final focus in _colorFocus.values) {
      focus.dispose();
    }
    for (final field in _fields.values) {
      field.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Map<String, Color> get _validColors => {
    for (final entry in _fields.entries)
      if (_validColor(entry.value.text))
        entry.key: parseThemeColor(entry.value.text.trim()),
  };
  bool _validColor(String value) {
    try {
      parseThemeColor(value.trim());
      return true;
    } on FormatException {
      return false;
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) {
      try {
        CustomTheme.validateName(_name.text);
        final invalid = _fields.entries.firstWhere(
          (entry) => !_validColor(entry.value.text),
        );
        _colorFocus[invalid.key]!.requestFocus();
      } on FormatException {
        _nameFocus.requestFocus();
      }
      return;
    }
    Navigator.pop(
      context,
      CustomTheme(
        id: '',
        name: _name.text,
        base: widget.palette.theme,
        colors: _validColors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.palette.withColors(_validColors);
    return AlertDialog(
      title: const Text('编辑自定义主题'),
      content: SizedBox(
        width: 720,
        height: 470,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('custom-theme-name'),
                controller: _name,
                focusNode: _nameFocus,
                decoration: const InputDecoration(
                  labelText: '主题名称',
                  counterText: '',
                ),
                maxLength: 80,
                validator: (value) {
                  try {
                    CustomTheme.validateName(value);
                    return null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
              Text(
                '基于 ${widget.palette.theme.label} · ${preview.brightness == Brightness.light ? '亮色' : '暗色'}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppPalette.of(context).muted,
                ),
              ),
              const SizedBox(height: 12),
              _preview(preview),
              const SizedBox(height: 12),
              const Text(
                '输入 #RRGGBB 或 #RRGGBBAA（末两位为透明度）。取消会丢弃本次编辑。',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _colorInputs(preview),
                    ),
                  ),
                ),
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
          key: const ValueKey('save-custom-theme'),
          onPressed: _save,
          child: const Text('保存主题'),
        ),
      ],
    );
  }

  List<Widget> _colorInputs(AppPalette preview) => [
    for (final group in [
      ('界面', ThemeColor.values.take(10)),
      ('差异与选择', ThemeColor.values.skip(10).take(8)),
      ('语法高亮', ThemeColor.values.skip(18)),
    ]) ...[
      Text(group.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 520
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in group.$2)
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('theme-color-${color.name}'),
                    controller: _fields[color.name],
                    focusNode: _colorFocus[color.name],
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: color.label,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: preview.colors[color.name],
                            border: Border.all(
                              color: AppPalette.of(context).border,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    validator: (value) =>
                        _validColor(value ?? '') ? null : '请输入有效的十六进制颜色',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
    ],
  ];

  Widget _preview(AppPalette colors) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: colors.panel,
      border: Border.all(color: colors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DefaultTextStyle(
      style: TextStyle(
        color: colors.ink,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('代码与差异预览', style: TextStyle(color: colors.accent)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'final ',
                  style: TextStyle(color: colors.keyword),
                ),
                const TextSpan(text: 'message = '),
                TextSpan(
                  text: '"Hello"',
                  style: TextStyle(color: colors.string),
                ),
                const TextSpan(text: ';'),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: colors.removedBg,
            child: Text('− oldValue = 1;', style: TextStyle(color: colors.ink)),
          ),
          Container(
            width: double.infinity,
            color: colors.addedBg,
            child: Text('+ newValue = 2;', style: TextStyle(color: colors.ink)),
          ),
        ],
      ),
    ),
  );
}
