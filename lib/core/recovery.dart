import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

class RecoveryRecord {
  const RecoveryRecord(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

/// 日志独立写入；持有系统文件锁的实例不会出现在其他窗口的恢复列表中。
class RecoveryStore {
  RecoveryStore(String directory) : folder = p.join(directory, 'recovery');
  final String folder;
  final String id = _nextId();
  static int _stamp = 0;
  static String _nextId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _stamp = now > _stamp ? now : _stamp + 1;
    return '$pid-$_stamp';
  }

  static final _active = <String>{};
  RandomAccessFile? _lease;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();
  Future<void> _queue(Future<void> Function() work) => _tail = _tail.then(
    (_) => work(),
    onError: (Object _, StackTrace _) => work(),
  );

  Future<void> save(Map<String, dynamic> data) {
    if (_closed) return Future.error(StateError('恢复存储已关闭'));
    _active.add(p.join(folder, id));
    return _queue(() async {
      if (_lease == null) {
        await _prepareFolder(folder);
        _lease = await _lockRecord(folder, id);
        if (_lease == null) {
          _active.remove(p.join(folder, id));
          throw StateError('恢复日志正在使用');
        }
        _active.add(p.join(folder, id));
      }
      await _writeSnapshot(folder, id, data);
    });
  }

  Future<void> remove([String? recordId]) => _queue(() async {
    final name = recordId ?? id;
    _validateId(name);
    final file = File(p.join(folder, '$name.json'));
    if (!await file.exists()) return;
    if (name == id && _lease != null) {
      await file.delete();
      return;
    }
    if (_active.contains(p.join(folder, name))) {
      throw StateError('此恢复记录仍在其他窗口中使用');
    }
    final lock = await _lockRecord(folder, name);
    if (lock == null) throw StateError('此恢复记录仍在其他窗口中使用');
    try {
      if (await file.exists()) await file.delete();
    } finally {
      await lock.unlock();
      await lock.close();
    }
  });

  Future<List<RecoveryRecord>> list() => _readRecords(folder, Set.of(_active));

  /// 关闭锁但保留正文，用于异常退出后的恢复；正常离开由调用方先 remove。
  Future<void> close() {
    _closed = true;
    return _queue(() async {
      final lease = _lease;
      _lease = null;
      if (lease == null) {
        _active.remove(p.join(folder, id));
        return;
      }
      await lease.unlock();
      await lease.close();
      _active.remove(p.join(folder, id));
      if (!await File(p.join(folder, '$id.json')).exists()) {
        final lock = File(p.join(folder, '$id.lock'));
        if (await lock.exists()) await lock.delete();
      }
    });
  }
}

void _validateId(String id) {
  if (!RegExp(r'^\d+-\d+$').hasMatch(id)) {
    throw const FormatException('恢复记录标识无效');
  }
}

Future<void> _prepareFolder(String folder) async {
  if (await FileSystemEntity.type(folder, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FileSystemException('恢复目录不能为符号链接');
  }
  await Directory(folder).create(recursive: true);
  if (!Platform.isWindows) await _chmod('700', folder);
}

Future<RandomAccessFile?> _lockRecord(String folder, String id) async {
  final file = File(p.join(folder, '$id.lock'));
  if (await FileSystemEntity.type(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FileSystemException('恢复锁不能为符号链接');
  }
  final lock = await file.open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    if (!Platform.isWindows) await _chmod('600', file.path);
    return lock;
  } on FileSystemException {
    await lock.close();
    return null;
  }
}

Future<void> _writeSnapshot(
  String folder,
  String id,
  Map<String, dynamic> data,
) => Isolate.run(() async {
  final bytes = utf8.encode(
    jsonEncode({
      ...data,
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
    }),
  );
  if (bytes.length > 128 * 1024 * 1024) {
    throw const FormatException('恢复快照超过 128 MiB，未写入磁盘');
  }
  final temp = File(p.join(folder, '$id.tmp'));
  try {
    if (await FileSystemEntity.type(temp.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('恢复临时文件不能为符号链接');
    }
    await temp.create();
    if (!Platform.isWindows) await _chmod('600', temp.path);
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(p.join(folder, '$id.json'));
  } finally {
    if (await temp.exists()) await temp.delete();
  }
});

Future<List<RecoveryRecord>> _readRecords(
  String folder,
  Set<String> active,
) => Isolate.run(() async {
  final directory = Directory(folder);
  if (await FileSystemEntity.type(folder, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FileSystemException('恢复目录不能为符号链接');
  }
  if (!await directory.exists()) return <RecoveryRecord>[];
  final records = <RecoveryRecord>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File ||
        !RegExp(r'^\d+-\d+\.json$').hasMatch(p.basename(entity.path))) {
      continue;
    }
    final id = p.basenameWithoutExtension(entity.path);
    if (active.contains(p.join(folder, id))) continue;
    RandomAccessFile? lock;
    try {
      lock = await _lockRecord(folder, id);
      if (lock == null || await entity.length() > 128 * 1024 * 1024) continue;
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
      records.add(RecoveryRecord(id, data));
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    } on FileSystemException {
      continue;
    } finally {
      if (lock != null) {
        await lock.unlock();
        await lock.close();
      }
    }
  }
  records.sort(
    (a, b) =>
        (b.data['savedAt'] as String).compareTo(a.data['savedAt'] as String),
  );
  return records;
});

Future<void> _chmod(String mode, String path) async {
  if ((await Process.run('chmod', [mode, path])).exitCode != 0) {
    throw FileSystemException('无法保护恢复文件权限', path);
  }
}

/// 空闲保存与最长间隔并用；写入期间的新请求只合并为下一次最新快照。
class RecoveryScheduler {
  RecoveryScheduler({
    required this.save,
    required this.onError,
    this.idle = const Duration(milliseconds: 900),
    this.maximum = const Duration(seconds: 5),
  });
  final Future<void> Function() save;
  final void Function(Object) onError;
  final Duration idle, maximum;
  Timer? _idle, _maximum;
  bool _queued = false, _writing = false, _disposed = false;
  void schedule() {
    if (_disposed) return;
    _idle?.cancel();
    _idle = Timer(idle, _flush);
    _maximum ??= Timer(maximum, _flush);
  }

  void reset() {
    _idle?.cancel();
    _maximum?.cancel();
    _idle = _maximum = null;
    _queued = false;
  }

  void _flush() {
    _idle?.cancel();
    _maximum?.cancel();
    _idle = _maximum = null;
    _queued = true;
    if (!_writing) unawaited(_drain());
  }

  Future<void> _drain() async {
    _writing = true;
    try {
      while (_queued && !_disposed) {
        _queued = false;
        try {
          await save();
        } catch (e) {
          onError(e);
        }
      }
    } finally {
      _writing = false;
    }
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
