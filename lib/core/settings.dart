import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart'
    show ChangeNotifier, ThemeMode, Brightness, Color;

import '../palette.dart';
import 'custom_theme.dart';
import 'diff.dart';
import 'shortcuts.dart';

class Settings extends ChangeNotifier {
  Settings({this.persist = true, this.storageDirectory});
  final bool persist;
  final String? storageDirectory;
  Future<void> _saveTail = Future<void>.value();
  ThemeMode themeMode = ThemeMode.system;
  ColorTheme lightTheme = ColorTheme.githubLight;
  ColorTheme darkTheme = ColorTheme.fmergeDark;

  final List<CustomTheme> _customThemes = [];
  List<CustomTheme> get customThemes => List.unmodifiable(_customThemes);
  String? lightCustomThemeId, darkCustomThemeId;

  CustomTheme? customThemeFor(Brightness brightness) {
    final id = brightness == Brightness.light
        ? lightCustomThemeId
        : darkCustomThemeId;
    return _customThemes
        .where((theme) => theme.id == id && theme.base.brightness == brightness)
        .firstOrNull;
  }

  AppPalette paletteFor(Brightness brightness) =>
      customThemeFor(brightness)?.palette ??
      palettes[brightness == Brightness.light ? lightTheme : darkTheme]!;

  String selectedThemeId(Brightness brightness) =>
      customThemeFor(brightness)?.id ??
      (brightness == Brightness.light ? lightTheme : darkTheme).name;

  void selectTheme(String id, Brightness brightness) {
    final builtin = ColorTheme.values
        .where((t) => t.name == id && t.brightness == brightness)
        .firstOrNull;
    if (builtin != null) {
      setAppearance(theme: builtin);
      return;
    }
    final custom = _customThemes
        .where((t) => t.id == id && t.base.brightness == brightness)
        .firstOrNull;
    if (custom == null) throw const FormatException('主题不存在或亮暗类型不匹配');
    if (brightness == Brightness.light) {
      lightCustomThemeId = id;
    } else {
      darkCustomThemeId = id;
    }
    notifyListeners();
  }

  String get _nextThemeId {
    var number = 1;
    while (_customThemes.any((theme) => theme.id == 'custom-$number')) {
      number++;
    }
    return 'custom-$number';
  }

  CustomTheme saveCustomTheme({
    String? id,
    required String name,
    required ColorTheme base,
    required Map<String, Color> colors,
  }) {
    final original = id == null
        ? -1
        : _customThemes.indexWhere((theme) => theme.id == id);
    if (id != null && original < 0) throw const FormatException('自定义主题不存在');
    final clean = CustomTheme.validateName(name);
    var unique = clean, suffix = 2;
    while (_customThemes.any((t) => t.id != id && t.name == unique)) {
      final ending = ' ($suffix)';
      unique = '${clean.characters.take(80 - ending.length)}$ending';
      suffix++;
    }
    final theme = CustomTheme(
      id: id ?? _nextThemeId,
      name: unique,
      base: base,
      colors: colors,
    );
    if (original < 0) {
      _customThemes.add(theme);
    } else {
      _customThemes[original] = theme;
    }
    selectTheme(theme.id, base.brightness);
    return theme;
  }

  CustomTheme importTheme(String contents) {
    // 完整解析通过后才写入设置；导入文件不携带本机主题标识。
    final draft = CustomTheme.decode(contents, id: '');
    return saveCustomTheme(
      name: draft.name,
      base: draft.base,
      colors: draft.colors,
    );
  }

  void deleteCustomTheme(String id) {
    _customThemes.removeWhere((theme) => theme.id == id);
    if (lightCustomThemeId == id) lightCustomThemeId = null;
    if (darkCustomThemeId == id) darkCustomThemeId = null;
    notifyListeners();
  }

  void setAppearance({ThemeMode? mode, ColorTheme? theme}) {
    if (mode != null) themeMode = mode;
    if (theme != null) {
      if (theme.brightness == Brightness.light) {
        lightTheme = theme;
        lightCustomThemeId = null;
      } else {
        darkTheme = theme;
        darkCustomThemeId = null;
      }
    }
    notifyListeners();
  }

