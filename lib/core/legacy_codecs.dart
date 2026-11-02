import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:dart_big5/big5.dart' as big5;

class Big5Encoding extends Encoding {
  const Big5Encoding();
  @override
  String get name => 'big5';
  @override
  Converter<List<int>, String> get decoder =>
      _Decoder(big5.Big5TransformDecode);
  @override
  Converter<String, List<int>> get encoder =>
      _Encoder(big5.Big5TransformEncode);
}

/// charset 2.0.1 将 JIS X 0208 的 A1 BD 错映射为 U+2014，标准为 U+2015。
class EucJpEncoding extends Encoding {
  const EucJpEncoding();
  @override
  String get name => 'euc-jp';
  @override
  Converter<List<int>, String> get decoder => _Decoder(
    (bytes) => charset.eucJp.decode(bytes).replaceAll('\u2014', '\u2015'),
  );
  @override
  Converter<String, List<int>> get encoder => _Encoder(
    (text) => charset.eucJp.encode(text.replaceAll('\u2015', '\u2014')),
  );
}

class _Decoder extends Converter<List<int>, String> {
  _Decoder(this.decode);
  final String Function(List<int>) decode;
  @override
  String convert(List<int> input) => decode(input);
}

class _Encoder extends Converter<String, List<int>> {
  _Encoder(this.encode);
  final List<int> Function(String) encode;
  @override
  List<int> convert(String input) => encode(input);
}
