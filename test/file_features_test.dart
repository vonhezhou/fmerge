import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/git.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/compare_task.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/git_review_dialog.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final seen = <String>{};
  await tester.runAsync(() async {
    final limit = DateTime.now().add(const Duration(seconds: 10));
    while (!ready()) {
      seen.addAll(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>(),
      );
      if (DateTime.now().isAfter(limit)) fail('等待操作完成超时：${seen.join(' | ')}');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

Future<void> invoke(
  WidgetTester tester,
  String command, {
  String menu = '视图',
}) async {
  await tester.tap(find.byKey(ValueKey('menu-$menu')));
  await tester.pumpAndSettle();
  final item = find.byKey(ValueKey('menu-command-$command'));
  await tester.ensureVisible(item);
  // 文件与 Git 进程的真实 I/O 从真实异步区启动，避免进程等待落入 FakeAsync。
  await tester.runAsync(() => tester.tap(item));
  await tester.pump();
}

void desktopTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

class FeaturePicker extends FileSelectorPlatform {
  final paths = <String>[];
  String? destination;
  Completer<List<XFile>>? deferred;
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      deferred == null ? paths.map(XFile.new).toList() : deferred!.future;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => paths.isEmpty ? null : XFile(paths.removeAt(0));
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => destination == null ? null : FileSaveLocation(destination!);
}

void main() {
  late Directory dir;
  late FeaturePicker picker;
  late FileSelectorPlatform previous;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fmerge-features-');
    previous = FileSelectorPlatform.instance;
    picker = FeaturePicker();
    FileSelectorPlatform.instance = picker;
  });
  tearDown(() {
    FileSelectorPlatform.instance = previous;
    dir.deleteSync(recursive: true);
  });
  File file(String name, String text) =>
      File('${dir.path}/$name')..writeAsStringSync(text);
  Future<void> app(
    WidgetTester tester,
    CompareSession? s, {
    Settings? settings,
    LaunchOptions options = const LaunchOptions(),
    ValueChanged<int>? onExit,
  }) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FmergeApp(
        settings: settings ?? Settings(persist: false),
        initial: s,
        options: options,
        onExit: onExit,
      ),
    );
    await waitFor(tester, () => s?.busy != true);
  }

  desktopTest('加载期间输入使替换作废，保留原会话与新编辑', (tester) async {
    final left = file('left', 'new left'), right = file('right', 'new right');
    picker.deferred = Completer<List<XFile>>();
    final s = CompareSession(
      TextFile.empty('old left'),
      TextFile.empty('old right'),
      compareRunner: (task) async => runCompareTask(task),
    );
    await app(tester, s);
    await tester.tap(find.byKey(const ValueKey('command-open')));
    await tester.pump();
    await tester.runAsync(() async {
      picker.deferred!.complete([XFile(left.path), XFile(right.path)]);
      await Future<void>.delayed(Duration.zero);
      s.rightEditor.text = 'edit during loading';
    });
    await waitFor(
      tester,
      () => find.text('加载期间有新的修改，已保留当前会话，请重新打开').evaluate().isNotEmpty,
    );
    expect(
      tester.widgetList<CodePane>(find.byType(CodePane)).last.controller,
      same(s.rightEditor),
    );
    expect(s.rightEditor.text, 'edit during loading');
    expect(s.rightDirty, true);
  });

  desktopTest('Git 合并取消后换开普通比较，关闭仍返回未完成', (tester) async {
    final s = CompareSession(
      TextFile.empty('left'),
      TextFile.empty('right'),
      base: TextFile.empty('base'),
    );
    picker.paths.addAll([file('a', 'a').path, file('b', 'b').path]);
    int? code;
    await app(
      tester,
      s,
      options: const LaunchOptions(
        base: 'base',
        left: 'left',
        right: 'right',
        output: 'output',
      ),
      onExit: (value) => code = value,
    );
    await tester.tap(find.byKey(const ValueKey('command-open')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('不保存')));
    await waitFor(
      tester,
      () =>
          find.byType(CodePane).evaluate().length == 2 &&
          find.text('正在比较…').evaluate().isEmpty,
    );
    await invoke(tester, 'close', menu: '文件');
    expect(code, 1);
  });

  desktopTest('新建比较取消时保留编辑，确认丢弃后两侧均为空且可编辑', (tester) async {
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    await app(tester, s);
    s.rightEditor.text = 'unsaved';
    await tester.pump(const Duration(milliseconds: 170));
    await waitFor(tester, () => !s.busy);
    await invoke(tester, 'newCompare', menu: '文件');
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(s.rightEditor.text, 'unsaved');
    await invoke(tester, 'newCompare', menu: '文件');
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('不保存')));
    await waitFor(
      tester,
      () =>
          find.byType(CodePane).evaluate().length == 2 &&
          tester.widgetList<CodePane>(find.byType(CodePane)).last.controller !=
              s.rightEditor &&
          find.text('正在比较…').evaluate().isEmpty,
    );
    final panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
    expect(panes.every((p) => p.controller.text.isEmpty && !p.readOnly), true);
  });

  desktopTest('三方选择面板回填最近路径，取消不影响当前未保存内容', (tester) async {
    final settings = Settings(persist: false);
    settings.remember('/left.txt', '/right.txt', '/base.txt', '/out.txt');
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    await app(tester, s, settings: settings);
    s.rightEditor.text = 'unsaved';
    await tester.pump(const Duration(milliseconds: 170));
    await waitFor(tester, () => !s.busy);
    await invoke(tester, 'open-merge', menu: '文件');
    await tester.pumpAndSettle();
    final expected = ['/base.txt', '/left.txt', '/right.txt', '/out.txt'];
    for (var i = 0; i < 4; i++) {
      expect(
        tester
            .widget<TextFormField>(find.byKey(ValueKey('merge-path-$i')))
            .controller!
            .text,
        expected[i],
      );
    }
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(s.rightEditor.text, 'unsaved');
    expect(find.text('有尚未保存的修改'), findsNothing);
  });

  desktopTest('Git 预览加载可取消，结束后允许关闭和刷新', (tester) async {
    final path = file('tracked', 'text').path;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitReviewDialog(path: path, encoding: TextEncoding.utf8),
        ),
      ),
    );
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '取消操作'),
    );
    cancel.onPressed!();
    await waitFor(
      tester,
      () => find.textContaining('操作已取消').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '关闭'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '刷新 Git 差异',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  desktopTest('文件菜单打开三方合并，明确选择来源和输出', (tester) async {
    picker.paths.addAll([
      file('base', 'base').path,
      file('left', 'left').path,
      file('right', 'right').path,
    ]);
    picker.destination = '${dir.path}/merged';
    await app(tester, null);
    await invoke(tester, 'open-merge', menu: '文件');
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => tester.tap(find.byKey(ValueKey('merge-browse-$i'))),
      );
      await tester.pumpAndSettle();
    }
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('merge-open'))),
    );
    await waitFor(
      tester,
      () =>
          find.byType(CodePane).evaluate().length == 3 &&
          find.text('正在比较…').evaluate().isEmpty,
    );
    final panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
    expect(panes[0].controller.text, 'left');
    expect(panes[1].controller.text, 'right');
    expect(panes[2].controller.text, 'base');
    expect(File(picker.destination!).existsSync(), false);
    expect(find.textContaining('1 处冲突'), findsWidgets);
  });

  desktopTest('拖放替换指定侧保留另一侧未保存文本，取消替换不丢修改', (tester) async {
    final dropped = file('drop', 'dropped');
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    s.leftEditor.text = 'left unsaved';
    await app(tester, s);
    void drop() =>
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(dropped.path)],
            localPosition: const Offset(1500, 100),
            globalPosition: const Offset(1500, 100),
          ),
        );
    drop();
    await waitFor(tester, () => s.rightEditor.text == 'dropped');
    expect(s.leftEditor.text, 'left unsaved');
    expect(s.leftDirty, true);
    s.rightEditor.text = 'right unsaved';
    drop();
    await tester.pumpAndSettle();
    expect(find.text('替换此侧文件？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(s.rightEditor.text, 'right unsaved');
    await tester.pump(const Duration(milliseconds: 170));
    await waitFor(tester, () => !s.busy);
  });

  desktopTest('Git 预览可选择区块暂存与取消暂存，不改写工作区', (tester) async {
    final disk = file('tracked', 'old\n');
    late CompareSession s;
    await tester.runAsync(() async {
      await GitReview.executable();
      for (final args in [
        ['init', '-q'],
        ['config', 'user.name', 'Test'],
        ['config', 'user.email', 'test@example.invalid'],
        ['config', 'commit.gpgsign', 'false'],
        ['add', 'tracked'],
        ['commit', '-qm', 'initial'],
      ]) {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: dir.path,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      disk.writeAsStringSync('new\n');
      s = CompareSession(
        TextFile.empty('old\n'),
        await TextFile.read(disk.path),
      );
    });
    await app(tester, s);
    await invoke(tester, 'git-review', menu: '工具');
    await waitFor(tester, () => find.text('区块 1').evaluate().isNotEmpty);
    await tester.tap(find.text('选择全部区块'));
    await tester.pump();
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '暂存所选块')),
    );
    await waitFor(tester, () => find.text('此文件没有对应修改').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('已暂存')));
    await waitFor(tester, () => find.text('区块 1').evaluate().isNotEmpty);
    await tester.tap(find.text('选择全部区块'));
    await tester.pump();
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '取消暂存所选块')),
    );
    await waitFor(tester, () => find.text('此文件没有对应修改').evaluate().isNotEmpty);
    expect(disk.readAsStringSync(), 'new\n');
    await tester.runAsync(() async {
      final result = await Process.run('git', [
        'show',
        ':tracked',
      ], workingDirectory: dir.path);
      expect(result.stdout, 'old\n');
    });
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}
