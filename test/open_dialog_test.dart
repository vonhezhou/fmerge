import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/files.dart';
import 'package:fmerge/session.dart';
import 'package:fmerge/ui/open_dialog.dart';

void main() {
  testWidgets('打开对话框可分别选择编码，交换时编码跟随文件', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('fmerge-open-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final left = File('${dir.path}/latin1')
      ..writeAsBytesSync(TextFile.encode('café', TextEncoding.latin1));
    final right = File(
      '${dir.path}/utf16',
    )..writeAsBytesSync(TextFile.encode('中文', TextEncoding.utf16be).sublist(2));
    final opened = Completer<CompareSession?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => opened.complete(
                await showDialog<CompareSession>(
                  context: context,
                  builder: (_) => const OpenDialog(),
                ),
              ),
              child: const Text('选择文件'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), left.path);
    await tester.enterText(find.byType(TextField).at(1), right.path);
    final dropdowns = find.byType(DropdownButtonFormField<TextEncoding?>);
    await tester.tap(dropdowns.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Latin-1').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UTF-16 BE').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('交换左右'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<TextEncoding?>>(dropdowns.at(0))
          .initialValue,
      TextEncoding.utf16be,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<TextEncoding?>>(dropdowns.at(1))
          .initialValue,
      TextEncoding.latin1,
    );
    final session = await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '打开'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!opened.isCompleted) {
        if (DateTime.now().isAfter(deadline)) fail('打开文件超时');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();
      }
      return opened.future;
    });
    expect(session, isNotNull);
    addTearDown(session!.dispose);
    expect(session.left.text, '中文');
    expect(session.right.text, 'café');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
