import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:fmerge/core/access.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/launch.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/main.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/document_status.dart';
import 'package:fmerge/ui/toolbar_action.dart';

Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail('等待界面操作完成超时');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

void desktopTest(String name, Future<void> Function(WidgetTester) callback) =>
    testWidgets(
      name,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

void main() {
  desktopTest('重新加载读取外部修改，取消时保留未保存编辑', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fmerge-reload-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final left = File('${dir.path}/left.txt')..writeAsStringSync('left');
    final right = File('${dir.path}/right.txt')..writeAsStringSync('right');
    late CompareSession s;
    await tester.runAsync(() async {
      s = CompareSession(
        await TextFile.read(left.path),
        await TextFile.read(right.path),
      );
    });
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await waitUntil(tester, () => !s.busy);
    s.rightEditor.text = 'unsaved';
    await tester.pump(const Duration(milliseconds: 170));
    right.writeAsStringSync('external');
    await tester.tap(find.byKey(const ValueKey('command-reload')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(s.rightEditor.text, 'unsaved');
    expect(right.readAsStringSync(), 'external');
    await tester.tap(find.byKey(const ValueKey('command-reload')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存'));
    await waitUntil(
      tester,
      () =>
          tester
                  .widgetList<CodePane>(find.byType(CodePane))
                  .last
                  .controller
                  .text ==
              'external' &&
          find.text('正在比较…').evaluate().isEmpty,
    );
    expect(
      tester.widgetList<CodePane>(find.byType(CodePane)).first.controller.text,
      'left',
    );
    expect(right.readAsStringSync(), 'external');
    expect(tester.takeException(), isNull);
  });

  desktopTest('合并工具栏双向循环跳转冲突，编辑后使用更新的位置', (tester) async {
    final s = CompareSession(
      TextFile.empty('a\nleft1\nb\nc\nleft2\nd'),
      TextFile.empty('a\nright1\nb\nc\nright2\nd'),
      base: TextFile.empty('a\nbase1\nb\nc\nbase2\nd'),
    );
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await waitUntil(tester, () => !s.busy);
    expect(s.merger!.state.regions.length, 2);
    Future<void> jump(String command, int index) async {
      await tester.tap(find.byKey(ValueKey('command-$command')));
      await tester.pumpAndSettle();
      expect(
        s.resultEditor!.selection.extentIndex,
        s.merger!.state.regions[index].start,
      );
      expect(
        tester.widgetList<CodePane>(find.byType(CodePane)).last.focus.hasFocus,
        true,
      );
    }

    await jump('nextConflict', 1);
    await jump('nextConflict', 0);
    await jump('previousConflict', 1);
    s.resultEditor!.text = 'header\n${s.resultEditor!.text}';
    await tester.pumpAndSettle();
    await jump('previousConflict', 0);
    expect(tester.takeException(), isNull);
  });

  for (final pair in [true, false]) {
    desktopTest('直接选择${pair ? '两个' : '一个后继续选择另一个'}文件，取消第二次选择不替换当前内容', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('fmerge-picker-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final left = File('${dir.path}/left.txt')..writeAsStringSync('left');
      final right = File('${dir.path}/right.txt')..writeAsStringSync('right');
      final previous = FileSelectorPlatform.instance;
      final picker = Picker(
        pair ? [left.path, right.path] : [left.path],
        right.path,
      );
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      await tester.pumpWidget(FmergeApp(settings: Settings(persist: false)));
      await tester.tap(find.byKey(const ValueKey('command-open')));
      await waitUntil(
        tester,
        () =>
            find.byType(CodePane).evaluate().length == 2 &&
            find.text('正在比较…').evaluate().isEmpty,
      );
      expect(picker.multipleCalls, 1);
      expect(picker.singleCalls, pair ? 0 : 1);
      final panes = tester.widgetList<CodePane>(find.byType(CodePane)).toList();
      expect(panes.first.controller.text, 'left');
      expect(panes.last.controller.text, 'right');
      expect(find.text('打开文件比较'), findsNothing);
      expect(find.byType(DocumentStatus), findsNWidgets(2));
      picker.paths = [left.path];
      picker.second = null;
      await tester.tap(find.byKey(const ValueKey('command-open')));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.widgetList<CodePane>(find.byType(CodePane)).last.controller,
          panes.last.controller,
        ),
        true,
      );
    });
  }

  desktopTest('双向采用差异保护锁定的左侧，工具栏文字可隐藏再显示', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = CompareSession(TextFile.empty('left'), TextFile.empty('right'));
    final settings = Settings(persist: false);
    await tester.pumpWidget(FmergeApp(settings: settings, initial: s));
    await waitUntil(tester, () => !s.busy);
    ToolbarAction takeRight() => tester.widget<ToolbarAction>(
      find.byWidgetPredicate(
        (w) =>
            w is ToolbarAction && w.key == const ValueKey('command-takeRight'),
      ),
    );
    expect(takeRight().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('command-toggleLeftEdit')));
    await tester.pumpAndSettle();
    expect(takeRight().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('command-takeRight')));
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    expect(s.leftEditor.text, 'right');
    expect(s.rightEditor.text, 'right');
    expect(s.leftDirty, true);
    for (final expected in [false, true]) {
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '显示工具栏文字'),
      );
      await tester.pumpAndSettle();
      expect(settings.toolbarLabels, expected);
      expect(
        tester
            .widgetList<ToolbarAction>(find.byType(ToolbarAction))
            .every((tool) => tool.showLabel == expected),
        true,
      );
    }
    expect(tester.takeException(), isNull);
  });

  desktopTest('底部更换输入编码只重读该侧，保留另一侧编辑并保护未保存修改', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fmerge-footer-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = File('${dir.path}/left.txt')..writeAsStringSync('café');
    final left = (await tester.runAsync(() => TextFile.read(path.path)))!;
    final s = CompareSession(left, TextFile.empty('right'));
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await waitUntil(tester, () => !s.busy);
    s.rightEditor.text = 'keep edited';
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    Future<void> encoding(String name) async {
      await tester.tap(find.byTooltip('编码 · 按所选编码重新读取').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, name));
    }

    await tester.runAsync(() => encoding('Latin-1'));
    await waitUntil(
      tester,
      () => s.left.encoding == TextEncoding.latin1 && !s.busy,
    );
    expect(s.leftEditor.text, 'cafÃ©');
    expect(s.rightEditor.text, 'keep edited');
    s.leftEditor.text = 'unsaved left';
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    await encoding('UTF-8');
    await tester.pumpAndSettle();
    expect(find.text('重新按编码读取文件'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(s.leftEditor.text, 'unsaved left');
    expect(s.rightEditor.text, 'keep edited');
  });

  desktopTest('右键暂存选择的 Git 差异块，未保存内容禁止暂存，工作区与其他块保持不变', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fmerge-stage-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/file.txt');
    final lines = List.generate(40, (i) => 'line $i');
    final original = '${lines.join('\n')}\n';
    Future<String> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: dir.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return r.stdout as String;
    }

    late TextFile right;
    await tester.runAsync(() async {
      await git(['init', '-q']);
      await file.writeAsString(original);
      await git(['add', '.']);
      await git([
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.invalid',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'core.hooksPath=/dev/null',
        'commit',
        '-qm',
        'fixture',
      ]);
      lines[3] = 'stage selected';
      lines[30] = 'leave unstaged';
      await file.writeAsString('${lines.join('\n')}\n');
      right = await TextFile.read(file.path);
    });
    final s = CompareSession(TextFile.empty(original), right);
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await waitUntil(tester, () => !s.busy);
    expect(find.byTooltip('Git · 按块暂存 / 取消暂存'), findsNothing);
    Future<void> stage() async {
      s.rightEditor.selection = const CodeLineSelection(
        baseIndex: 3,
        baseOffset: 0,
        extentIndex: 3,
        extentOffset: 14,
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(CodePane).last) + const Offset(90, 90),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂存所选代码块'));
    }

    s.rightEditor.text = '${right.text}\nunsaved';
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    await stage();
    await tester.pumpAndSettle();
    expect(find.text('请先保存当前文件，再暂存所选代码块'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => expect(await git(['show', ':file.txt']), original),
    );
    s.rightEditor.text = right.text;
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    await tester.runAsync(stage);
    await waitUntil(
      tester,
      () => find.textContaining('已暂存 1 个 Git 差异块').evaluate().isNotEmpty,
    );
    await tester.runAsync(() async {
      final index = await git(['show', ':file.txt']);
      expect(index, contains('stage selected'));
      expect(index, isNot(contains('leave unstaged')));
      expect(await file.readAsString(), '${lines.join('\n')}\n');
    });
    expect(tester.takeException(), isNull);
  });

  test('macOS 旧最近记录缺权限时请求目录授权，明确所选文件可登记书签', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-access-');
    final file = File('${dir.path}/file.txt')..writeAsStringSync('protected');
    const channel = MethodChannel('fmerge/access');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'grant') {
            await Process.run('chmod', ['600', file.path]);
            return true;
          }
          return null;
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await Process.run('chmod', ['600', file.path]);
      await dir.delete(recursive: true);
    });
    await Process.run('chmod', ['000', file.path]);
    await DirectoryAccess.read(file.path);
    expect(calls.single.method, 'grant');
    expect((calls.single.arguments as Map)['path'], dir.absolute.path);
    expect(await file.readAsString(), 'protected');
    await DirectoryAccess.rememberFiles([file.path]);
    expect(calls.last.method, 'rememberFiles');
    expect((calls.last.arguments as Map)['paths'], [file.path]);
  }, skip: !Platform.isMacOS);

  test('合并结果编码和换行修改进入未保存状态，保存后清理格式状态', () async {
    final dir = await Directory.systemTemp.createTemp('fmerge-output-format-');
    addTearDown(() => dir.delete(recursive: true));
    final s = CompareSession(
      TextFile.empty('a\nb'),
      TextFile.empty('a\nb'),
      base: TextFile.empty('a\nb'),
    );
    addTearDown(s.dispose);
    await s.saveResult(destination: '${dir.path}/result');
    expect(s.dirty, false);
    s.setSaveEncoding(2, TextEncoding.utf16le);
    s.setSaveEol(2, '\r\n');
    expect(s.resultDirty, true);
    expect(s.toolExitCode, 1);
    await s.saveResult();
    final saved = await TextFile.read('${dir.path}/result');
    expect(saved.encoding, TextEncoding.utf16le);
    expect(saved.eol, 'CRLF');
    expect(saved.text, 'a\nb');
    expect(s.dirty, false);
    expect(s.toolExitCode, 0);
    s.setSaveEol(2, '\n');
    await s.saveResult(usePendingFormat: false);
    expect((await TextFile.read('${dir.path}/result')).eol, 'CRLF');
    expect(s.dirty, false);
  });

  desktopTest('普通保存不因底部格式控件而给 UTF-16 无 BOM 文件添加 BOM', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fmerge-no-bom-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/file')
      ..writeAsBytesSync(
        TextFile.encode('old', TextEncoding.utf16le).sublist(2),
      );
    final right = (await tester.runAsync(
      () => TextFile.read(file.path, encoding: TextEncoding.utf16le),
    ))!;
    final s = CompareSession(TextFile.empty('left'), right);
    await tester.pumpWidget(
      FmergeApp(settings: Settings(persist: false), initial: s),
    );
    await waitUntil(tester, () => !s.busy);
    s.rightEditor.text = 'new';
    await tester.pump(const Duration(milliseconds: 170));
    await waitUntil(tester, () => !s.busy);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('command-save'))),
    );
    await waitUntil(tester, () => !s.rightDirty);
    expect(
      file.readAsBytesSync(),
      TextFile.encode('new', TextEncoding.utf16le).sublist(2),
    );
  });

  test('可复制的 Git 配置正确引用带空格与单引号的可执行路径及 Git 变量', () async {
    final config = LaunchOptions.gitConfiguration(
      '/Applications/my app\'s/fmerge',
    );
    final syntax = await Process.run('sh', ['-n', '-c', config]);
    expect(syntax.exitCode, 0, reason: '${syntax.stderr}');
    expect(config, contains('\$LOCAL'));
    expect(config, contains('--base'));
    expect(config, contains('--output'));
    expect(config, contains('mergetool.fmerge.trustExitCode true'));
  });
}

class Picker extends FileSelectorPlatform {
  Picker(this.paths, this.second);
  List<String> paths;
  String? second;
  int multipleCalls = 0, singleCalls = 0;
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    multipleCalls++;
    return paths.map(XFile.new).toList();
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    singleCalls++;
    return second == null ? null : XFile(second!);
  }
}
