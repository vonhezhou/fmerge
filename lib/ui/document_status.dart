import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../core/files.dart';
import '../palette.dart';
import 'code_pane.dart';

/// 每个文档独立显示格式，避免焦点切换后不清楚当前修改的是哪个文件。
class DocumentStatus extends StatelessWidget {
  const DocumentStatus({
    super.key,
    required this.file,
    required this.controller,
    required this.language,
    required this.onLanguageChanged,
    required this.onEncodingChanged,
    this.encoding,
    this.eol,
    this.onEolChanged,
    this.saveEncoding = false,
    this.languageName,
    this.changeSummary,
    this.changeTooltip,
  });
  final TextFile file;
  final CodeLineEditingController controller;
  final String? language;
  final String? languageName;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<TextEncoding?>? onEncodingChanged;
  final ValueChanged<String?>? onEolChanged;
  final TextEncoding? encoding;
  final String? eol;
  final bool saveEncoding;
  final String? changeSummary, changeTooltip;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: AppPalette.of(context).panel,
      border: Border(top: BorderSide(color: AppPalette.of(context).border)),
    ),
    child: Row(
      children: [
        PopupMenuButton<String>(
          tooltip: saveEncoding ? '保存编码' : '编码 · 按所选编码重新读取',
          enabled: onEncodingChanged != null,
          onSelected: (value) => onEncodingChanged!(
            value == 'auto' ? null : TextEncoding.values.byName(value),
          ),
          itemBuilder: (_) => [
            if (!saveEncoding)
              const PopupMenuItem(
                value: 'auto',
                child: Text('自动识别（BOM / UTF-8）'),
              ),
            for (final value in TextEncoding.values)
              CheckedPopupMenuItem(
                value: value.name,
                checked: value == (encoding ?? file.encoding),
                child: Text(value.label),
              ),
          ],
          child: _value(context, (encoding ?? file.encoding).label),
        ),
        PopupMenuButton<String>(
          tooltip: '换行 · 保存时统一整份文件',
          enabled: onEolChanged != null,
          onSelected: (value) =>
              onEolChanged!(value == 'preserve' ? null : value),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'preserve',
              checked: eol == null,
              child: const Text('保留原文逐行换行'),
            ),
            for (final entry in const {
              '\n': 'LF',
              '\r\n': 'CRLF',
              '\r': 'CR',
            }.entries)
              CheckedPopupMenuItem(
                value: entry.key,
                checked: eol == entry.key,
                child: Text(entry.value),
              ),
          ],
          child: _value(
            context,
            eol == null
                ? file.eol
                : {'\n': 'LF', '\r\n': 'CRLF', '\r': 'CR'}[eol]!,
          ),
        ),
        ValueListenableBuilder<CodeLineEditingValue>(
          valueListenable: controller,
          builder: (_, _, _) => PopupMenuButton<int>(
            tooltip: 'Tab 显示宽度（不改写文件）',
            onSelected: (value) => controller.displayTabSize = value,
            itemBuilder: (_) => [
              for (final size in [2, 4, 8])
                CheckedPopupMenuItem(
                  value: size,
                  checked: controller.displayTabSize == size,
                  child: Text('Tab $size'),
                ),
            ],
            child: _value(context, 'Tab ${controller.displayTabSize}'),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: LanguageMenu(
              name: languageName ?? file.path ?? file.name,
              value: language,
              onChanged: onLanguageChanged,
            ),
          ),
        ),
        if (changeSummary != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: changeTooltip ?? '',
              child: Text(
                changeSummary!,
                style: TextStyle(
                  fontSize: 10,
                  color: AppPalette.of(context).muted,
                ),
              ),
            ),
          ),
        ValueListenableBuilder<CodeLineEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => Tooltip(
            message:
                '行 ${value.selection.extentIndex + 1}，列 ${value.selection.extentOffset + 1}',
            child: Text(
              'Ln ${value.selection.extentIndex + 1}',
              style: TextStyle(
                fontSize: 10,
                color: AppPalette.of(context).muted,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _value(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(fontSize: 10, color: AppPalette.of(context).muted),
        ),
        Icon(
          Icons.arrow_drop_down,
          size: 14,
          color: AppPalette.of(context).muted,
        ),
      ],
    ),
  );
}
