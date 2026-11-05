import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'myers.dart';
import 'strict_codec.dart';
import 'text_encoding.dart';
export 'text_encoding.dart';

class FileConflict implements Exception {
  const FileConflict(this.path);
  final String path;
  @override
  String toString() => '文件已被其他程序修改：$path';
}

class TextFile {
  TextFile._(this.path, this.original, this.encoding, this.digest);
  factory TextFile.empty([String text = '']) =>
      TextFile._(null, text, TextEncoding.utf8, null);
  String? path;
  String original;
  TextEncoding encoding;
  String? digest;
  String? _resolvedPath;
  bool _utf16Bom = true;
  List<int> originalBytes() => encode(original, encoding, utf16Bom: _utf16Bom);
  String get text => normalize(original);
  String get name => path == null ? '未命名' : p.basename(path!);
  String get eol {
    final endings = RegExp(r'\r\n|\r|\n')
        .allMatches(original)
        .map((m) => m[0]!)
        .toSet();
    return endings.length > 1
        ? '混合换行'
        : switch (endings.firstOrNull) {
            '\r\n' => 'CRLF',
            '\r' => 'CR',
            _ => 'LF',
          };
  }

  static Future<TextFile> read(String path, {TextEncoding? encoding}) =>
      Isolate.run(() => _read(path, encoding));

  static Future<TextFile> _read(String path, TextEncoding? encoding) async {
    final file = File(path);
    // 后续会整份读取、解码，并为多侧文本建立编辑器、比较结果及历史；
    // 实际内存可能远大于文件字节数。读取前限制规模，避免超大输入耗尽资源。
    // 32 MiB 是保守保护阈值，不是流畅性保证；放宽前需验证完整应用的耗时与峰值内存。
    if (await file.length() > 32 * 1024 * 1024) {
      throw const FormatException('文本文件超过 32 MiB，暂不支持打开');
    }
    final bytes = await file.readAsBytes();
    final (String, TextEncoding) decoded;
    try {
      decoded = decode(bytes, encoding);
    } on FormatException catch (error) {
      throw FormatException('$path：${error.message}');
    }
    return TextFile._(
        file.absolute.path,
        decoded.$1,
        decoded.$2,
        sha256.convert(bytes).toString(),
      )
      .._resolvedPath = await file.resolveSymbolicLinks()
      .._utf16Bom =
          bytes.length >= 2 &&
          (decoded.$2 == TextEncoding.utf16le &&
                  bytes[0] == 255 &&
                  bytes[1] == 254 ||
              decoded.$2 == TextEncoding.utf16be &&
                  bytes[0] == 254 &&
                  bytes[1] == 255);
  }

