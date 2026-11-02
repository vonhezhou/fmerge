import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/git.dart';

void main() {
  late Directory dir;
  Future<String> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fmerge-git-');
    await git(['init', '-q']);
    await git(['config', 'user.email', 'test@example.invalid']);
    await git(['config', 'user.name', 'Test']);
    await git(['config', 'core.autocrlf', 'false']);
  });
  tearDown(() => dir.delete(recursive: true));

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
}
