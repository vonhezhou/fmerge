import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class GitPatch {
  GitPatch(this.header, this.hunks);
  factory GitPatch.parse(String text) {
    final lines = text.split('\n');
    if (lines.last == '') lines.removeLast();
    final header = <String>[], hunks = <String>[];
    var current = <String>[];
    for (final line in lines) {
      if (line.startsWith('@@ ')) {
        if (current.isNotEmpty) hunks.add('${current.join('\n')}\n');
        current = [line];
      } else if (current.isEmpty) {
        header.add(line);
      } else {
        current.add(line);
      }
    }
    if (current.isNotEmpty) hunks.add('${current.join('\n')}\n');
    if (text.isNotEmpty &&
        (hunks.isEmpty ||
            header.any(
              (line) =>
                  line.startsWith('old mode ') ||
                  line.startsWith('new mode ') ||
                  ((line.startsWith('index ') ||
                          line.startsWith('new file mode ') ||
                          line.startsWith('deleted file mode ')) &&
                      RegExp(r' (120000|160000)$').hasMatch(line)),
            ))) {
      throw const FormatException('仅支持普通文本文件的内容暂存；不支持二进制、符号链接、子模块或权限变化');
    }
    return GitPatch(header.isEmpty ? '' : '${header.join('\n')}\n', hunks);
  }
  final String header;
  final List<String> hunks;
  String select(Set<int> selected) {
    if (selected.isEmpty || selected.any((i) => i < 0 || i >= hunks.length)) {
      throw StateError('请选择有效的差异块');
    }
    return header +
        [
          for (var i = 0; i < hunks.length; i++)
            if (selected.contains(i)) hunks[i],
        ].join();
  }
}

class GitReview {
  GitReview(
    this.root,
    this.path,
    this.staged,
    this.patch,
    this._index,
    this._diff,
  );
  final String root, path;
  final bool staged;
  final GitPatch patch;
  final String _index, _diff;

  static Future<String>? _executable;
  static Future<String> executable() => _executable ??= _findExecutable();

  static Future<String> _findExecutable() async {
    if (!Platform.isMacOS) return 'git';
    // /usr/bin/git 是 xcrun 入口，无法在 App Sandbox 中运行。
    final candidates = <String>{
      if (Platform.environment['FMERGE_GIT'] case final String path) path,
      for (final folder in (Platform.environment['PATH'] ?? '').split(':'))
        if (folder.isNotEmpty) p.join(folder, 'git'),
      '/opt/homebrew/bin/git',
      '/usr/local/bin/git',
      if (Platform.environment['DEVELOPER_DIR'] case final String folder)
        p.join(folder, 'usr/bin/git'),
      '/Applications/Xcode.app/Contents/Developer/usr/bin/git',
      '/Library/Developer/CommandLineTools/usr/bin/git',
    };
    for (final candidate in candidates) {
      try {
        final file = File(candidate);
        if (!await file.exists()) continue;
        final actual = await file.resolveSymbolicLinks();
        if (actual == '/usr/bin/git') continue;
        final result = await Process.run(actual, ['--version']);
        if (result.exitCode == 0) return actual;
      } on ProcessException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    _executable = null;
    throw StateError(
      '未找到可在沙盒运行的 Git。请安装 Git，或通过 FMERGE_GIT 指定实际可执行文件（不能是 /usr/bin/git）。',
    );
  }

  // 不继承外部 Git 重定向变量，避免意外修改另一个仓库或临时索引。
  static Map<String, String> get _environment => {
    for (final entry in Platform.environment.entries)
      if (!entry.key.startsWith('GIT_')) entry.key: entry.value,
    'GIT_LITERAL_PATHSPECS': '1',
    'GIT_TERMINAL_PROMPT': '0',
    'LC_ALL': 'C',
  };
  static Future<String> _git(String cwd, List<String> args) async {
    final result = await Process.run(
      await executable(),
      ['-c', 'core.quotePath=true', ...args],
      workingDirectory: cwd,
      environment: _environment,
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) throw StateError('Git 操作失败：${result.stderr}');
    return result.stdout as String;
  }

  static Future<String> findRoot(String file) async {
    return (await _git(p.dirname(p.absolute(file)), [
      'rev-parse',
      '--show-toplevel',
    ])).trimRight();
  }

  static Future<String> _indexState(String root, String path) =>
      _git(root, ['ls-files', '--stage', '-z', '--', path]);

  static Future<String> _readDiff(String root, String path, bool staged) =>
      _git(root, [
        'diff',
        '--no-ext-diff',
        '--no-textconv',
        '--no-color',
        '--no-renames',
        '--no-relative',
        '--src-prefix=a/',
        '--dst-prefix=b/',
        '--diff-algorithm=myers',
        '--unified=3',
        '--no-indent-heuristic',
        if (staged) '--cached',
        '--',
        path,
      ]);

  static Future<GitReview> open(String file, {bool staged = false}) async {
    // macOS 的 /var、/tmp 等别名与 Git 返回的真实根目录必须使用同一口径。
    final parent = await Directory(p.dirname(p.absolute(file)))
        .resolveSymbolicLinks();
    final absolute = p.join(parent, p.basename(file));
    final root = await findRoot(absolute);
    final path = p.relative(absolute, from: root);
    if (!p.isWithin(root, absolute)) throw StateError('文件不在仓库中');
    final index = await _indexState(root, path);
    if (index
        .split('\u0000')
        .any(
          (s) => s.isNotEmpty && !RegExp(r'^\d+ [a-f0-9]+ 0\t').hasMatch(s),
        )) {
      throw StateError('该文件存在未解决的 Git 冲突，请先完成合并');
    }
    if (index.isEmpty) {
      // 删除已暂存的文件仍可取消暂存；未跟踪文件应先用 Git 加入跟踪。
      final tracked = await _git(root, [
        'diff',
        '--cached',
        '--name-only',
        '-z',
        '--',
        path,
      ]);
      if (tracked.isEmpty) throw StateError('该文件尚未被 Git 跟踪，请先添加到 Git 后再按块暂存');
    }
    final diff = await _readDiff(root, path, staged);
    if (index != await _indexState(root, path)) {
      throw StateError('Git 索引已变化，请重新加载');
    }
    return GitReview(root, path, staged, GitPatch.parse(diff), index, diff);
  }

  Future<void> apply(Set<int> selected) async {
    final text = patch.select(selected);
    if (_index != await _indexState(root, path) ||
        _diff != await _readDiff(root, path, staged)) {
      throw StateError('文件或 Git 索引已变化，请重新加载后再选择');
    }
    final process = await Process.start(
      await executable(),
      [
        'apply',
        '--cached',
        '--whitespace=nowarn',
        if (staged) '--reverse',
        '-',
      ],
      workingDirectory: root,
      environment: _environment,
      includeParentEnvironment: false,
    );
    final stdout = process.stdout.drain<void>();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.add(utf8.encode(text));
    await process.stdin.close();
    final code = await process.exitCode;
    await stdout;
    final error = await stderr;
    if (code != 0) throw StateError('暂存操作失败，索引未应用此补丁：$error');
  }
}
