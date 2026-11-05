import 'package:flutter/material.dart';

const bg = Color(0xff101318);
const panel = Color(0xff161b22);
const elevated = Color(0xff202731);
const border = Color(0xff303946);
const muted = Color(0xff9aa8ba);
const ink = Color(0xffe4eaf2);
const accent = Color(0xff91bcff);
const green = Color(0xff8cdbac);
const red = Color(0xfff3a0a0);
const amber = Color(0xffe8c587);
const addedBg = Color(0xff19332c);
const removedBg = Color(0xff352429);
const addedInline = Color(0xff28583f);
const removedInline = Color(0xff67343e);
const movedBg = Color(0xff203547);
const movedInk = Color(0xff85cce8);

/// 配色文件与编辑器共用字段定义，字段名也是稳定的导入导出键。
enum ThemeColor {
  bg('窗口背景'),
  panel('编辑器与面板背景'),
  elevated('浮层背景'),
  border('边框与分隔线'),
  muted('次要文字'),
  ink('主要文字'),
  accent('强调色与光标'),
  green('新增标记'),
  red('删除标记'),
  amber('警告标记'),
  addedBg('新增行背景'),
  removedBg('删除行背景'),
  addedInline('新增行内背景'),
  removedInline('删除行内背景'),
  movedBg('移动行背景'),
  movedInk('移动标记'),
  conflictBg('冲突背景'),
  selection('选区背景'),
  keyword('关键字'),
  string('字符串'),
  number('数字'),
  comment('注释'),
  title('类型与函数名'),
  meta('属性与元数据');

  const ThemeColor(this.label);
  final String label;
}

enum ColorTheme {
  fmergeDark('fmerge Dark', Brightness.dark),
  githubLight('GitHub Light', Brightness.light),
  githubDark('GitHub Dark', Brightness.dark),
  tokyoNight('Tokyo Night', Brightness.dark);

  const ColorTheme(this.label, this.brightness);
  final String label;
  final Brightness brightness;

  static ColorTheme read(Object? value, Brightness brightness) =>
      values
          .where((t) => t.name == value && t.brightness == brightness)
          .firstOrNull ??
      (brightness == Brightness.light ? githubLight : fmergeDark);
}

