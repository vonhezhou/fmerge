import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

class RecoveryRecord {
  const RecoveryRecord(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

/// 每个进程使用独立日志；串行原子替换，不覆盖其他正在运行的窗口。
class RecoveryStore {
  RecoveryStore(String directory) : folder = p.join(directory, 'recovery');
  final String folder;
  final String id = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  Future<void> _tail = Future<void>.value();
  Future<void> _queue(Future<void> Function() work) => _tail = _tail.then(
    (_) => work(),
    onError: (Object _, StackTrace _) => work(),
  );

  Future<void> save(Map<String, dynamic> data) {
    final location = folder, identifier = id;
    return _queue(
      () => Isolate.run(() async {
        final bytes = utf8.encode(
          jsonEncode({
            'version': 1,
            'savedAt': DateTime.now().toIso8601String(),
            ...data,
          }),
        );
        if (bytes.length > 128 * 1024 * 1024) {
          throw const FormatException('恢复快照超过 128 MiB，未写入磁盘');
        }
        final directory = Directory(location);
        if (await FileSystemEntity.type(location, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FileSystemException('恢复目录不能为符号链接');
        }
        await directory.create(recursive: true);
        if (!Platform.isWindows) await _chmod('700', location);
        final temp = File(p.join(location, '$identifier.tmp'));
        try {
          if (await FileSystemEntity.type(temp.path, followLinks: false) ==
              FileSystemEntityType.link) {
            throw const FileSystemException('恢复临时文件不能为符号链接');
          }
          await temp.create();
          if (!Platform.isWindows) await _chmod('600', temp.path);
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(p.join(location, '$identifier.json'));
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      }),
    );
  }

  Future<void> remove([String? recordId]) => _queue(() async {
    final name = recordId ?? id;
    if (!RegExp(r'^\d+-\d+$').hasMatch(name)) {
      throw const FormatException('恢复记录标识无效');
    }
    final file = File(p.join(folder, '$name.json'));
    if (await file.exists()) await file.delete();
  });

  Future<List<RecoveryRecord>> list() {
    final location = folder;
    return Isolate.run(() async {
      final directory = Directory(location);
      if (await FileSystemEntity.type(location, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('恢复目录不能为符号链接');
      }
      if (!await directory.exists()) return <RecoveryRecord>[];
      final result = <RecoveryRecord>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            !RegExp(r'^\d+-\d+\.json$').hasMatch(p.basename(entity.path))) {
          continue;
        }
        try {
          if (await entity.length() > 128 * 1024 * 1024) continue;
          final data =
              jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          if (data['version'] != 1 ||
              data['savedAt'] is! String ||
              data['left'] is! Map<String, dynamic> ||
              data['right'] is! Map<String, dynamic> ||
              data['leftText'] is! String ||
              data['rightText'] is! String) {
            continue;
          }
          result.add(
            RecoveryRecord(p.basenameWithoutExtension(entity.path), data),
          );
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        } on FileSystemException {
          continue;
        }
      }
      result.sort(
        (a, b) => (b.data['savedAt'] as String? ?? '').compareTo(
          a.data['savedAt'] as String? ?? '',
        ),
      );
      return result;
    });
  }
}

Future<void> _chmod(String mode, String path) async {
  if ((await Process.run('chmod', [mode, path])).exitCode != 0) {
    throw FileSystemException('无法保护恢复文件权限', path);
  }
}
