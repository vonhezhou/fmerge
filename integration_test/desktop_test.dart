import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:fmerge/core/merge_labels.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/core/diff.dart' show InlineDiffMode;
import 'package:fmerge/core/shortcuts.dart';
import 'package:fmerge/ui/code_pane.dart';

import '../test/support/menus.dart';

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
    // 验证原生书签 API 的保存/恢复链路；外部受保护目录仍需系统选择器人工验收。
    await native.invokeMethod<void>('rememberFiles', {
      'paths': [left.path, right.path],
    });
    await native.invokeMethod<void>('restore');
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
    // 测试窗口被其他应用遮挡后，macOS 会停止提交帧，使 pumpAndSettle 无法推进。
    await windowManager.setAlwaysOnTop(true);
    addTearDown(() => windowManager.setAlwaysOnTop(false));
    await windowManager.show();
    // 与正式启动流程一致，激活窗口后再验证编辑器快捷键。
    await windowManager.focus();
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
    for (final (width, name) in [
      (1480.0, 'toolbar-wide'),
      (920.0, 'toolbar-narrow'),
      (1200.0, 'toolbar-restored'),
    ]) {
      await windowManager.setSize(Size(width, 800));
      await tester.pumpAndSettle();
      await snapshot(name);
      expect(tester.takeException(), isNull);
    }
    for (final (menu, name) in [
      ('文件', 'file-menu'),
      ('编辑', 'edit-menu'),
      ('导航', 'navigate-menu'),
      ('比较', 'compare-menu'),
    ]) {
      await tester.tap(find.byKey(ValueKey('menu-$menu')));
      await tester.pumpAndSettle();
      await snapshot(name);
      await tester.tapAt(const Offset(420, 20));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('menu-视图')));
    await tester.pumpAndSettle();
    await snapshot('view-menu');
    // 点击工具条空白关闭菜单，不改变当前编辑栏；原先左侧此处已不再是概览条。
    await tester.tapAt(const Offset(420, 20));
    await tester.pumpAndSettle();
    await chooseMenuCommand(tester, 'nextInlineDiff', menu: '导航');
    await tester.pumpAndSettle();
    expect(s.rightEditor.selection.isCollapsed, false);
    await chooseMenuCommand(tester, 'copy', menu: '编辑');
    await tester.pumpAndSettle();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      s.rightEditor.selectedText,
    );
    await snapshot('diff-details');
    debugPrint('STEP: clipboard');
    final panes = find.byType(CodePane);
    await tester.tapAt(tester.getTopLeft(panes.at(1)) + const Offset(70, 20));
    await tester.pumpAndSettle();
    final selectedText = s.rightEditor.text;
    s.rightEditor.selectAll();
    await s.rightEditor.copy();
    expect((await Clipboard.getData(Clipboard.kTextPlain))!.text, selectedText);
    debugPrint('STEP: edited diff');
    s.rightEditor.runRevocableOp(
      () => s.rightEditor.text = 'class A {\n  final value = 3;\n}\n',
    );
    await tester.pump(const Duration(milliseconds: 180));
    await ready(s);
    // 编辑器持有焦点时发送保存快捷键，确保内部快捷键没有吞掉保存。
    debugPrint('STEP: save shortcut');
    tester.widgetList<CodePane>(panes).last.focus.requestFocus();
    await tester.pump();
    expect(tester.widgetList<CodePane>(panes).last.focus.hasFocus, true);
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
    debugPrint('STEP: goto shortcut');
    // 原生菜单必须编辑当前对话框字段，不能误改背后的文件。
    debugPrint('STEP: native dialog edit');
    final savedText = s.rightEditor.text;
    tester.widgetList<CodePane>(panes).last.focus.requestFocus();
    await tester.pump();
    expect(tester.widgetList<CodePane>(panes).last.focus.hasFocus, true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    final pathField = find.byType(TextField).first;
    await tester.tap(pathField);
    await tester.pumpAndSettle();
    await native
        .invokeMethod<void>('performMenuAction', {'label': '全选'})
        .timeout(const Duration(seconds: 10));
    await Clipboard.setData(
      const ClipboardData(text: '/tmp/native-menu-path.txt'),
    );
    await native
        .invokeMethod<void>('performMenuAction', {'label': '粘贴'})
        .timeout(const Duration(seconds: 10));
    debugPrint('STEP: native dialog edited');
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
    expect(
      tester.getSize(find.byKey(const ValueKey('merge-actions'))).height,
      40,
    );
    await snapshot('merge-unresolved');
    for (final command in ['nextConflict', 'previousConflict']) {
      expect(
        find.byKey(ValueKey('command-$command')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('command-$command')));
      await tester.pumpAndSettle();
      expect(
        merge.resultEditor!.selection.extentIndex,
        merge.merger!.state.regions.first.start,
      );
      expect(
        tester.widgetList<CodePane>(find.byType(CodePane)).last.focus.hasFocus,
        true,
      );
    }
    await snapshot('merge-navigated');
    await tester.tap(find.byKey(const ValueKey('menu-合并')));
    await tester.pumpAndSettle();
    await snapshot('merge-menu');
    await tester.tapAt(const Offset(420, 20));
    await tester.pumpAndSettle();
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
    await tester.tap(find.widgetWithText(OutlinedButton, '采用左侧'));
    await tester.pumpAndSettle();
    expect(merge.resultEditor!.text, 'a\nLOCAL\nc\nD\n');
    merge.resultEditor!.text = '// 保留手工编辑\na\nLOCAL\nc\nD\n';
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '采用右侧'));
    await tester.pumpAndSettle();
    expect(merge.resultEditor!.text, startsWith('// 保留手工编辑\na\nREMOTE'));
    await tester.tap(find.byKey(const ValueKey('command-save')));
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
    await tester.tap(find.text('查看祖先'));
    await tester.pumpAndSettle();
    await snapshot('base');
    debugPrint('STEP: close base');
    await tester.tap(find.byTooltip('关闭共同祖先'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    debugPrint('STEP: base closed');
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
    debugPrint('STEP: large open');
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
    debugPrint('STEP: large ready');
    final largePanes = tester
        .widgetList<CodePane>(find.byType(CodePane))
        .toList();
    await tester.tap(find.byKey(const ValueKey('command-nextDiff')));
    await tester.pumpAndSettle();
    debugPrint('STEP: large navigated');
    expect(large.rightEditor.selection.extentIndex, 450);
    expect(largePanes.last.focus.hasFocus, true);
    final centered = largePanes.last.scroll.verticalScroller.offset;
    largePanes.last.scroll.verticalScroller.jumpTo(centered + 50);
    await tester.pumpAndSettle();
    // 同一个差异已可见且光标未变，再次跳转仍须主动居中。
    await tester.tap(find.byKey(const ValueKey('command-nextDiff')));
    await tester.pumpAndSettle();
    expect(
      largePanes.last.scroll.verticalScroller.offset,
      closeTo(centered, 1),
    );
    expect(
      largePanes.first.scroll.verticalScroller.offset,
      closeTo(centered, 1),
    );
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
    await chooseMenuCommand(tester, 'contextOnly');
    await tester.pumpAndSettle();
    expect(large.leftEditor.diffLayout!.totalRows, 12);
    expect(large.rightEditor.diffLayout!.totalRows, 12);
    expect(large.leftEditor.text, original.join('\n'));
    await chooseMenuCommand(tester, 'contextOnly');
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

    await git(['restore', 'file.txt']);
    await git(['branch', '-M', 'main']);
    await git(['checkout', '-qb', 'feature']);
    await gitFile.writeAsString('feature version\n');
    await git(['commit', '-qam', 'feature change']);
    await git(['checkout', '-q', 'main']);
    await gitFile.writeAsString('main version\n');
    await git(['commit', '-qam', 'main change']);
    await git(['checkout', '-q', 'feature']);
    final conflict = await Process.run(await GitReview.executable(), [
      'rebase',
      'main',
    ], workingDirectory: repository.path);
    expect(conflict.exitCode, 1);
    final snapshots = <String>[];
    for (var stage = 1; stage <= 3; stage++) {
      final snapshot = File('${dir.path}/rebase-stage$stage.txt');
      await snapshot.writeAsString(await git(['show', ':$stage:file.txt']));
      snapshots.add(snapshot.path);
    }
    final rebasing = await CompareSession.open(
      LaunchOptions(
        base: snapshots[0],
        left: snapshots[1],
        right: snapshots[2],
        output: gitFile.path,
      ),
    );
    expect(rebasing.mergeLabels.operation, MergeOperation.rebase);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          initial: rebasing,
          settings: Settings(persist: false),
          nativeWindow: true,
        ),
      ),
    );
    await ready(rebasing);
    expect(find.text('正在将 feature 变基到 main'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '采用目标历史'));
    await tester.pumpAndSettle();
    expect(rebasing.resultEditor!.text, 'main version\n');
    await tester.tap(find.widgetWithText(OutlinedButton, '采用本次提交'));
    await tester.pumpAndSettle();
    expect(rebasing.resultEditor!.text, 'feature version\n');
    await snapshot('rebase-sources');
    await windowManager.setSize(const Size(920, 680));
    await tester.pumpAndSettle();
    await snapshot('merge-compact');
    await git(['rebase', '--abort']);
    await gitFile.writeAsString('review unstaged change\n');
    final staging = CompareSession(
      TextFile.empty(await git(['show', 'HEAD:file.txt'])),
      await TextFile.read(gitFile.path),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          initial: staging,
          settings: Settings(persist: false),
          nativeWindow: true,
        ),
      ),
    );
    await ready(staging);
    await snapshot('diff-compact');
    staging.rightEditor.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodePane).last) + const Offset(90, 20),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await snapshot('stage-context');
    await tester.tap(find.text('暂存所选代码块'));
    final gitDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.textContaining('已暂存 1 个 Git 差异块').evaluate().isEmpty) {
      if (DateTime.now().isAfter(gitDeadline)) fail('Git 暂存超时');
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(await git(['show', ':file.txt']), 'review unstaged change\n');
    expect(await gitFile.readAsString(), 'review unstaged change\n');
    await snapshot('stage-result');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          settings: Settings(persist: false),
          nativeWindow: true,
        ),
      ),
    );
    await snapshot('welcome');
    await tester.tap(find.byKey(const ValueKey('command-settings')));
    await tester.pumpAndSettle();
    await snapshot('settings');
    await tester.tap(find.text('编辑器与外观').first);
    await tester.pumpAndSettle();
    await snapshot('settings-editor');
    await tester.tap(find.text('Git 集成').first);
    await tester.pumpAndSettle();
    await snapshot('settings-git');
    await tester.tap(find.text('复制文件比较配置'));
    await tester.pumpAndSettle();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      contains('difftool.fmerge.cmd'),
    );
    await tester.tap(find.text('快捷键').first);
    await tester.pumpAndSettle();
    await snapshot('settings-shortcuts');
    await tester.tap(find.byKey(const ValueKey('shortcut-open')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    await snapshot('shortcut-recorded');
    expect(find.textContaining('已用于“保存”'), findsOneWidget);
    await snapshot('shortcut-conflict');
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存快捷键'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件与权限').first);
    await tester.pumpAndSettle();
    await snapshot('settings-files');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建文本比较'));
    await tester.pumpAndSettle();
    final configured = tester
        .widget<CodePane>(find.byType(CodePane).last)
        .settings;
    expect(configured.shortcuts[AppCommand.open]!.key, LogicalKeyboardKey.f9);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    await snapshot('goto');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-文件')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('另存为…'));
    await tester.pumpAndSettle();
    await snapshot('format');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final blankPane = tester.widgetList<CodePane>(find.byType(CodePane)).last;
    blankPane.find.replaceMode();
    blankPane.find.toggleRegex();
    blankPane.find.findInputController.text = '[';
    await tester.pumpAndSettle();
    expect(find.text('正则无效'), findsOneWidget);
    await snapshot('find-invalid');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await windowManager.setSize(const Size(1100, 800));
    final context = List.generate(
      12,
      (i) => 'unchanged context $i;',
    ).join('\n');
    const moved = 'int movedValue = 42;\nreturn movedValue;';
    final long = '\tfinal getUserName = "${'中文 long_value ' * 9}";';
    final features = CompareSession(
      TextFile.empty('start\n$moved\n$long\n$context\nend'),
      TextFile.empty(
        'start\n${long.replaceFirst('getUserName', 'getUserNames')}\n$context\n$moved\nend',
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FmergeApp(
          initial: features,
          settings: Settings(persist: false)
            ..wordWrap = true
            ..inlineMode = InlineDiffMode.words,
          nativeWindow: true,
        ),
      ),
    );
    await ready(features);
    expect(features.diff!.movedBlocks, hasLength(1));
    features.rightEditor.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 12,
    );
    await snapshot('word-diff-wrap');
    final move = features.diff!.movedBlocks.single;
    features.leftEditor.selection = CodeLineSelection.collapsed(
      index: move.leftStart,
      offset: 0,
    );
    tester
        .widgetList<CodePane>(find.byType(CodePane))
        .first
        .focus
        .requestFocus();
    await tester.pumpAndSettle();
    await snapshot('moved-blocks');
    await tester.tap(find.byKey(const ValueKey('follow-moved-block')));
    await tester.pumpAndSettle();
    expect(features.rightEditor.selection.extentIndex, move.rightStart);
    features.leftEditor.selectAll();
    await features.leftEditor.copy();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      features.leftEditor.text,
    );
    await chooseMenuCommand(tester, 'contextOnly');
    await tester.pumpAndSettle();
    final rightPane = tester.widgetList<CodePane>(find.byType(CodePane)).last;
    rightPane.scroll.verticalScroller.jumpTo(0);
    await tester.pumpAndSettle();
    await snapshot('context-only');
    final appearance = rightPane.settings.themeMode;
    rightPane.settings.setAppearance(mode: ThemeMode.light);
    await tester.pumpAndSettle();
    await snapshot('context-only-light');
    rightPane.settings.setAppearance(mode: appearance);
    await tester.pumpAndSettle();
    final layout = features.rightEditor.diffLayout!;
    final first = tester
        .widgetList<DefaultCodeLineNumber>(find.byType(DefaultCodeLineNumber))
        .last
        .notifier
        .value!
        .paragraphs
        .first;
    final gap = layout.rowLabels.keys.first;
    final hiddenLine = layout.hiddenLines.first;
    final unit = first.preferredLineHeight;
    final y =
        first.offset.dy +
        (layout.wrap!.rowStart(gap) -
                layout.wrap!.rowStart(layout.lineRows[first.index]) +
                1) *
            unit;
    final rect = tester.getRect(find.byType(CodeEditor).last);
    await tester.tapAt(Offset(rect.center.dx, rect.top + y));
    await tester.pumpAndSettle();
    expect(features.contextOnly, false);
    expect(features.rightEditor.selection.extentIndex, hiddenLine);
    await snapshot('context-expanded');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
