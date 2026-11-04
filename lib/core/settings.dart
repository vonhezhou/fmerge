import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart'
    show ChangeNotifier, ThemeMode, Brightness;

import '../palette.dart' show ColorTheme;
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

  void setAppearance({ThemeMode? mode, ColorTheme? theme}) {
    if (mode != null) themeMode = mode;
    if (theme != null) {
      if (theme.brightness == Brightness.light) {
        lightTheme = theme;
      } else {
        darkTheme = theme;
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
