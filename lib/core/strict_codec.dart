import 'dart:convert';

/// 旧编码库可能替换、截断或输出越界字节，不能仅依赖其是否抛出异常。
String decodeLosslessly(Encoding codec, List<int> bytes) {
  return _convert(codec, () {
    _checkBytes(bytes);
    final text = codec.decode(bytes);
    final restored = codec.encode(text);
    _checkBytes(restored);
    if (bytes.length != restored.length) {
      throw const FormatException('解码后无法还原原始字节');
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != restored[i]) {
        throw const FormatException('解码后无法还原原始字节');
      }
    }
    return text;
  });
}

List<int> encodeLosslessly(Encoding codec, String text) {
  return _convert(codec, () {
    final bytes = codec.encode(text);
    _checkBytes(bytes);
    if (codec.decode(bytes) != text) {
      throw const FormatException('目标编码无法完整表示文本');
    }
    return bytes;
  });
}

void _checkBytes(List<int> bytes) {
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    throw const FormatException('编码器返回了无效字节');
  }
}

T _convert<T>(Encoding codec, T Function() convert) {
  try {
    return convert();
  } on FormatException {
    throw FormatException('${codec.name} 无法无损转换，请检查编码或改用 UTF-8');
  } on ArgumentError {
    // 某些解码器对截断的多字节输入抛出 RangeError。
    throw FormatException('${codec.name} 编码数据无效或不完整');
  }
}
