import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/ui/app_theme.dart';
import 'package:fmerge/ui/base_dialog.dart';
import 'package:fmerge/ui/code_pane.dart';

void main() {
  testWidgets('祖先预览可直接查找，保持只读且不改变原文件', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = List.generate(80, (i) => 'line $i').join('\n');
    final file = TextFile.empty(
      original,
    )..path = '/${List.filled(20, 'long-repository-directory').join('/')}/base';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BaseDialog(file: file, settings: Settings(persist: false)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('在共同祖先中查找'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'line 65');
    await tester.pumpAndSettle();
    final pane = tester.widget<CodePane>(find.byType(CodePane));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (pane.find.value?.result == null) {
        if (DateTime.now().isAfter(deadline)) fail('祖先查找超时');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(pane.find.value!.result!.matches, hasLength(1));
    expect(pane.readOnly, true);
    expect(find.byTooltip('替换'), findsNothing);
    expect(pane.controller.text, original);
    expect(file.text, original);
    expect(tester.takeException(), isNull);
  });
}
