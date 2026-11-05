import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> chooseMenuCommand(
  WidgetTester tester,
  String command, {
  String menu = '视图',
}) async {
  await tester.tap(find.byKey(ValueKey('menu-$menu')));
  await tester.pumpAndSettle();
  final item = find.byKey(ValueKey('menu-command-$command'));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}
