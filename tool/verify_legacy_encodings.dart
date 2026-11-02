import 'dart:convert';
import 'dart:io';

import 'package:fmerge/core/files.dart';

void main(List<String> args) {
  final data =
      jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;
  final names = {
    'shift_jis': 'shiftJis',
    'euc_jp': 'eucJp',
    for (var i = 1250; i <= 1258; i++) 'cp$i': 'windows$i',
  };
  for (final entry in data.entries) {
    final encoding = TextEncoding.values.byName(names[entry.key] ?? entry.key);
    var accepted = 0, rejected = 0, wrong = 0;
    for (final dynamic row in entry.value) {
      final bytes = (row[0] as List).cast<int>();
      try {
        final text = TextFile.decode(bytes, encoding).$1;
        accepted++;
        if (text != row[1]) {
          if (wrong < 5) {
            stderr.writeln(
              '${encoding.label} $bytes: ${text.runes.toList()} != ${(row[1] as String).runes.toList()}',
            );
          }
          wrong++;
        }
      } on FormatException {
        // 不能精确往返的字节允许保守拒绝；接受的文字必须符合独立标准。
        rejected++;
      }
    }
    stdout.writeln(
      '${encoding.label}: accepted=$accepted rejected=$rejected wrong=$wrong',
    );
    if (wrong != 0) exitCode = 1;
  }
}
