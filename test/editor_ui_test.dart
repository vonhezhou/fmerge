import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:fmerge/core/settings.dart';
import 'package:fmerge/ui/app_theme.dart';
import 'package:fmerge/ui/code_pane.dart';
import 'package:fmerge/ui/welcome_view.dart';

void main() {
  testWidgets('查找区分无匹配和无效正则，仅有效匹配可导航与替换', (tester) async {
    final editor = CodeLineEditingController.fromText('alpha beta alpha');
    late CodeFindController finder;
    await tester.runAsync(() async {
      finder = CodeFindController(editor);
    });
    final focus = FocusNode();
    final scroll = CodeScrollController();
    addTearDown(() {
      finder.dispose();
      editor.dispose();
      focus.dispose();
      scroll.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 460,
            child: CodePane(
              controller: editor,
              settings: Settings(persist: false),
              focus: focus,
              scroll: scroll,
              language: 'text',
              readOnly: false,
              find: finder,
            ),
          ),
        ),
      ),
    );
    finder.replaceMode();
    await tester.pumpAndSettle();
    // 查找浮层只能占用顶部区域，下方代码仍需能获取编辑焦点。
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodePane)) + const Offset(100, 130),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(finder.replaceInputFocusNode.hasFocus, isFalse);

    Future<void> query(String pattern) async {
      await tester.runAsync(() async {
        finder.findInputController.text = pattern;
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (finder.value?.searching == true) {
          if (DateTime.now().isAfter(deadline)) fail('查找超时');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
    }

    IconButton navigation(String tooltip) => tester.widget<IconButton>(
      find.widgetWithIcon(
        IconButton,
        tooltip == '上一处' ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
      ),
    );
    TextButton replaceAll() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, '全部替换'));

    await query('alpha');
    expect(find.text('1/2'), findsOneWidget);
    expect(navigation('下一处').onPressed, isNotNull);
    expect(replaceAll().onPressed, isNotNull);
    finder.replaceInputController.text = 'result';
    await tester.tap(find.widgetWithText(TextButton, '全部替换'));
    await tester.pumpAndSettle();
    expect(editor.text, 'result beta result');

    await query('missing');
    expect(find.text('无结果'), findsOneWidget);
    expect(navigation('上一处').onPressed, isNull);
    expect(navigation('下一处').onPressed, isNull);
    expect(replaceAll().onPressed, isNull);

    finder.toggleRegex();
    await query('[');
    expect(find.text('正则无效'), findsOneWidget);
    expect(navigation('下一处').onPressed, isNull);
    expect(replaceAll().onPressed, isNull);
    expect(editor.text, 'result beta result');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('最近记录忽略损坏项与合并入口，区分左右目录', (tester) async {
    final merge = <String, dynamic>{
      'left': '/current/src/file.dart',
      'right': '/incoming/src/file.dart',
    };
    Map<String, dynamic>? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: WelcomeView(
            onCompare: () {},
            onPaste: () {},
            recent: [
              <String, dynamic>{'left': 1},
              {...merge, 'base': '/ancestor/file.dart'},
              merge,
            ],
            onRecent: (entry) => opened = entry,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final row = find.widgetWithText(ListTile, 'file.dart  ↔  file.dart');
    await tester.ensureVisible(row);
    expect(find.text('左：/current/src'), findsOneWidget);
    expect(find.text('右：/incoming/src'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: row, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, contains('左侧：/current/src/file.dart'));
    expect(tooltip.message, contains('右侧：/incoming/src/file.dart'));
    expect(find.byIcon(Icons.merge), findsNothing);
    await tester.tap(row);
    expect(identical(opened, merge), true);
  });
}