/// 界面、编辑器及差异布局共用语义色，避免切换主题时残留旧配色。
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(
    this.theme, {
    required this.bg,
    required this.panel,
    required this.elevated,
    required this.border,
    required this.muted,
    required this.ink,
    required this.accent,
    required this.green,
    required this.red,
    required this.amber,
    required this.addedBg,
    required this.removedBg,
    required this.addedInline,
    required this.removedInline,
    required this.movedBg,
    required this.movedInk,
    required this.conflictBg,
    required this.selection,
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.title,
    required this.meta,
  });
  final ColorTheme theme;
  final Color bg;
  final Color panel;
  final Color elevated;
  final Color border;
  final Color muted;
  final Color ink;
  final Color accent;
  final Color green;
  final Color red;
  final Color amber;
  final Color addedBg;
  final Color removedBg;
  final Color addedInline;
  final Color removedInline;
  final Color movedBg;
  final Color movedInk;
  final Color conflictBg;
  final Color selection;
  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color title;
  final Color meta;

  Brightness get brightness => theme.brightness;
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      palettes[ColorTheme.fmergeDark]!;

  Map<String, Color> get colors => {
    'bg': bg,
    'panel': panel,
    'elevated': elevated,
    'border': border,
    'muted': muted,
    'ink': ink,
    'accent': accent,
    'green': green,
    'red': red,
    'amber': amber,
    'addedBg': addedBg,
    'removedBg': removedBg,
    'addedInline': addedInline,
    'removedInline': removedInline,
    'movedBg': movedBg,
    'movedInk': movedInk,
    'conflictBg': conflictBg,
    'selection': selection,
    'keyword': keyword,
    'string': string,
    'number': number,
    'comment': comment,
    'title': title,
    'meta': meta,
  };

  AppPalette withColors(Map<String, Color> colors) => copyWith(
    bg: colors['bg'],
    panel: colors['panel'],
    elevated: colors['elevated'],
    border: colors['border'],
    muted: colors['muted'],
    ink: colors['ink'],
    accent: colors['accent'],
    green: colors['green'],
    red: colors['red'],
    amber: colors['amber'],
    addedBg: colors['addedBg'],
    removedBg: colors['removedBg'],
    addedInline: colors['addedInline'],
    removedInline: colors['removedInline'],
    movedBg: colors['movedBg'],
    movedInk: colors['movedInk'],
    conflictBg: colors['conflictBg'],
    selection: colors['selection'],
    keyword: colors['keyword'],
    string: colors['string'],
    number: colors['number'],
    comment: colors['comment'],
    title: colors['title'],
    meta: colors['meta'],
  );

  Color tokenColor(String scope) => switch (scope.split('.').first) {
    'keyword' || 'literal' => keyword,
    'string' || 'regexp' => string,
    'number' => number,
    'comment' => comment,
    'title' || 'type' || 'built_in' => title,
    'meta' || 'attr' || 'attribute' => meta,
    _ => ink,
  };

  @override
  AppPalette copyWith({
    ColorTheme? theme,
    Color? bg,
    Color? panel,
    Color? elevated,
    Color? border,
    Color? muted,
    Color? ink,
    Color? accent,
    Color? green,
    Color? red,
    Color? amber,
    Color? addedBg,
    Color? removedBg,
    Color? addedInline,
    Color? removedInline,
    Color? movedBg,
    Color? movedInk,
    Color? conflictBg,
    Color? selection,
    Color? keyword,
    Color? string,
    Color? number,
    Color? comment,
    Color? title,
    Color? meta,
  }) => AppPalette(
    theme ?? this.theme,
    bg: bg ?? this.bg,
    panel: panel ?? this.panel,
    elevated: elevated ?? this.elevated,
    border: border ?? this.border,
    muted: muted ?? this.muted,
    ink: ink ?? this.ink,
    accent: accent ?? this.accent,
    green: green ?? this.green,
    red: red ?? this.red,
    amber: amber ?? this.amber,
    addedBg: addedBg ?? this.addedBg,
    removedBg: removedBg ?? this.removedBg,
    addedInline: addedInline ?? this.addedInline,
    removedInline: removedInline ?? this.removedInline,
    movedBg: movedBg ?? this.movedBg,
    movedInk: movedInk ?? this.movedInk,
    conflictBg: conflictBg ?? this.conflictBg,
    selection: selection ?? this.selection,
    keyword: keyword ?? this.keyword,
    string: string ?? this.string,
    number: number ?? this.number,
    comment: comment ?? this.comment,
    title: title ?? this.title,
    meta: meta ?? this.meta,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) => other == null
      ? this
      : AppPalette(
          t < .5 ? theme : other.theme,
          bg: Color.lerp(bg, other.bg, t)!,
          panel: Color.lerp(panel, other.panel, t)!,
          elevated: Color.lerp(elevated, other.elevated, t)!,
          border: Color.lerp(border, other.border, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          green: Color.lerp(green, other.green, t)!,
          red: Color.lerp(red, other.red, t)!,
          amber: Color.lerp(amber, other.amber, t)!,
          addedBg: Color.lerp(addedBg, other.addedBg, t)!,
          removedBg: Color.lerp(removedBg, other.removedBg, t)!,
          addedInline: Color.lerp(addedInline, other.addedInline, t)!,
          removedInline: Color.lerp(removedInline, other.removedInline, t)!,
          movedBg: Color.lerp(movedBg, other.movedBg, t)!,
          movedInk: Color.lerp(movedInk, other.movedInk, t)!,
          conflictBg: Color.lerp(conflictBg, other.conflictBg, t)!,
          selection: Color.lerp(selection, other.selection, t)!,
          keyword: Color.lerp(keyword, other.keyword, t)!,
          string: Color.lerp(string, other.string, t)!,
          number: Color.lerp(number, other.number, t)!,
          comment: Color.lerp(comment, other.comment, t)!,
          title: Color.lerp(title, other.title, t)!,
          meta: Color.lerp(meta, other.meta, t)!,
        );
}

