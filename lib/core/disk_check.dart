import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// 合并重复焦点事件，读盘和摘要都在后台执行；不缓存可能漏掉外部改动的时间戳。
class DiskCheck {
  Future<bool>? _running;
  List<(String, String)> _baselines = const [];

  Future<bool> changed(List<(String, String)> baselines) {
    final active = _running;
    if (active != null) {
      if (baselines.length == _baselines.length &&
          Iterable<int>.generate(baselines.length)
              .every((i) => baselines[i] == _baselines[i])) {
        return active;
      }
      return active.then((_) => changed(baselines));
    }
    _baselines = List.of(baselines);
    return _running = Isolate.run(() async {
      for (final (path, digest) in baselines) {
        final file = File(path);
        if (!await file.exists() ||
            (await sha256.bind(file.openRead()).first).toString() != digest) {
          return true;
        }
      }
      return false;
    }).whenComplete(() => _running = null);
  }
}
