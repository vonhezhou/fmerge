import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart' show Color;

import '../palette.dart';

Color parseThemeColor(Object? value) {
  if (value is! String ||
      !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)) {
    throw const FormatException('颜色需为 #RRGGBB 或 #RRGGBBAA');
  }
  final hex = value.substring(1);
  final rgba = int.parse(hex, radix: 16);
  return Color(
    hex.length == 6 ? 0xff000000 | rgba : (rgba >> 8) | ((rgba & 0xff) << 24),
  );
}

String formatThemeColor(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
  final alpha = argb >> 24;
  return '#$rgb${alpha == 255 ? '' : alpha.toRadixString(16).padLeft(2, '0')}';
}

/// 自定义主题保留内置基底；未配置的颜色继承基底，运行时使用固定配色快照。
class CustomTheme {
  CustomTheme({
    required this.id,
    required String name,
    required this.base,
    Map<String, Color> colors = const {},
  }) : name = validateName(name),
       colors = Map.unmodifiable(colors),
       palette = palettes[base]!.withColors(colors) {
    if (colors.keys.any(
      (key) => !ThemeColor.values.any((color) => color.name == key),
    )) {
      throw const FormatException('包含不支持的颜色字段');
    }
  }
  final String id, name;
  final ColorTheme base;
  final Map<String, Color> colors;
  final AppPalette palette;

  static String validateName(Object? value) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().characters.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('主题名称需为 1–80 个字符，不能包含控制字符');
    }
    return value.trim();
  }

  factory CustomTheme.fromJson(Object? value, {required String id}) {
    if (value is! Map<String, dynamic> ||
        value['format'] != 'fmerge-theme' ||
        value['version'] is! int ||
        value['version'] != 1) {
      throw const FormatException('需要版本为 1 的 fmerge-theme JSON 文件');
    }
    final base = ColorTheme.values
        .where((theme) => theme.name == value['base'])
        .firstOrNull;
    if (base == null) throw const FormatException('未知的内置基底主题');
    final raw = value['colors'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('colors 必须是颜色对象');
    }
    final colors = <String, Color>{};
    for (final entry in raw.entries) {
      if (!ThemeColor.values.any((color) => color.name == entry.key)) {
        throw FormatException('不支持的颜色字段：${entry.key}');
      }
      try {
        colors[entry.key] = parseThemeColor(entry.value);
      } on FormatException catch (error) {
        throw FormatException('${entry.key}：${error.message}');
      }
    }
    return CustomTheme(
      id: id,
      name: validateName(value['name']),
      base: base,
      colors: colors,
    );
  }

  factory CustomTheme.decode(String contents, {required String id}) =>
      CustomTheme.fromJson(jsonDecode(contents), id: id);

  Map<String, dynamic> toJson({bool includeId = false}) => {
    'format': 'fmerge-theme',
    'version': 1,
    if (includeId) 'id': id,
    'name': name,
    'base': base.name,
    'colors': palette.colors.map(
      (key, value) => MapEntry(key, formatThemeColor(value)),
    ),
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}