const palettes = <ColorTheme, AppPalette>{
  ColorTheme.fmergeDark: AppPalette(
    ColorTheme.fmergeDark,
    bg: bg,
    panel: panel,
    elevated: elevated,
    border: border,
    muted: muted,
    ink: ink,
    accent: accent,
    green: green,
    red: red,
    amber: amber,
    addedBg: addedBg,
    removedBg: removedBg,
    addedInline: addedInline,
    removedInline: removedInline,
    movedBg: movedBg,
    movedInk: movedInk,
    conflictBg: Color(0xff3c3020),
    selection: Color(0xff365274),
    keyword: Color(0xffc8a9ed),
    string: Color(0xffadd9ae),
    number: Color(0xffe3bc87),
    comment: Color(0xff798a9f),
    title: Color(0xff8fc7ef),
    meta: Color(0xffe7bc8e),
  ),
  ColorTheme.githubLight: AppPalette(
    ColorTheme.githubLight,
    bg: Color(0xffffffff),
    panel: Color(0xfff6f8fa),
    elevated: Color(0xffeaeef2),
    border: Color(0xffd0d7de),
    muted: Color(0xff57606a),
    ink: Color(0xff1f2328),
    accent: Color(0xff0969da),
    green: Color(0xff116329),
    red: Color(0xffcf222e),
    amber: Color(0xff9a6700),
    addedBg: Color(0xffdafbe1),
    removedBg: Color(0xffffebe9),
    addedInline: Color(0xffaceebb),
    removedInline: Color(0xffffc1ba),
    movedBg: Color(0xffddf4ff),
    movedInk: Color(0xff0550ae),
    conflictBg: Color(0xfffff8c5),
    selection: Color(0xffb6d7ff),
    keyword: Color(0xffcf222e),
    string: Color(0xff0a3069),
    number: Color(0xff0550ae),
    comment: Color(0xff6e7781),
    title: Color(0xff8250df),
    meta: Color(0xff953800),
  ),
  ColorTheme.githubDark: AppPalette(
    ColorTheme.githubDark,
    bg: Color(0xff0d1117),
    panel: Color(0xff161b22),
    elevated: Color(0xff21262d),
    border: Color(0xff30363d),
    muted: Color(0xff8b949e),
    ink: Color(0xffe6edf3),
    accent: Color(0xff58a6ff),
    green: Color(0xff3fb950),
    red: Color(0xfff85149),
    amber: Color(0xffd29922),
    addedBg: Color(0xff122b1d),
    removedBg: Color(0xff351b20),
    addedInline: Color(0xff1f5835),
    removedInline: Color(0xff762c36),
    movedBg: Color(0xff152d45),
    movedInk: Color(0xff79c0ff),
    conflictBg: Color(0xff3b2e15),
    selection: Color(0xff264f78),
    keyword: Color(0xffff7b72),
    string: Color(0xffa5d6ff),
    number: Color(0xff79c0ff),
    comment: Color(0xff8b949e),
    title: Color(0xffd2a8ff),
    meta: Color(0xffffa657),
  ),
  ColorTheme.tokyoNight: AppPalette(
    ColorTheme.tokyoNight,
    bg: Color(0xff1a1b26),
    panel: Color(0xff1f2335),
    elevated: Color(0xff292e42),
    border: Color(0xff414868),
    muted: Color(0xffa9b1d6),
    ink: Color(0xffc0caf5),
    accent: Color(0xff7aa2f7),
    green: Color(0xff9ece6a),
    red: Color(0xfff7768e),
    amber: Color(0xffe0af68),
    addedBg: Color(0xff23352c),
    removedBg: Color(0xff3f283c),
    addedInline: Color(0xff345442),
    removedInline: Color(0xff69364f),
    movedBg: Color(0xff253c56),
    movedInk: Color(0xff7dcfff),
    conflictBg: Color(0xff413626),
    selection: Color(0xff364a82),
    keyword: Color(0xffbb9af7),
    string: Color(0xff9ece6a),
    number: Color(0xffff9e64),
    comment: Color(0xff7883ab),
    title: Color(0xff7aa2f7),
    meta: Color(0xffe0af68),
  ),
};
