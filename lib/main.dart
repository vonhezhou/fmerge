import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/launch.dart';
import 'core/access.dart';
import 'core/settings.dart';
import 'session.dart';
import 'ui/workbench.dart';
import 'palette.dart';
import 'ui/app_theme.dart';

Future<void> main(List<String> args) async {
  LaunchOptions options;
  try {
    options = LaunchOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(LaunchOptions.usage);
    exit(64);
  }
  if (options.help) {
    stdout.write(LaunchOptions.usage);
    exit(0);
  }
  if (options.version) {
    stdout.writeln('fmerge 0.1.0');
    exit(0);
  }
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  CompareSession? initial;
  String? startupError;
  try {
    await DirectoryAccess.restore();
    if (options.left != null) {
      for (final path in [
        options.left!,
        options.right!,
        if (options.base != null) options.base!,
      ]) {
        await DirectoryAccess.read(path);
      }
      if (options.output != null) await DirectoryAccess.write(options.output!);
      initial = await CompareSession.open(options);
    }
  } catch (e) {
    startupError = e.toString();
  }
  Settings settings;
  try {
    settings = await Settings.load();
  } catch (_) {
    settings = Settings();
  }
  await windowManager.setPreventClose(true);
  runApp(
    FmergeApp(
      initial: initial,
      settings: settings,
      options: options,
      startupError: startupError,
      nativeWindow: true,
    ),
  );
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(920, 680),
      center: true,
      title: 'fmerge',
      backgroundColor: bg,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class FmergeApp extends StatelessWidget {
  const FmergeApp({
    super.key,
    required this.settings,
    this.initial,
    this.options = const LaunchOptions(),
    this.startupError,
    this.nativeWindow = false,
    this.onExit,
  });
  final Settings settings;
  final CompareSession? initial;
  final LaunchOptions options;
  final String? startupError;
  final bool nativeWindow;
  final ValueChanged<int>? onExit;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fmerge',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Workbench(
      initial: initial,
      settings: settings,
      options: options,
      startupError: startupError,
      nativeWindow: nativeWindow,
      onExit: onExit,
    ),
  );
}
