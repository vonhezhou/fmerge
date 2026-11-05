import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

import 'files.dart';
import 'merge_labels.dart';
import 'process_operation.dart';

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

  /// 选择工作区真实行范围相交的修改块，不将周围上下文误当成修改。
  Set<int> hunksForLines(int start, int end) {
    if (start < 0 || end <= start) return {};
    final selected = <int>{};
    for (var i = 0; i < hunks.length; i++) {
      final lines = hunks[i].split('\n');
      final header = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')
          .firstMatch(lines.first);
      if (header == null) continue;
      final count = int.parse(header[2] ?? '1');
      var line = int.parse(header[1]!) - (count == 0 ? 0 : 1);
      for (final text in lines.skip(1)) {
        if (text.startsWith('+') || text.startsWith('-')) {
          if (line >= start && line < end) selected.add(i);
        }
        if (text.startsWith('+') || text.startsWith(' ')) line++;
      }
    }
    return selected;
  }

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
  static String? _resolvedExecutable;
  static Future<String> executable({ProcessOperation? operation}) {
    operation?.check();
    final resolved = _resolvedExecutable;
    if (resolved != null) return Future.value(resolved);
    if (operation != null) {
      return _findExecutable(operation)
          .then((value) => _resolvedExecutable = value);
    }
    return _executable ??= _resolveExecutable();
  }

  static Future<String> _resolveExecutable() async {
    final operation = ProcessOperation();
    try {
      return _resolvedExecutable = await _findExecutable(operation);
    } catch (_) {
      _executable = null;
      rethrow;
    } finally {
      operation.dispose();
    }
  }

  static Future<String> _findExecutable(ProcessOperation operation) async {
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
        final result = await operation.run(actual, ['--version']);
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
  static Future<String> _git(
    String cwd,
    List<String> args, {
    bool bytes = false,
    ProcessOperation? operation,
  }) async {
    final task = operation ?? ProcessOperation();
    try {
      final result = await task.run(
        await task.wait(executable(operation: task)),
        ['-c', 'core.quotePath=true', ...args],
        workingDirectory: cwd,
        environment: _environment,
        includeParentEnvironment: false,
      );
      if (result.exitCode != 0) {
        throw StateError(
          'Git 操作失败：${utf8.decode(result.stderr as List<int>, allowMalformed: true)}',
        );
      }
      return (bytes ? latin1 : utf8).decode(result.stdout as List<int>);
    } finally {
      if (operation == null) task.dispose();
    }
  }

  static Future<String> findRoot(
    String file, {
    ProcessOperation? operation,
  }) async => (await _git(p.dirname(p.absolute(file)), [
    'rev-parse',
    '--show-toplevel',
  ], operation: operation)).trimRight();
  static Future<String> _indexState(
    String root,
    String path, {
    ProcessOperation? operation,
  }) => _git(root, [
    'ls-files',
    '--stage',
    '-z',
    '--',
    path,
  ], operation: operation);
  static Future<String> _readDiff(
    String root,
    String path,
    bool staged, {
    ProcessOperation? operation,
  }) => _git(
    root,
    [
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
    ],
    bytes: true,
    operation: operation,
  );

  static Future<GitReview> open(
    String file, {
    bool staged = false,
    ProcessOperation? operation,
  }) async {
    final task = operation ?? ProcessOperation();
    try {
      return await _open(file, staged: staged, operation: task);
    } finally {
      if (operation == null) task.dispose();
    }
  }

  static Future<GitReview> _open(
    String file, {
    required bool staged,
    required ProcessOperation operation,
  }) async {
    // macOS 的 /var、/tmp 等别名与 Git 返回的真实根目录必须使用同一口径。
    final parent = await Directory(p.dirname(p.absolute(file)))
        .resolveSymbolicLinks();
    final absolute = p.join(parent, p.basename(file));
    final root = await findRoot(absolute, operation: operation);
    final path = p.relative(absolute, from: root);
    if (!p.isWithin(root, absolute)) throw StateError('文件不在仓库中');
    final index = await _indexState(root, path, operation: operation);
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
      ], operation: operation);
      if (tracked.isEmpty) throw StateError('该文件尚未被 Git 跟踪，请先添加到 Git 后再按块暂存');
    }
    final diff = await _readDiff(root, path, staged, operation: operation);
    if (index != await _indexState(root, path, operation: operation)) {
      throw StateError('Git 索引已变化，请重新加载');
    }
    return GitReview(root, path, staged, GitPatch.parse(diff), index, diff);
  }

  Future<void> apply(Set<int> selected, {ProcessOperation? operation}) async {
    final task = operation ?? ProcessOperation();
    try {
      final text = patch.select(selected);
      if (_index != await _indexState(root, path, operation: task) ||
          _diff != await _readDiff(root, path, staged, operation: task)) {
        throw StateError('文件或 Git 索引已变化，请重新加载后再选择');
      }
      final result = await task.run(
        await task.wait(executable(operation: task)),
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
        input: latin1.encode(text),
      );
      if (result.exitCode != 0) {
        throw StateError(
          '暂存操作失败，请刷新确认索引：${utf8.decode(result.stderr as List<int>, allowMalformed: true)}',
        );
      }
    } finally {
      if (operation == null) task.dispose();
    }
  }
}

