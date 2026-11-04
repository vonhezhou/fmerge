import 'dart:convert';
import 'dart:io';

import 'diff.dart';

class Settings {
  Settings({this.persist = true});
  final bool persist;
  double fontSize = 13;
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
  );
  static String get directory {
    final home = Platform.environment['HOME'] ?? '.';
    return Platform.isMacOS
        ? '$home/Library/Application Support/fmerge'
        : Platform.isWindows
        ? '${Platform.environment['APPDATA'] ?? home}/fmerge'
        : '${Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config'}/fmerge';
  }

  static Future<Settings> load() async {
    final settings = Settings();
    final file = File('$directory/settings.json');
    if (!await file.exists()) return settings;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      settings.fontSize = (json['fontSize'] as num? ?? 13).toDouble().clamp(
        10,
        24,
      );
      settings.highlight = json['highlight'] as bool? ?? true;
      settings.toolbarLabels = json['toolbarLabels'] as bool? ?? true;
      settings.backup = json['backup'] as bool? ?? true;
      settings.showWhitespace = json['showWhitespace'] as bool? ?? false;
      settings.ignoreCase = json['ignoreCase'] as bool? ?? false;
      settings.ignoreEol = json['ignoreEol'] as bool? ?? true;
      settings.whitespace =
          WhitespaceMode.values[(json['whitespace'] as int? ?? 0).clamp(0, 2)];
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

  Future<void> save() async {
    if (!persist) return;
    await Directory(directory).create(recursive: true);
    final file = File('$directory/settings.json');
    final temp = File('${file.path}.$pid.tmp');
    await temp.writeAsString(
      jsonEncode({
        'fontSize': fontSize,
        'highlight': highlight,
        'toolbarLabels': toolbarLabels,
        'backup': backup,
        'showWhitespace': showWhitespace,
        'ignoreCase': ignoreCase,
        'ignoreEol': ignoreEol,
        'whitespace': whitespace.index,
        'recent': recent,
      }),
      flush: true,
    );
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
