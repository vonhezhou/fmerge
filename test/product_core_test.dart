import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/merge.dart';
import 'package:fmerge/core/merge_session.dart';

void main() {
  for (final encoding in TextEncoding.values) {
    test('编码与 BOM 可往返 $encoding', () {
      final text = encoding == TextEncoding.latin1
          ? 'café\r\n'
          : '中文 👩‍💻\r\n';
      final bytes = TextFile.encode(text, encoding);
      final decoded = TextFile.decode(bytes, encoding);
      expect(decoded.$1, text);
      expect(decoded.$2, encoding);
    });
  }
  test('保存拒绝未配对代理码，混合换行的修改行也沿用原风格', () {
    expect(
      () => TextFile.encode(String.fromCharCode(0xd800), TextEncoding.utf8),
      throwsFormatException,
    );
    expect(
      TextFile.empty('a\r\nb\nc\r\n').materialize('a\nB\nc\n'),
      'a\r\nB\nc\r\n',
    );
  });
  test('拒绝损坏 UTF-16 与二进制，不用替换字符掩盖编码错误', () {
    expect(() => TextFile.decode([255, 254, 0]), throwsFormatException);
    expect(() => TextFile.decode([255, 254, 0, 216]), throwsFormatException);
    expect(() => TextFile.decode([0, 0, 0, 0]), throwsFormatException);
    expect(() => TextFile.decode([255]), throwsFormatException);
  });
  test('混合换行的不变行保持原字节，新增行使用主导风格', () {
    final file = TextFile.empty('a\r\nb\nc\r\n');
    expect(file.materialize('a\nb\nc\n'), 'a\r\nb\nc\r\n');
    expect(file.materialize('a\nb\nnew\nc\n'), 'a\r\nb\nnew\r\nc\r\n');
  });
  test('真实文件保存备份、外部改动保护与另存', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-save-');
    addTearDown(() => dir.delete(recursive: true));
    final original = File('${dir.path}/中文 space.txt');
    await original.writeAsBytes(
      TextFile.encode('a\r\nb\r\n', TextEncoding.utf8Bom),
    );
    final file = await TextFile.read(original.path);
    await file.save('a\nB\n');
    expect((await TextFile.read(original.path)).original, 'a\r\nB\r\n');
    expect(
      (await TextFile.read('${original.path}.bak')).original,
      'a\r\nb\r\n',
    );
    await original.writeAsString('external');
    await expectLater(file.save('mine'), throwsA(isA<FileConflict>()));
    expect(await original.readAsString(), 'external');
    await file.save('mine', destination: '${dir.path}/另存.txt');
    expect((await TextFile.read('${dir.path}/另存.txt')).text, 'mine');
    expect(await dir.list().where((e) => e.path.endsWith('.tmp')).length, 0);
  });
  test('通过符号链接保存保留链接本身', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('fmerge-link-');
    addTearDown(() => dir.delete(recursive: true));
    final target = File('${dir.path}/actual')..writeAsStringSync('old');
    final link = await Link('${dir.path}/alias').create(target.path);
    final file = await TextFile.read(link.path);
    await file.save('new');
    expect(await FileSystemEntity.isLink(link.path), true);
    expect(await target.readAsString(), 'new');
  });
  test('破损符号链接与备份符号链接均不能被静默覆盖', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('fmerge-link-protect-');
    addTearDown(() => dir.delete(recursive: true));
    final broken = await Link('${dir.path}/broken')
        .create('${dir.path}/missing');
    final empty = TextFile.empty()..path = broken.path;
    await expectLater(empty.save('new'), throwsA(isA<FileSystemException>()));
    expect(await FileSystemEntity.isLink(broken.path), true);
    final file = File('${dir.path}/source')..writeAsStringSync('old');
    final other = File('${dir.path}/other')..writeAsStringSync('keep');
    await Link('${file.path}.bak').create(other.path);
    final doc = await TextFile.read(file.path);
    await expectLater(doc.save('new'), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), 'old');
    expect(await other.readAsString(), 'keep');
  });
  test('CLI 支持 Git 参数、Tortoise 参数和带空格路径', () {
    final options = LaunchOptions.parse([
      '--base',
      'a b',
      '--local',
      'mine',
      '--remote',
      'theirs',
      '--output',
      'out',
    ]);
    expect(options.merge, true);
    expect(options.left, 'mine');
    expect(options.output, 'out');
    final tortoise = LaunchOptions.parse([
      '/base:C:\\a',
      '/mine:C:\\m',
      '/theirs:C:\\t',
      '/merged:C:\\out',
    ]);
    expect(tortoise.base, 'C:\\a');
    expect(tortoise.output, 'C:\\out');
    expect(LaunchOptions.parse(['--', '--left', 'right']).left, '--left');
    expect(
      () => LaunchOptions.parse(['--base', 'b', '--local', 'l']),
      throwsFormatException,
    );
    expect(() => LaunchOptions.parse(['one']), throwsFormatException);
    expect(() => LaunchOptions.parse(['--wat', 'bad']), throwsFormatException);
  });
  test('冲突选择、手工修改、重新选择和撤销不会覆盖其他编辑', () {
    final s = MergeSession(planMerge('a\nb\nc\nd', 'a\nL\nc\nd', 'a\nR\nc\nd'));
    final id = s.state.regions.single.chunk.id;
    expect(s.pending, 1);
    s.edit('header\na\nb\nc\nd\nfooter');
    s.choose(id, MergeChoice.left);
    expect(s.state.text, 'header\na\nL\nc\nd\nfooter');
    expect(s.pending, 0);
    s.choose(id, MergeChoice.right);
    expect(s.state.text, 'header\na\nR\nc\nd\nfooter');
    s.undo();
    expect(s.state.text, 'header\na\nL\nc\nd\nfooter');
    s.undo();
    expect(s.pending, 1);
    s.redo();
    expect(s.pending, 0);
  });
  test('删除冲突内容仍需显式确认，撤销确认恢复未解决状态', () {
    final s = MergeSession(planMerge('a\nb\nc', 'a\nL\nc', 'a\nR\nc'));
    final id = s.state.regions.single.chunk.id;
    s.edit('a\nc');
    expect(s.pending, 1);
    s.markResolved(id, true);
    expect(s.pending, 0);
    s.undo();
    expect(s.pending, 1);
  });
}