class GitMergeLabels {
  /// 只有输入快照、索引和提交来源相互吻合时，才赋予 Git 操作角色。
  static Future<MergeLabels> detect({
    required TextFile left,
    required TextFile right,
    required TextFile base,
    required String output,
  }) async {
    try {
      // 普通文件合并不启动 Git；同时兼容 .git 为文件的 linked worktree。
      final parent = await Directory(p.dirname(p.absolute(output)))
          .resolveSymbolicLinks();
      var folder = Directory(parent);
      var repository = false;
      while (true) {
        if (await FileSystemEntity.type(p.join(folder.path, '.git')) !=
            FileSystemEntityType.notFound) {
          repository = true;
          break;
        }
        final parent = folder.parent;
        if (p.equals(parent.path, folder.path)) break;
        folder = parent;
      }
      if (!repository) return const MergeLabels();
      final absolute = p.join(parent, p.basename(output));
      final root = await GitReview.findRoot(absolute);
      if (!p.isWithin(root, absolute)) return const MergeLabels();
      final path = p.relative(absolute, from: root);
      Future<String> git(List<String> args) => GitReview._git(root, args);
      Future<String> revision(String name) async =>
          (await git(['rev-parse', '--verify', '$name^{commit}'])).trim();
      Future<String?> state(String name) async {
        final location = (await git(['rev-parse', '--git-path', name]))
            .trimRight();
        final file = File(
          p.isAbsolute(location) ? location : p.join(root, location),
        );
        return await file.exists() ? (await file.readAsString()).trim() : null;
      }

      final index = await GitReview._indexState(root, path);
      final stages = <int, String>{};
      for (final entry in index.split('\u0000')) {
        final match = RegExp(r'^100(?:644|755) ([a-f0-9]+) ([123])\t')
            .firstMatch(entry);
        if (match != null) stages[int.parse(match[2]!)] = match[1]!;
      }
      bool matches(TextFile file, String? oid) {
        if (oid == null) return false;
        final bytes = file.originalBytes();
        final data = [...utf8.encode('blob ${bytes.length}\u0000'), ...bytes];
        return (oid.length == 40 ? sha1 : sha256).convert(data).toString() ==
            oid;
      }

      if (!matches(left, stages[2]) ||
          !matches(right, stages[3]) ||
          (stages[1] != null
              ? !matches(base, stages[1])
              : base.original.isNotEmpty)) {
        return const MergeLabels();
      }
      final head = await revision('HEAD');
      final rebaseBranch =
          await state('rebase-merge/head-name') ??
          await state('rebase-apply/head-name');
      final rebasing = rebaseBranch != null;
      final otherRef = rebasing ? 'REBASE_HEAD' : 'MERGE_HEAD';
      final other = await revision(otherRef);
      // 重命名冲突等无法按输出路径核对来源的情况保守回退。
      if ((await git(['rev-parse', '$head:$path'])).trim() != stages[2] ||
          (await git(['rev-parse', '$other:$path'])).trim() != stages[3]) {
        return const MergeLabels();
      }
      Future<String> source(String commit) async {
        final subject = (await git(['show', '-s', '--format=%s', commit]))
            .trimRight();
        return '${commit.substring(0, 8)} · $subject';
      }

      Future<String> name(String commit) async {
        final refs = (await git([
          'for-each-ref',
          '--format=%(refname:short)',
          '--points-at=$commit',
          'refs/heads',
        ])).trim().split('\n').where((s) => s.isNotEmpty).toList();
        return refs.length == 1 ? refs.single : commit.substring(0, 8);
      }

      final leftSource = await source(head), rightSource = await source(other);
      late MergeLabels labels;
      if (rebasing) {
        final onto =
            await state('rebase-merge/onto') ??
            await state('rebase-apply/onto');
        if (onto == null || !RegExp(r'^[a-f0-9]{40,64}$').hasMatch(onto)) {
          return const MergeLabels();
        }
        final target = await name(onto);
        final branch = rebaseBranch.replaceFirst('refs/heads/', '');
        labels = MergeLabels(
          operation: MergeOperation.rebase,
          summary: '正在将 $branch 变基到 $target',
          leftTitle: '目标历史',
          rightTitle: '本次提交',
          leftSource: '$target + 已重放提交 · $leftSource',
          rightSource: rightSource,
          leftAction: '采用目标历史',
          rightAction: '采用本次提交',
        );
      } else {
        String? branch;
        try {
          branch = (await git(['symbolic-ref', '--quiet', '--short', 'HEAD']))
              .trim();
        } catch (_) {
          // detached HEAD 仍有确定的输入提交，只是不宣称它属于某个当前分支。
        }
        final current = branch ?? 'HEAD ${head.substring(0, 8)}';
        final incoming = await name(other);
        labels = MergeLabels(
          operation: MergeOperation.merge,
          summary: '正在将 $incoming 合并到 $current',
          leftTitle: branch == null ? '当前版本 · $current' : '当前分支 · $branch',
          rightTitle: '合入版本 · $incoming',
          leftSource: leftSource,
          rightSource: rightSource,
          leftAction: branch == null ? '采用当前版本' : '采用当前分支',
          rightAction: '采用合入版本',
        );
      }
      if (index != await GitReview._indexState(root, path) ||
          head != await revision('HEAD') ||
          other != await revision(otherRef)) {
        return const MergeLabels();
      }
      return labels;
    } catch (_) {
      // 没有 Git、目录未授权或不是当前冲突时，仍可按原始路径完成文件合并。
      return const MergeLabels();
    }
  }
}
