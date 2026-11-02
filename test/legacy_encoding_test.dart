import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';

// 固定的标准字节向量，避免仅验证同一编码库的自洽性。
const fixtures = <TextEncoding, (String, List<int>)>{
  TextEncoding.gbk: ('中文', [214, 208, 206, 196]),
  TextEncoding.big5: ('中文', [164, 164, 164, 229]),
  TextEncoding.shiftJis: ('日本', [147, 250, 150, 123]),
  TextEncoding.eucJp: ('日本', [198, 252, 203, 220]),
  TextEncoding.windows1250: ('Ł', [163]),
  TextEncoding.windows1251: ('Я', [223]),
  TextEncoding.windows1252: ('€', [128]),
  TextEncoding.windows1253: ('Ω', [217]),
  TextEncoding.windows1254: ('ğ', [240]),
  TextEncoding.windows1255: ('ש', [249]),
  TextEncoding.windows1256: ('ش', [212]),
  TextEncoding.windows1257: ('Ā', [194]),
  TextEncoding.windows1258: ('ơ', [245]),
  TextEncoding.cp437: ('é', [130]),
  TextEncoding.cp737: ('α', [152]),
};

void main() {
  test('EUC-JP 横线符合 JIS 标准，不将 U+2014 冒充 U+2015', () {
    expect(TextFile.decode([0xa1, 0xbd], TextEncoding.eucJp).$1, '\u2015');
    expect(TextFile.encode('\u2015', TextEncoding.eucJp), [0xa1, 0xbd]);
    expect(
      () => TextFile.encode('\u2014', TextEncoding.eucJp),
      throwsFormatException,
    );
  });
  for (final entry in fixtures.entries) {
    final encoding = entry.key, text = entry.value.$1, bytes = entry.value.$2;
    test('${encoding.label} 读写符合标准字节向量', () {
      expect(TextFile.decode(bytes, encoding), (text, encoding));
      expect(TextFile.encode(text, encoding), bytes);
    });
    test('${encoding.label} 拒绝不可表示的字符，不替换或截断后缀', () {
      expect(
        () => TextFile.encode('$text😀suffix', encoding),
        throwsFormatException,
      );
      expect(
        () => TextFile.encode('prefix\ufffdsuffix', encoding),
        throwsFormatException,
      );
    });
  }

  const malformed = <TextEncoding, List<List<int>>>{
    TextEncoding.gbk: [
      [0x81],
      [0x81, 0x20],
      [0x90, 0x30, 0x81, 0x30],
    ],
    TextEncoding.big5: [
      [0xa4],
      [0xa4, 0x20],
      [0xff],
    ],
    TextEncoding.shiftJis: [
      [0x82],
      [0x82, 0x20],
      [0xff],
    ],
    TextEncoding.eucJp: [
      [0xa4],
      [0xa4, 0x20],
      [0xff],
    ],
    TextEncoding.windows1252: [
      [0x81],
    ],
  };
  for (final entry in malformed.entries) {
    test('${entry.key.label} 拒绝截断、非法和不支持的输入', () {
      for (final bytes in entry.value) {
        expect(
          () => TextFile.decode(bytes, entry.key),
          throwsFormatException,
          reason: '$bytes',
        );
      }
      expect(() => TextFile.decode([0], entry.key), throwsFormatException);
    });
  }

  test('自动模式不会将旧编码猜作其他编码，读取错误包含具体路径', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-legacy-auto-');
    addTearDown(() => dir.delete(recursive: true));
    final disk = File('${dir.path}/old.txt')
      ..writeAsBytesSync(fixtures[TextEncoding.gbk]!.$2);
    await expectLater(
      TextFile.read(disk.path),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(disk.path),
        ),
      ),
    );
  });

  test('所有旧编码正常保存保留字节与 CRLF，有损保存不影响文件、备份和会话', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-legacy-save-');
    addTearDown(() => dir.delete(recursive: true));
    for (final entry in fixtures.entries) {
      final bytes = [...entry.value.$2, 13, 10];
      final disk = File('${dir.path}/${entry.key.name}')
        ..writeAsBytesSync(bytes);
      final file = await TextFile.read(disk.path, encoding: entry.key);
      expect(file.originalBytes(), bytes);
      await file.save(file.text, backup: false);
      expect(await disk.readAsBytes(), bytes);
      await file.save('${file.text}next\n');
      final editedBytes = [...bytes, ...'next\r\n'.codeUnits];
      expect(await disk.readAsBytes(), editedBytes);
      expect(await File('${disk.path}.bak').readAsBytes(), bytes);
      final original = file.original, digest = file.digest;
      await expectLater(
        file.save('${file.text}😀suffix'),
        throwsFormatException,
      );
      expect(await disk.readAsBytes(), editedBytes);
      expect(await File('${disk.path}.bak').readAsBytes(), bytes);
      expect(file.original, original);
      expect(file.digest, digest);
      expect(file.encoding, entry.key);
    }
    expect(
      await dir.list().where((file) => file.path.endsWith('.tmp')).length,
      0,
    );
  });

  test('另存可在 GBK 与 UTF-8 间无损转换，失败不创建或覆盖目标', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-transcode-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/gbk')
      ..writeAsBytesSync(fixtures[TextEncoding.gbk]!.$2);
    final file = await TextFile.read(source.path, encoding: TextEncoding.gbk);
    final utf = '${dir.path}/utf8';
    await file.save(file.text, destination: utf, asEncoding: TextEncoding.utf8);
    expect(await File(utf).readAsString(), '中文');
    final target = File('${dir.path}/target')..writeAsStringSync('keep');
    await expectLater(
      file.save(
        '😀suffix',
        destination: target.path,
        asEncoding: TextEncoding.big5,
      ),
      throwsFormatException,
    );
    expect(await target.readAsString(), 'keep');
    expect(await File('${target.path}.bak').exists(), false);
    final missing = '${dir.path}/missing';
    await expectLater(
      file.save('😀', destination: missing, asEncoding: TextEncoding.gbk),
      throwsFormatException,
    );
    expect(await File(missing).exists(), false);
    expect(file.path, utf);
    expect(file.text, '中文');
    expect(file.encoding, TextEncoding.utf8);
    expect(await source.readAsBytes(), fixtures[TextEncoding.gbk]!.$2);
    await file.save(
      file.text,
      destination: target.path,
      asEncoding: TextEncoding.gbk,
    );
    expect(await target.readAsBytes(), fixtures[TextEncoding.gbk]!.$2);
  });
}
