import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmerge/core/settings.dart';
import 'package:fmerge/ui/app_theme.dart';
import 'package:fmerge/ui/settings_dialog.dart';

void main() {
  testWidgets('撤销授权阻止重复操作并在失败后允许重试', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('fmerge/access');
    final firstRequest = Completer<void>();
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'revoke');
      if (++calls == 1) {
        await firstRequest.future;
        throw PlatformException(code: 'access', message: '无法清除书签');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsDialog(settings: Settings(persist: false)),
        ),
      ),
    );
    await tester.ensureVisible(find.text('撤销已授权文件与目录'));
    await tester.tap(find.text('撤销已授权文件与目录'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '正在撤销文件授权…'))
          .onPressed,
      isNull,
    );
    expect(calls, 1);
    firstRequest.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('撤销目录授权失败：'), findsOneWidget);
    await tester.ensureVisible(find.text('撤销已授权文件与目录'));
    await tester.tap(find.text('撤销已授权文件与目录'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('已清除文件与目录授权书签；重启后完全生效。'), findsOneWidget);
    expect(find.textContaining('撤销目录授权失败：'), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isMacOS);
}
