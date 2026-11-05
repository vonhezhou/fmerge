import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/git.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/merge_labels.dart';
import 'package:fmerge/session.dart';

void main() {
  test('代码行选择只匹配实际修改，不把上下文和结束行边界纳入暂存', () {
    final patch = GitPatch.parse('''diff --git a/file b/file
--- a/file
+++ b/file
@@ -1,3 +1,3 @@
 context
-old
+new
 after
@@ -20,2 +20,1 @@
-deleted
 tail
''');
    expect(patch.hunksForLines(0, 1), isEmpty);
    expect(patch.hunksForLines(1, 2), {0});
    expect(patch.hunksForLines(2, 3), isEmpty);
    expect(patch.hunksForLines(19, 20), {1});
    expect(patch.hunksForLines(0, 20), {0, 1});
    expect(patch.hunksForLines(2, 2), isEmpty);
    final deletion = GitPatch.parse('''--- a/file
+++ b/file
@@ -1 +0,0 @@
-last line
''');
    expect(deletion.hunksForLines(0, 1), {0});
  });
  late Directory dir;
  Future<String> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fmerge-git-');
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 'test@example.invalid']);
    await git(['config', 'user.name', 'Test']);
    await git(['config', 'core.autocrlf', 'false']);
    await git(['config', 'commit.gpgsign', 'false']);
  });
  tearDown(() => dir.delete(recursive: true));

  for (final encoding in [
    TextEncoding.gbk,
    TextEncoding.big5,
    TextEncoding.utf8,
  ]) {
    test('按块暂存与取消暂存保留原始编码字节 $encoding', () async {
      final file = File('${dir.path}/encoded.txt');
      final old = TextFile.encode('中文原文\n', encoding),
          next = TextFile.encode('中文修改\n', encoding);
      await file.writeAsBytes(old);
      await git(['add', 'encoded.txt']);
      await git(['commit', '-qm', 'initial']);
      await file.writeAsBytes(next);
      final review = await GitReview.open(file.path);
      await review.apply({0});
      final staged = await Process.run(
        'git',
        ['show', ':encoded.txt'],
        workingDirectory: dir.path,
        stdoutEncoding: null,
      );
      expect(staged.stdout, next);
      await (await GitReview.open(file.path, staged: true)).apply({0});
      final unstaged = await Process.run(
        'git',
        ['show', ':encoded.txt'],
        workingDirectory: dir.path,
        stdoutEncoding: null,
      );
      expect(unstaged.stdout, old);
      expect(await file.readAsBytes(), next);
    });
  }

  test('选择不相邻差异块暂存，保留已有暂存、其他文件和工作区；可逆向取消暂存', () async {
    final file = File('${dir.path}/测试 file [1].txt');
    final original = List.generate(50, (i) => 'line $i');
    await file.writeAsString('${original.join('\n')}\n');
    await File('${dir.path}/other').writeAsString('old\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'initial']);
    final lines = [...original]..[2] = 'already staged';
    await file.writeAsString('${lines.join('\n')}\n');
    await git(['add', '--', '测试 file [1].txt']);
    lines[16] = 'selected';
    lines[30] = 'keep unstaged';
    lines[44] = 'also selected';
    final worktree = '${lines.join('\n')}\n';
    await file.writeAsString(worktree);
    await File('${dir.path}/other').writeAsString('other staged\n');
    await git(['add', 'other']);
    final review = await GitReview.open(file.path);
    expect(review.patch.hunks.length, 3);
    await review.apply({0, 2});
    final indexed = await git(['show', ':测试 file [1].txt']);
    expect(indexed, contains('already staged'));
    expect(indexed, contains('selected\n'));
    expect(indexed, contains('also selected'));
    expect(indexed, isNot(contains('keep unstaged')));
    expect(await file.readAsString(), worktree);
    expect(await git(['show', ':other']), 'other staged\n');
    final staged = await GitReview.open(file.path, staged: true);
    expect(staged.patch.hunks.length, 3);
    await staged.apply({1});
    final after = await git(['show', ':测试 file [1].txt']);
    expect(after, contains('already staged'));
    expect(after, isNot(contains('\nselected\n')));
    expect(after, contains('also selected'));
    expect(await file.readAsString(), worktree);
  });

  test('文件或索引变化后拒绝旧补丁，失败不改写索引', () async {
    final file = File('${dir.path}/file')..writeAsStringSync('old\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'initial']);
    await file.writeAsString('new\n');
    final review = await GitReview.open(file.path);
    await file.writeAsString('external\n');
    await expectLater(review.apply({0}), throwsStateError);
    expect(await git(['show', ':file']), 'old\n');
    final fresh = await GitReview.open(file.path);
    await git(['add', 'file']);
    await expectLater(fresh.apply({0}), throwsStateError);
    expect(await git(['show', ':file']), 'external\n');
  });

  test('CRLF 和没有末尾换行的补丁保留原字节；删除文件可暂存及撤回', () async {
    final file = File('${dir.path}/file')..writeAsStringSync('old\r\nlast');
    await git(['add', '.']);
    await git(['commit', '-qm', 'initial']);
    await file.writeAsString('new\r\nlast');
    await (await GitReview.open(file.path)).apply({0});
    expect(await git(['show', ':file']), 'new\r\nlast');
    expect(await file.readAsString(), 'new\r\nlast');
    await (await GitReview.open(file.path, staged: true)).apply({0});
    expect(await git(['show', ':file']), 'old\r\nlast');
    await file.delete();
    await (await GitReview.open(file.path)).apply({0});
    expect(await git(['ls-files', '--', 'file']), '');
    await (await GitReview.open(file.path, staged: true)).apply({0});
    expect(await git(['show', ':file']), 'old\r\nlast');
    expect(await file.exists(), false);
  });

  test('未跟踪和二进制文件明确拒绝', () async {
    final file = File('${dir.path}/file')..writeAsStringSync('untracked');
    await expectLater(GitReview.open(file.path), throwsStateError);
    await file.writeAsBytes([0, 1]);
    await git(['add', '.']);
    await git(['commit', '-qm', 'initial']);
    await file.writeAsBytes([0, 2]);
    await expectLater(GitReview.open(file.path), throwsFormatException);
  });
  Future<File> divergentBranches() async {
    final file = File('${dir.path}/file');
    await file.writeAsString('base\n');
    await git(['add', 'file']);
    await git(['commit', '-qm', 'base']);
    await git(['checkout', '-qb', 'feature']);
    await file.writeAsString('feature\n');
    await git(['commit', '-qam', 'feature change']);
    await git(['checkout', '-q', 'main']);
    await file.writeAsString('main\n');
    await git(['commit', '-qam', 'main change']);
    await git(['checkout', '-q', 'feature']);
    return file;
  }

  Future<LaunchOptions> conflictInputs(File file) async {
    final paths = <String>[];
    for (var stage = 1; stage <= 3; stage++) {
      final snapshot = File('${dir.path}/stage$stage.txt');
      await snapshot.writeAsString(await git(['show', ':$stage:file']));
      paths.add(snapshot.path);
    }
    return LaunchOptions(
      base: paths[0],
      left: paths[1],
      right: paths[2],
      output: file.path,
    );
  }

  for (final rebasing in [false, true]) {
    test('${rebasing ? 'rebase' : 'merge'} 来源按实际冲突和提交核验，输入互换或改变后回退', () async {
      final file = await divergentBranches();
      final result = await Process.run(
        'git',
        rebasing ? ['rebase', 'main'] : ['merge', 'main'],
        workingDirectory: dir.path,
      );
      expect(result.exitCode, 1, reason: '${result.stdout} ${result.stderr}');
      final args = await conflictInputs(file);
      final s = await CompareSession.open(args);
      addTearDown(s.dispose);
      final labels = s.mergeLabels;
      expect(
        labels.operation,
        rebasing ? MergeOperation.rebase : MergeOperation.merge,
      );
      expect(
        labels.summary,
        rebasing ? '正在将 feature 变基到 main' : '正在将 main 合并到 feature',
      );
      expect(
        labels.leftSource,
        contains(rebasing ? 'main change' : 'feature change'),
      );
      expect(
        labels.rightSource,
        contains(rebasing ? 'feature change' : 'main change'),
      );
      expect(labels.leftAction, rebasing ? '采用目标历史' : '采用当前分支');
      expect(labels.rightAction, rebasing ? '采用本次提交' : '采用合入版本');
      expect(labels.detail(true), contains('ours / current / LOCAL'));
      final swapped = await GitMergeLabels.detect(
        left: s.right,
        right: s.left,
        base: s.base!,
        output: file.path,
      );
      expect(swapped.operation, MergeOperation.files);
      final modified = await GitMergeLabels.detect(
        left: TextFile.empty('unrelated'),
        right: s.right,
        base: s.base!,
        output: file.path,
      );
      expect(modified.operation, MergeOperation.files);
      expect(await file.readAsString(), contains('<<<<<<<'));
    });
  }

  test('正常文件及已解决索引不冒充 Git 冲突；分支引用不唯一时显示提交哈希', () async {
    final file = await divergentBranches();
    final result = await Process.run('git', [
      'merge',
      'main',
    ], workingDirectory: dir.path);
    expect(result.exitCode, 1);
    await git(['branch', 'alias-main', 'main']);
    final args = await conflictInputs(file);
    final s = await CompareSession.open(args);
    addTearDown(s.dispose);
    final incoming = (await git(['rev-parse', '--short=8', 'main'])).trim();
    expect(s.mergeLabels.rightTitle, '合入版本 · $incoming');
    await file.writeAsString('resolved\n');
    await git(['add', 'file']);
    final resolved = await CompareSession.open(args);
    addTearDown(resolved.dispose);
    expect(resolved.mergeLabels.operation, MergeOperation.files);
    expect(resolved.mergeLabels.leftTitle, '左侧输入');
    expect(resolved.mergeLabels.rightAction, '采用右侧');
  });

  test('linked worktree 的 rebase 使用独立状态，左侧保留已重放提交身份', () async {
    final file = File('${dir.path}/file');
    final other = File('${dir.path}/other');
    await file.writeAsString('base\n');
    await other.writeAsString('base\n');
    await git(['add', 'file', 'other']);
    await git(['commit', '-qm', 'base']);
    await git(['checkout', '-qb', 'feature']);
    await other.writeAsString('first feature commit\n');
    await git(['commit', '-qam', 'already replayed']);
    await file.writeAsString('feature\n');
    await git(['commit', '-qam', 'replaying now']);
    await git(['checkout', '-q', 'main']);
    await file.writeAsString('main\n');
    await git(['commit', '-qam', 'target change']);
    final linked = '${dir.path}/linked';
    await git(['worktree', 'add', '-q', linked, 'feature']);
    final result = await Process.run('git', [
      'rebase',
      'main',
    ], workingDirectory: linked);
    expect(result.exitCode, 1);
    final inputs = <TextFile>[];
    for (var stage = 1; stage <= 3; stage++) {
      inputs.add(
        TextFile.empty(await git(['-C', linked, 'show', ':$stage:file'])),
      );
    }
    final labels = await GitMergeLabels.detect(
      left: inputs[1],
      right: inputs[2],
      base: inputs[0],
      output: '$linked/file',
    );
    expect(labels.operation, MergeOperation.rebase);
    expect(labels.summary, '正在将 feature 变基到 main');
    expect(labels.leftSource, contains('already replayed'));
    expect(labels.rightSource, contains('replaying now'));
  });
}