  double fontSize = 13;
  int contextLines = 3;
  bool contextOnly = false;
  bool showOverview = true, showLineDetails = true;
  bool wordWrap = false, detectMoves = true;
  InlineDiffMode inlineMode = InlineDiffMode.characters;
  final shortcuts = ShortcutPreferences();
  bool get ignoreWhitespace => whitespace != WhitespaceMode.exact;
  set ignoreWhitespace(bool value) =>
      whitespace = value ? WhitespaceMode.edges : WhitespaceMode.exact;
  bool highlight = true,
      toolbarLabels = true,
      backup = true,
      showWhitespace = false,
      ignoreCase = false,
      ignoreEol = true;
  WhitespaceMode whitespace = WhitespaceMode.exact;
  final List<Map<String, dynamic>> recent = [];
  CompareOptions get comparison => CompareOptions(
    whitespace: whitespace,
    ignoreCase: ignoreCase,
    ignoreEol: ignoreEol,
    inlineMode: inlineMode,
    detectMoves: detectMoves,
  );
  static String get directory {
    final home = Platform.environment['HOME'] ?? '.';
    return Platform.isMacOS
        ? '$home/Library/Application Support/fmerge'
        : Platform.isWindows
        ? '${Platform.environment['APPDATA'] ?? home}/fmerge'
        : '${Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config'}/fmerge';
  }

  static Future<Settings> load({String? storageDirectory}) async {
    final settings = Settings(storageDirectory: storageDirectory);
    final file = File('${storageDirectory ?? directory}/settings.json');
    if (!await file.exists()) return settings;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      settings.readPreferences(json);
      for (final r in (json['recent'] as List? ?? []).take(12)) {
        if (r is Map) settings.recent.add(Map<String, dynamic>.from(r));
      }
    } on FormatException {
      /* 损坏的偏好不影响打开文件；原文件在下次保存设置前保留。 */
    } on TypeError {
      /* 兼容旧版本或无效字段。 */
    }
    return settings;
  }

  void readPreferences(Map<String, dynamic> json) {
    double number(String name, double fallback) =>
        json[name] is num ? (json[name] as num).toDouble() : fallback;
    bool flag(String name, bool fallback) =>
        json[name] is bool ? json[name] as bool : fallback;
    themeMode =
        ThemeMode.values
            .where((m) => m.name == json['themeMode'])
            .firstOrNull ??
        ThemeMode.system;
    lightTheme = ColorTheme.read(json['lightTheme'], Brightness.light);
    darkTheme = ColorTheme.read(json['darkTheme'], Brightness.dark);
    _customThemes.clear();
    final savedThemes = json['customThemes'];
    if (savedThemes is List) {
      for (final raw in savedThemes) {
        try {
          if (raw is! Map<String, dynamic> ||
              raw['id'] is! String ||
              !RegExp(r'^custom-[1-9][0-9]*$').hasMatch(raw['id'] as String) ||
              _customThemes.any((theme) => theme.id == raw['id'])) {
            continue;
          }
          _customThemes.add(CustomTheme.fromJson(raw, id: raw['id'] as String));
        } on FormatException {
          // 单个主题损坏时保留其他主题和偏好。
        }
      }
    }
    lightCustomThemeId = json['lightCustomThemeId'] is String
        ? json['lightCustomThemeId'] as String
        : null;
    darkCustomThemeId = json['darkCustomThemeId'] is String
        ? json['darkCustomThemeId'] as String
        : null;
    if (customThemeFor(Brightness.light) == null) lightCustomThemeId = null;
    if (customThemeFor(Brightness.dark) == null) darkCustomThemeId = null;

    fontSize = number('fontSize', 13).clamp(10, 24);
    contextLines = number('contextLines', 3).clamp(0, 1000).toInt();
    contextOnly = flag('contextOnly', false);
    showOverview = flag('showOverview', true);
    showLineDetails = flag('showLineDetails', true);
    wordWrap = flag('wordWrap', false);
    detectMoves = flag('detectMoves', true);
    inlineMode = json['inlineMode'] == InlineDiffMode.words.name
        ? InlineDiffMode.words
        : InlineDiffMode.characters;
    highlight = flag('highlight', true);
    toolbarLabels = flag('toolbarLabels', true);
    backup = flag('backup', true);
    showWhitespace = flag('showWhitespace', false);
    ignoreCase = flag('ignoreCase', false);
    ignoreEol = flag('ignoreEol', true);
    final legacy = json['whitespace'];
    ignoreWhitespace = flag(
      'ignoreWhitespace',
      legacy is int && legacy > 0 && legacy < WhitespaceMode.values.length,
    );
    shortcuts.load(json['shortcuts']);
  }

  Map<String, dynamic> preferencesJson() => {
    'themeMode': themeMode.name,
    'lightTheme': lightTheme.name,
    'darkTheme': darkTheme.name,
    'lightCustomThemeId': lightCustomThemeId,
    'darkCustomThemeId': darkCustomThemeId,
    'customThemes': [
      for (final theme in _customThemes) theme.toJson(includeId: true),
    ],
    'fontSize': fontSize,
    'contextLines': contextLines,
    'contextOnly': contextOnly,
    'showOverview': showOverview,
    'showLineDetails': showLineDetails,
    'wordWrap': wordWrap,
    'detectMoves': detectMoves,
    'inlineMode': inlineMode.name,
    'highlight': highlight,
    'toolbarLabels': toolbarLabels,
    'backup': backup,
    'showWhitespace': showWhitespace,
    'ignoreCase': ignoreCase,
    'ignoreEol': ignoreEol,
    'ignoreWhitespace': ignoreWhitespace,
    'whitespace': whitespace.index,
    'shortcuts': shortcuts.toJson(),
  };

  Future<void> save() {
    if (!persist) return Future<void>.value();
    final contents = jsonEncode({...preferencesJson(), 'recent': recent});
    // 快速连续切换时按调用顺序保存快照，避免共用临时文件相互覆盖或 rename 失败。
    final next = _saveTail.then(
      (_) => _write(contents),
      onError: (Object _, StackTrace _) => _write(contents),
    );
    _saveTail = next;
    return next;
  }

  Future<void> _write(String contents) async {
    final folder = storageDirectory ?? directory;
    await Directory(folder).create(recursive: true);
    final file = File('$folder/settings.json');
    final temp = File('${file.path}.$pid.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }

  void remember(String? left, String? right, String? base, String? output) {
    if (left == null || right == null) return;
    final entry = {
      'left': left,
      'right': right,
      'base': base,
      'output': output,
    };
    recent.removeWhere(
      (r) => r['left'] == left && r['right'] == right && r['base'] == base,
    );
    recent.insert(0, entry);
    if (recent.length > 12) recent.removeLast();
  }
}
