import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fmerge/core/custom_theme.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/palette.dart';

void main() {
  test('颜色使用 RGB 或 RGBA，透明度放在末尾，所有通道可往返', () {
    expect(parseThemeColor('#123456'), const Color(0xff123456));
    expect(parseThemeColor('#123456AB'), const Color(0xab123456));
    for (final value in ['#00000000', '#abcdef', '#fffffffe', '#112233ff']) {
      final color = parseThemeColor(value);
      expect(parseThemeColor(formatThemeColor(color)), color);
    }
    for (final value in ['red', '#fff', '#12345g', '#1234567', 42, null]) {
      expect(() => parseThemeColor(value), throwsFormatException);
    }
  });

  test('部分字段继承内置基底，导出是完整快照且不携带本机 ID', () {
    final theme = CustomTheme(
      id: 'custom-1',
      name: ' 我的夜色 ',
      base: ColorTheme.tokyoNight,
      colors: {'accent': parseThemeColor('#ff8800')},
    );
    expect(theme.name, '我的夜色');
    expect(theme.palette.accent, const Color(0xffff8800));
    expect(theme.palette.panel, palettes[ColorTheme.tokyoNight]!.panel);
    final json = jsonDecode(theme.encode()) as Map<String, dynamic>;
    expect(json.containsKey('id'), false);
    expect(
      (json['colors'] as Map).keys.toSet(),
      ThemeColor.values.map((t) => t.name).toSet(),
    );
    final restored = CustomTheme.decode(theme.encode(), id: 'custom-2');
    expect(restored.palette.colors, theme.palette.colors);
    expect(restored.base, theme.base);
    expect(restored.name, theme.name);
  });

  test('无效导入完整拒绝，不改动已有主题、选中项或其他设置', () {
    final settings = Settings(persist: false)..fontSize = 18;
    final original = settings.saveCustomTheme(
      name: '已有主题',
      base: ColorTheme.githubDark,
      colors: {},
    );
    final valid = original.toJson();
    final before = jsonEncode(settings.preferencesJson());
    for (final input in [
      '[]',
      '{',
      jsonEncode({...valid, 'version': 2}),
      jsonEncode({...valid, 'format': 'zed'}),
      jsonEncode({...valid, 'base': 'missing'}),
      jsonEncode({...valid, 'name': ''}),
      jsonEncode({...valid, 'name': 'bad\nname'}),
      jsonEncode({...valid, 'colors': []}),
      jsonEncode({
        ...valid,
        'colors': {'bg': 42},
      }),
      jsonEncode({
        ...valid,
        'colors': {'typo': '#ffffff'},
      }),
    ]) {
      expect(
        () => settings.importTheme(input),
        throwsFormatException,
        reason: input,
      );
      expect(jsonEncode(settings.preferencesJson()), before);
    }
  });

  test('同名导入生成独立副本，编辑替换原主题，删除恢复内置选择', () {
    final settings = Settings(persist: false)
      ..setAppearance(theme: ColorTheme.githubDark);
    final first = settings.saveCustomTheme(
      name: '我的夜色',
      base: ColorTheme.tokyoNight,
      colors: {},
    );
    final imported = settings.importTheme(first.encode());
    expect(imported.id, isNot(first.id));
    expect(imported.name, '我的夜色 (2)');
    expect(settings.customThemes, hasLength(2));
    final edited = settings.saveCustomTheme(
      id: first.id,
      name: first.name,
      base: first.base,
      colors: {'bg': const Color(0xff112233)},
    );
    expect(settings.customThemes, hasLength(2));
    expect(settings.paletteFor(Brightness.dark), same(edited.palette));
    expect(
      settings.customThemes.last.palette.bg,
      palettes[ColorTheme.tokyoNight]!.bg,
    );
    settings.deleteCustomTheme(first.id);
    expect(
      settings.paletteFor(Brightness.dark),
      same(palettes[ColorTheme.githubDark]),
    );
    expect(settings.customThemes.single.id, imported.id);
  });

  test('长名称按可见字符计数，同名编号不会拆开 Emoji', () {
    final settings = Settings(persist: false);
    final name = List.filled(80, '🦊').join();
    final first = settings.saveCustomTheme(
      name: name,
      base: ColorTheme.githubDark,
      colors: {},
    );
    final imported = settings.importTheme(first.encode());
    expect(imported.name, '${List.filled(76, '🦊').join()} (2)');
    expect(CustomTheme.decode(imported.encode(), id: '').name, imported.name);
  });

  test('亮暗自定义主题及选中项跨启动恢复，坏主题单独回退', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-custom-themes-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = Settings(storageDirectory: dir.path);
    final light = settings.saveCustomTheme(
      name: '我的白天',
      base: ColorTheme.githubLight,
      colors: {'ink': const Color(0xff112233)},
    );
    final dark = settings.saveCustomTheme(
      name: '我的夜色',
      base: ColorTheme.githubDark,
      colors: {'accent': const Color(0xff00ffcc)},
    );
    await settings.save();
    final restored = await Settings.load(storageDirectory: dir.path);
    expect(restored.selectedThemeId(Brightness.light), light.id);
    expect(restored.selectedThemeId(Brightness.dark), dark.id);
    expect(restored.paletteFor(Brightness.light).colors, light.palette.colors);
    expect(restored.paletteFor(Brightness.dark).colors, dark.palette.colors);
    final prefs = settings.preferencesJson();
    final entries = prefs['customThemes'] as List;
    (entries.last as Map)['colors'] = {'bg': 'bad'};
    restored.readPreferences(prefs);
    expect(restored.customThemes.single.id, light.id);
    expect(
      restored.paletteFor(Brightness.dark),
      same(palettes[ColorTheme.fmergeDark]),
    );
    expect(
      () => restored.selectTheme(light.id, Brightness.dark),
      throwsFormatException,
    );
    expect(restored.paletteFor(Brightness.light).colors, light.palette.colors);
  });
}