  static (String, TextEncoding) decode(
    List<int> bytes, [
    TextEncoding? requested,
  ]) {
    TextEncoding? detected;
    var bomLength = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 239 &&
        bytes[1] == 187 &&
        bytes[2] == 191) {
      detected = TextEncoding.utf8Bom;
      bomLength = 3;
    } else if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254) {
      detected = TextEncoding.utf16le;
      bomLength = 2;
    } else if (bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255) {
      detected = TextEncoding.utf16be;
      bomLength = 2;
    }
    final encoding = requested ?? detected ?? TextEncoding.utf8;
    // 手动选择优先；只移除与所选编码相符的 BOM。
    final skip =
        requested == null ||
            requested == detected ||
            requested == TextEncoding.utf8 && detected == TextEncoding.utf8Bom
        ? bomLength
        : 0;
    final body = bytes.sublist(skip);
    String text;
    if (encoding == TextEncoding.utf16le || encoding == TextEncoding.utf16be) {
      if (body.length.isOdd) throw const FormatException('UTF-16 文件字节长度无效');
      final units = <int>[];
      for (var i = 0; i < body.length; i += 2) {
        units.add(
          encoding == TextEncoding.utf16le
              ? body[i] | body[i + 1] << 8
              : body[i] << 8 | body[i + 1],
        );
      }
      for (var i = 0; i < units.length; i++) {
        if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            throw const FormatException('UTF-16 代理对无效');
          }
        } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
          throw const FormatException('UTF-16 代理对无效');
        }
      }
      text = String.fromCharCodes(units);
    } else {
      final codec = encoding.legacyCodec;
      text = codec != null
          ? decodeLosslessly(codec, body)
          : encoding == TextEncoding.latin1
          ? latin1.decode(body)
          : utf8.decode(body);
    }
    if (text.contains('\x00')) throw const FormatException('检测到二进制内容，不能作为文本打开');
    return (text, encoding);
  }

  static List<int> encode(
    String text,
    TextEncoding encoding, {
    bool utf16Bom = true,
  }) {
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException("文本包含未完成的 Unicode 代理对，不能保存");
        }
      } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
        throw const FormatException("文本包含无效 Unicode 代理对，不能保存");
      }
    }
    return switch (encoding) {
      TextEncoding.utf8 => utf8.encode(text),
      TextEncoding.utf8Bom => [239, 187, 191, ...utf8.encode(text)],
      TextEncoding.latin1 => latin1.encode(text),
      TextEncoding.utf16le => [
        if (utf16Bom) ...[255, 254],
        for (final u in text.codeUnits) ...[u & 255, u >> 8],
      ],
      TextEncoding.utf16be => [
        if (utf16Bom) ...[254, 255],
        for (final u in text.codeUnits) ...[u >> 8, u & 255],
      ],
      _ => encodeLosslessly(encoding.legacyCodec!, text),
    };
  }

  /// 不变行保留各自原换行，新增行使用原文主导风格，避免混合换行被整份重写。
  String materialize(String edited, {String? forcedEol}) {
    if (forcedEol == null && edited == text) return original;
    if (forcedEol != null) return edited.replaceAll('\n', forcedEol);
    final oldLines = text.split('\n'), newLines = edited.split('\n');
    final endings = RegExp(r'\r\n|\r|\n')
        .allMatches(original)
        .map((m) => m[0]!)
        .toList();
    final frequency = <String, int>{};
    for (final e in endings) {
      frequency[e] = (frequency[e] ?? 0) + 1;
    }
    final dominant = frequency.isEmpty
        ? '\n'
        : (frequency.keys.toList()
                ..sort((a, b) => frequency[b]!.compareTo(frequency[a]!)))
              .first;
    final assigned = List.filled(math.max(0, newLines.length - 1), dominant);
    final diff = myers(oldLines, newLines);
    var a = 0, b = 0;
    for (final c in [
      ...diff.changes,
      SequenceChange(
        oldLines.length,
        oldLines.length,
        newLines.length,
        newLines.length,
      ),
    ]) {
      while (a < c.aStart && b < assigned.length) {
        if (a < endings.length) assigned[b] = endings[a];
        a++;
        b++;
      }
      // 同一替换块里仍能逐行对应的修改，沿用该原始行自己的换行。
      final paired = math.min(c.aEnd - c.aStart, c.bEnd - c.bStart);
      for (var i = 0; i < paired; i++) {
        if (c.aStart + i < endings.length && c.bStart + i < assigned.length) {
          assigned[c.bStart + i] = endings[c.aStart + i];
        }
      }
      a = c.aEnd;
      b = c.bEnd;
    }
    final out = StringBuffer();
    for (var i = 0; i < newLines.length; i++) {
      out.write(newLines[i]);
      if (i < assigned.length) out.write(assigned[i]);
    }
    return out.toString();
  }

  Future<void> save(
    String edited, {
    String? destination,
    bool backup = true,
    bool overwriteExternal = false,
    String? forcedEol,
    TextEncoding? asEncoding,
  }) async {
    // 后台副本持有调用时的保存基线；仅成功后更新主线程模型。
    final snapshot = TextFile._(path, original, encoding, digest)
      .._resolvedPath = _resolvedPath
      .._utf16Bom = _utf16Bom;
    final task = (
      snapshot,
      edited,
      destination,
      backup,
      overwriteExternal,
      forcedEol,
      asEncoding,
    );
    final saved = await Isolate.run(() => _saveFile(task));
    path = saved.path;
    original = saved.original;
    encoding = saved.encoding;
    digest = saved.digest;
    _resolvedPath = saved._resolvedPath;
    _utf16Bom = saved._utf16Bom;
  }

  Future<void> _save(
    String edited, {
    String? destination,
    bool backup = true,
    bool overwriteExternal = false,
    String? forcedEol,
    TextEncoding? asEncoding,
  }) async {
    final requestedPath = destination ?? path;
    if (requestedPath == null) throw StateError('请先选择保存位置');
    var target = File(requestedPath);
    final exists = await target.exists();
    if (await FileSystemEntity.type(requestedPath, followLinks: false) ==
            FileSystemEntityType.link &&
        !exists) {
      throw FileSystemException('符号链接目标不存在或无法访问，已取消保存', requestedPath);
    }
    if (exists) {
      target = File(await target.resolveSymbolicLinks());
    } else {
      // 新文件也统一父目录别名，避免下次保存将 /var 与 /private/var 误判为外部替换。
      target = File(
        p.join(
          await target.parent.resolveSymbolicLinks(),
          p.basename(target.path),
        ),
      );
    }
    final same =
        path != null &&
        p.equals(File(path!).absolute.path, File(requestedPath).absolute.path);
    final baseline = exists
        ? sha256.convert(await target.readAsBytes()).toString()
        : null;
    if (same &&
        !overwriteExternal &&
        (baseline != digest ||
            _resolvedPath != null &&
                !p.equals(_resolvedPath!, target.absolute.path))) {
      throw FileConflict(requestedPath);
    }
    final raw = materialize(edited, forcedEol: forcedEol);
    final selectedEncoding = asEncoding ?? encoding;
    final utf16Bom = asEncoding != null || _utf16Bom;
    final bytes = encode(raw, selectedEncoding, utf16Bom: utf16Bom);
    // 同目录临时文件 + rename；失败不破坏原文件。
    final temp = File(
      p.join(
        p.dirname(target.path),
        '.fmerge-$pid-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}.tmp',
      ),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (exists && !Platform.isWindows) {
        final mode = (await target.stat()).mode & 0x1ff;
        final result = await Process.run('chmod', [
          mode.toRadixString(8),
          temp.path,
        ]);
        if (result.exitCode != 0) {
          throw FileSystemException('无法保留原文件权限', target.path);
        }
      }
      final current = await target.exists()
          ? sha256.convert(await target.readAsBytes()).toString()
          : null;
      if (current != baseline) throw FileConflict(requestedPath);
      if (backup && exists) {
        final backupPath = '${target.path}.bak';
        if (await FileSystemEntity.type(backupPath, followLinks: false) ==
            FileSystemEntityType.link) {
          throw FileSystemException('备份位置是符号链接，已取消保存', backupPath);
        }
        await target.copy(backupPath);
      }
      await temp.rename(target.path);
      path = File(requestedPath).absolute.path;
      _resolvedPath = target.absolute.path;
      original = raw;
      encoding = selectedEncoding;
      _utf16Bom = utf16Bom;
      digest = sha256.convert(bytes).toString();
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

String normalize(String raw) =>
    raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

Future<TextFile> _saveFile(
  (TextFile, String, String?, bool, bool, String?, TextEncoding?) task,
) async {
  await task.$1._save(
    task.$2,
    destination: task.$3,
    backup: task.$4,
    overwriteExternal: task.$5,
    forcedEol: task.$6,
    asEncoding: task.$7,
  );
  return task.$1;
}
