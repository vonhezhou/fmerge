import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 监听父目录以兼容原子替换和删除重建；事件合并后交给正文摘要检查。
class FileWatchMonitor {
  FileWatchMonitor(
    this.onChange, {
    this.debounce = const Duration(milliseconds: 250),
    this.fallback = const Duration(seconds: 3),
  });
  final void Function() onChange;
  final Duration debounce, fallback;
  final _subscriptions = <StreamSubscription<FileSystemEvent>>[];
  Set<String> _requested = {};
  Timer? _timer, _poll;
  int _generation = 0;
  bool _disposed = false;

  Future<void> update(Iterable<String> paths) async {
    if (_disposed) return;
    final requested = paths
        .map((path) => p.normalize(p.absolute(path)))
        .toSet();
    if (requested.length == _requested.length &&
        requested.containsAll(_requested)) {
      return;
    }
    _requested = requested;
    final generation = ++_generation;
    _timer?.cancel();
    _poll?.cancel();
    _poll = null;
    final old = _subscriptions.toList();
    _subscriptions.clear();
    await Future.wait(old.map((s) => s.cancel()));
    if (_disposed || generation != _generation) return;
    final watched = {...requested};
    for (final path in requested) {
      try {
        watched.add(await File(path).resolveSymbolicLinks());
      } on FileSystemException {
        /* 删除的文件仍监听原父目录。 */
      }
    }
    if (_disposed || generation != _generation) return;
    for (final folder in watched.map(p.dirname).toSet()) {
      try {
        final sub = Directory(folder).watch().listen(
          (event) {
            if (_disposed || generation != _generation) return;
            final path = p.normalize(p.absolute(event.path));
            if (watched.contains(path) ||
                event is FileSystemMoveEvent &&
                    event.destination != null &&
                    watched.contains(
                      p.normalize(p.absolute(event.destination!)),
                    )) {
              _schedule();
            }
          },
          onError: (Object _) {
            if (generation == _generation) _fallback();
          },
          onDone: () {
            if (generation == _generation) _fallback();
          },
        );
        _subscriptions.add(sub);
      } on FileSystemException {
        _fallback();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (!_disposed) onChange();
    });
  }

  void _fallback() {
    if (!_disposed && _requested.isNotEmpty) {
      _poll ??= Timer.periodic(fallback, (_) => _schedule());
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _poll?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
