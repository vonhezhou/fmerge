import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:re_editor/re_editor.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/git.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/ui/code_pane.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('fmerge/access');
  testWidgets('真实 macOS：可编辑对齐、剪贴板、原子保存、冲突与原生退出取消', (tester) async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await native.invokeMethod<void>('restore');
    await native.invokeMethod<void>('backupClipboard');
    addTearDown(() => native.invokeMethod<void>('restoreClipboard'));
    final dir = await Directory.systemTemp.createTemp('fmerge-native-');
    addTearDown(() => dir.delete(recursive: true));
    final left = File('${dir.path}/left.dart'),
        right = File('${dir.path}/right.dart');
    await left.writeAsString('class A {\n  final value = 1;\n}\n');
    await right.writeAsBytes(
      TextFile.encode(
        'class A {\r\n  // 中文注释\r\n  final value = 2;\r\n}\r\n',
        TextEncoding.utf8Bom,
      ),
    );
    final s = await CompareSession.open(
      LaunchOptions(left: left.path, right: right.path),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          initial: s,
          settings: Settings(persist: false),
          nativeWindow: true,
        ),
      ),
    );
    await windowManager.show();
    Future<void> ready(CompareSession current) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (current.busy || current.diff == null) {
        if (DateTime.now().isAfter(deadline)) fail('差异计算超时');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<void> snapshot(String name) async {
      await tester.pumpAndSettle();
      final b =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      // 预览仅来自实际运行应用的渲染帧，不冒充系统录屏。
      final file = File(
        '${Directory.systemTemp.path}/fmerge-product-$name.png',
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('PREVIEW: ${file.path}');
    }

    await ready(s);
    expect(s.leftEditor.diffLayout!.totalRows, s.rightEditor.lineCount);
    await snapshot('diff');
    final panes = find.byType(CodePane);
    await tester.tapAt(tester.getCenter(panes.at(1)));
    s.rightEditor.selectAll();
    await s.rightEditor.copy();
    expect((await Clipboard.getData(Clipboard.kTextPlain))!.text, s.right.text);
    s.rightEditor.runRevocableOp(
      () => s.rightEditor.text = 'class A {\n  final value = 3;\n}\n',
    );
    await tester.pump(const Duration(milliseconds: 180));
    await ready(s);
    // 编辑器持有焦点时发送保存快捷键，确保内部快捷键没有吞掉保存。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    final saveDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (s.rightDirty && DateTime.now().isBefore(saveDeadline)) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    if (s.rightDirty) {
      debugPrint(
        'SAVE DIAGNOSTIC: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(" | ")}',
      );
    }
    expect(s.rightDirty, false);
    expect(
      (await TextFile.read(right.path)).original,
      'class A {\r\n  final value = 3;\r\n}\r\n',
    );
    expect((await TextFile.read(right.path)).encoding, TextEncoding.utf8Bom);
    expect(await File('${right.path}.bak').exists(), true);
    // 原生菜单必须编辑当前对话框字段，不能误改背后的文件。
    final savedText = s.rightEditor.text;
    await tester.tap(find.text('打开比较'));
    await tester.pumpAndSettle();
    final pathField = find.byType(TextField).first;
    await tester.tap(pathField);
    await tester.pumpAndSettle();
    await Clipboard.setData(
      const ClipboardData(text: '/tmp/native-menu-path.txt'),
    );
    await native.invokeMethod<void>('performMenuAction', {'label': '粘贴'});
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      '/tmp/native-menu-path.txt',
    );
    expect(s.rightEditor.text, savedText);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // 不把真实平台窗口的关闭事件替换成按钮回调。
    s.rightEditor.text = 'unsaved';
    await tester.pump(const Duration(milliseconds: 180));
    await ready(s);
    await windowManager.close();
    await tester.pumpAndSettle();
    expect(find.text('有尚未保存的修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await windowManager.isVisible(), true);
    expect(s.rightEditor.text, 'unsaved');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final base = File('${dir.path}/base.dart')
      ..writeAsStringSync('a\nb\nc\nd\n');
    left.writeAsStringSync('a\nLOCAL\nc\nd\n');
    right.writeAsStringSync('a\nREMOTE\nc\nD\n');
    final output = File('${dir.path}/merged.dart')
      ..writeAsStringSync('unresolved original');
    final merge = await CompareSession.open(
      LaunchOptions(
        base: base.path,
        left: left.path,
        right: right.path,
        output: output.path,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          initial: merge,
          settings: Settings(persist: false),
          nativeWindow: true,
        ),
      ),
    );
    await ready(merge);
    expect(merge.pending, 1);
    expect(merge.toolExitCode, 1);
    final unchangedResult = merge.resultEditor!.text;
    await tester.tap(find.text('查看祖先'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(CodePane).last));
    await tester.pumpAndSettle();
    await native.invokeMethod<void>('performMenuAction', {'label': '全选'});
    await native.invokeMethod<void>('performMenuAction', {'label': '复制'});
    await tester.pumpAndSettle();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      merge.base!.text,
    );
    await native.invokeMethod<void>('performMenuAction', {'label': '粘贴'});
    await tester.pumpAndSettle();
    expect(merge.resultEditor!.text, unchangedResult);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    await native.invokeMethod<void>('requestSystemQuit');
    await tester.pumpAndSettle();
    expect(find.text('有尚未保存的修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '采用本地'));
    await tester.pumpAndSettle();
    expect(merge.resultEditor!.text, 'a\nLOCAL\nc\nD\n');
    merge.resultEditor!.text = '// 保留手工编辑\na\nLOCAL\nc\nD\n';
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '采用远端'));
    await tester.pumpAndSettle();
    expect(merge.resultEditor!.text, startsWith('// 保留手工编辑\na\nREMOTE'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    final mergeDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (merge.resultDirty && DateTime.now().isBefore(mergeDeadline)) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(await output.readAsString(), merge.resultEditor!.text);
    expect(merge.toolExitCode, 0);
    expect(await left.readAsString(), 'a\nLOCAL\nc\nd\n');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
    await snapshot('merge');
    // 大文件使用同一套可编辑布局，验证远距离定位与鼠标滚轮同步。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final original = List.generate(10000, (i) => 'final item$i = $i;');
    final modified = [...original]
      ..insertAll(450, ['// inserted line 1', '// inserted line 2']);
    final largeLeft = File('${dir.path}/large-left.dart')
      ..writeAsStringSync(original.join('\n'));
    final largeRight = File('${dir.path}/large-right.dart')
      ..writeAsStringSync(modified.join('\n'));
    final large = await CompareSession.open(
      LaunchOptions(left: largeLeft.path, right: largeRight.path),
    );
    await tester.pumpWidget(
      FmergeApp(
        initial: large,
        settings: Settings(persist: false),
        nativeWindow: true,
      ),
    );
    await ready(large);
    final largePanes = tester
        .widgetList<CodePane>(find.byType(CodePane))
        .toList();
    largePanes.first.scroll.makeVisible(
      const CodeLinePosition(index: 9999, offset: 0),
    );
    await tester.pumpAndSettle();
    expect(
      largePanes.first.scroll.verticalScroller.offset,
      greaterThan(100000),
    );
    expect(
      largePanes.first.scroll.verticalScroller.offset,
      largePanes.last.scroll.verticalScroller.offset,
    );
    expect(large.leftEditor.text, original.join('\n'));
    await tester.tap(find.byTooltip('仅显示差异及前后 3 行'));
    await tester.pumpAndSettle();
    expect(large.leftEditor.diffLayout!.totalRows, 10);
    expect(large.rightEditor.diffLayout!.totalRows, 10);
    expect(large.leftEditor.text, original.join('\n'));
    await tester.tap(find.byTooltip('显示整个文件'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 在真实 App Sandbox 子进程中操作独立仓库，不触碰用户仓库与全局配置。
    final repository = await Directory('${dir.path}/git').create();
    Future<String> git(List<String> args) async {
      final result = await Process.run(await GitReview.executable(), [
        '-c',
        'core.hooksPath=/dev/null',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.invalid',
        ...args,
      ], workingDirectory: repository.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout as String;
    }

    await git(['init', '-q']);
    await git(['config', 'core.autocrlf', 'false']);
    final gitFile = File('${repository.path}/file.txt');
    final gitLines = List.generate(30, (i) => 'line $i');
    await gitFile.writeAsString('${gitLines.join('\n')}\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'fixture']);
    gitLines[3] = 'stage this';
    gitLines[25] = 'keep unstaged';
    final workingText = '${gitLines.join('\n')}\n';
    await gitFile.writeAsString(workingText);
    final review = await GitReview.open(gitFile.path);
    expect(review.patch.hunks.length, 2);
    await review.apply({0});
    expect(await git(['show', ':file.txt']), contains('stage this'));
    expect(await git(['show', ':file.txt']), isNot(contains('keep unstaged')));
    expect(await gitFile.readAsString(), workingText);
    await (await GitReview.open(gitFile.path, staged: true)).apply({0});
    expect(await git(['diff', '--cached']), '');
    expect(await gitFile.readAsString(), workingText);
  });
}
