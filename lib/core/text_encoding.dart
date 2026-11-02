import 'dart:convert';

import 'package:charset/charset.dart' as charset;

import 'legacy_codecs.dart';

enum TextEncoding {
  utf8,
  utf8Bom,
  utf16le,
  utf16be,
  latin1,
  gbk,
  big5,
  shiftJis,
  eucJp,
  windows1250,
  windows1251,
  windows1252,
  windows1253,
  windows1254,
  windows1255,
  windows1256,
  windows1257,
  windows1258,
  cp437,
  cp737,
}

extension TextEncodingLabel on TextEncoding {
  String get label => switch (this) {
    TextEncoding.utf8 => 'UTF-8',
    TextEncoding.utf8Bom => 'UTF-8 with BOM',
    TextEncoding.utf16le => 'UTF-16 LE',
    TextEncoding.utf16be => 'UTF-16 BE',
    TextEncoding.latin1 => 'Latin-1',
    TextEncoding.gbk => 'GBK',
    TextEncoding.big5 => 'Big5',
    TextEncoding.shiftJis => 'Shift-JIS',
    TextEncoding.eucJp => 'EUC-JP',
    TextEncoding.cp437 => 'CP437',
    TextEncoding.cp737 => 'CP737',
    _ => 'Windows-${name.substring(7)}',
  };

  Encoding? get legacyCodec => switch (this) {
    TextEncoding.gbk => charset.gbk,
    TextEncoding.big5 => const Big5Encoding(),
    TextEncoding.shiftJis => charset.shiftJis,
    TextEncoding.eucJp => const EucJpEncoding(),
    TextEncoding.windows1250 => charset.windows1250,
    TextEncoding.windows1251 => charset.windows1251,
    TextEncoding.windows1252 => charset.windows1252,
    TextEncoding.windows1253 => charset.windows1253,
    TextEncoding.windows1254 => charset.windows1254,
    TextEncoding.windows1255 => charset.windows1255,
    TextEncoding.windows1256 => charset.windows1256,
    TextEncoding.windows1257 => charset.windows1257,
    TextEncoding.windows1258 => charset.windows1258,
    TextEncoding.cp437 => charset.cp437,
    TextEncoding.cp737 => charset.cp737,
    _ => null,
  };
}
