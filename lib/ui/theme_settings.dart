import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/custom_theme.dart';
import '../core/settings.dart';
import '../palette.dart';
import 'theme_editor.dart';

class ThemeSettings extends StatefulWidget {
  const ThemeSettings({super.key, required this.settings});
  final Settings settings;
  @override
  State<ThemeSettings> createState() => _ThemeSettingsState();
}

class _ThemeSettingsState extends State<ThemeSettings> {
  Settings get s => widget.settings;
  bool _busy = false, _failed = false;
  String? _notice;
  static const _fileType = XTypeGroup(
    label: 'fmerge 主题 JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  void _message(String message, {bool failed = false}) {
    if (mounted) {
      setState(() {
        _notice = message;
        _failed = failed;
      });
    }
  }

  Future<void> _edit(Brightness brightness, {bool duplicate = false}) async {
    final current = s.customThemeFor(brightness);
    final name = current == null || duplicate
        ? '${current?.name ?? s.paletteFor(brightness).theme.label} 自定义'
        : current.name;
    final result = await showDialog<CustomTheme>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ThemeEditor(
        name: name.characters.take(80).toString(),
        palette: s.paletteFor(brightness),
      ),
    );
    if (result == null || !mounted) return;
    final saved = s.saveCustomTheme(
      id: duplicate ? null : current?.id,
      name: result.name,
      base: result.base,
      colors: result.colors,
    );
    _message('已保存主题：${saved.name}');
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [_fileType],
        confirmButtonText: '导入主题',
      );
      if (file == null || !mounted) return;
      if (await file.length() > 1024 * 1024) {
        throw const FormatException('主题文件不能超过 1 MB');
      }
      final contents = await file.readAsString();
      if (!mounted) return;
      final theme = s.importTheme(contents);
      _message(
        '已导入${theme.base.brightness == Brightness.light ? '亮色' : '暗色'}主题：${theme.name}',
      );
    } catch (error) {
      _message(
        '导入失败：${error is FormatException ? error.message : error}',
        failed: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(Brightness brightness) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final custom = s.customThemeFor(brightness);
      final palette = s.paletteFor(brightness);
      final theme =
          custom ??
          CustomTheme(
            id: '',
            name: palette.theme.label,
            base: palette.theme,
            colors: palette.colors,
          );
      final filename =
          '${theme.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')}.fmerge-theme.json';
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: [_fileType],
        confirmButtonText: '导出主题',
      );
      if (location == null) return;
      await XFile.fromData(
        utf8.encode(theme.encode()),
        mimeType: 'application/json',
        name: filename,
      ).saveTo(location.path);
      _message('已导出主题：${theme.name}');
    } catch (error) {
      _message('导出失败：$error', failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(CustomTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除自定义主题'),
        content: Text('删除“${theme.name}”后，将使用原先选择的内置主题。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      s.deleteCustomTheme(theme.id);
      _message('已删除主题：${theme.name}');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('外观模式', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('亮色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('暗色'),
              ),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (value) => s.setAppearance(mode: value.single),
          ),
          const SizedBox(height: 18),
          _themeChoice('亮色主题', Brightness.light),
          const SizedBox(height: 16),
          _themeChoice('暗色主题', Brightness.dark),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('import-theme'),
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined, size: 16),
            label: Text(_busy ? '正在处理主题…' : '导入主题 JSON'),
          ),
          const SizedBox(height: 8),
          Text(
            '亮暗主题分别记住。可自定义全部颜色；导入和导出使用 fmerge 主题 JSON 格式。',
            style: TextStyle(fontSize: 11, color: AppPalette.of(context).muted),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _notice!,
                key: const ValueKey('theme-notice'),
                style: TextStyle(
                  fontSize: 12,
                  color: _failed
                      ? AppPalette.of(context).red
                      : AppPalette.of(context).green,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _themeChoice(String label, Brightness brightness) {
    final custom = s.customThemeFor(brightness);
    final choices = [
      for (final theme in ColorTheme.values.where(
        (t) => t.brightness == brightness,
      ))
        (theme.name, theme.label, palettes[theme]!),
      for (final theme in s.customThemes.where(
        (t) => t.base.brightness == brightness,
      ))
        (theme.id, theme.name, theme.palette),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: ValueKey('theme-${brightness.name}'),
          width: double.infinity,
          child: DropdownButtonFormField<String>(
            key: ValueKey(s.selectedThemeId(brightness)),
            initialValue: s.selectedThemeId(brightness),
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final theme in choices)
                DropdownMenuItem(
                  value: theme.$1,
                  child: Row(
                    children: [
                      for (final color in [
                        theme.$3.bg,
                        theme.$3.accent,
                        theme.$3.green,
                        theme.$3.red,
                      ])
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: AppPalette.of(context).border,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          theme.$2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (theme.$1.startsWith('custom-'))
                        Text(
                          '自定义',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppPalette.of(context).muted,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (id) {
                    if (id != null) s.selectTheme(id, brightness);
                  },
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              key: ValueKey('edit-theme-${brightness.name}'),
              onPressed: _busy ? null : () => _edit(brightness),
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: Text(custom == null ? '自定义' : '编辑'),
            ),
            TextButton.icon(
              key: ValueKey('export-theme-${brightness.name}'),
              onPressed: _busy ? null : () => _export(brightness),
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('导出'),
            ),
            if (custom != null) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _edit(brightness, duplicate: true),
                child: const Text('另存为新主题'),
              ),
              IconButton(
                tooltip:
                    '删除${brightness == Brightness.light ? '亮色' : '暗色'}自定义主题',
                onPressed: _busy ? null : () => _delete(custom),
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
