import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// macOS 仅恢复用户明确选择的文件与目录；不移除沙盒，也不自动扩展访问范围。
class DirectoryAccess {
  static const channel = MethodChannel('fmerge/access');
  static Future<void> restore() async {
    if (Platform.isMacOS) await channel.invokeMethod<void>('restore');
  }

  /// 仅用于系统选择器刚刚选中的文件，保存其现有授权以供最近记录恢复。
  static Future<void> rememberFiles(Iterable<String> paths) async {
    if (Platform.isMacOS) {
      await channel.invokeMethod<void>('rememberFiles', {
        'paths': paths.toList(),
      });
    }
  }

  static Future<bool> grant(String path) async {
    if (!Platform.isMacOS) return true;
    return await channel.invokeMethod<bool>('grant', {
          'path': File(path).absolute.path,
        }) ??
        false;
  }

  static Future<void> read(String path) async {
    if (!Platform.isMacOS) return;
    try {
      await File(path).openRead().first;
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode != 1 && e.osError?.errorCode != 13) rethrow;
      if (!await grant(p.dirname(File(path).absolute.path))) {
        throw FileSystemException('未授权访问该文件所在目录', path);
      }
    } on StateError {
      /* 空文件没有字节块，但可以正常打开。 */
    }
  }

  static Future<void> write(String path) async {
    if (!Platform.isMacOS) return;
    final file = File(path);
    final actual = await file.exists()
        ? await file.resolveSymbolicLinks()
        : file.absolute.path;
    final parent = p.dirname(actual);
    final probe = File(
      p.join(
        parent,
        '.fmerge-access-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await probe.writeAsBytes(const [], flush: true);
      await probe.delete();
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode != 1 && e.osError?.errorCode != 13) rethrow;
      if (!await grant(parent)) throw FileSystemException('未授权保存目录', parent);
    }
  }
}
