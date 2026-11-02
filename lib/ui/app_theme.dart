import 'dart:io';

import 'package:flutter/material.dart';

import '../palette.dart';

ThemeData buildAppTheme() {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  final buttonStyle = ButtonStyle(
    shape: const WidgetStatePropertyAll(shape),
    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: bg,
      secondary: accent,
      surface: panel,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: border,
      error: red,
    ),
    fontFamily: Platform.isMacOS ? 'PingFang SC' : null,
    dividerColor: border,
    dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: ink, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: TextStyle(fontSize: 13, color: ink),
      subtitleTextStyle: TextStyle(fontSize: 12, color: muted),
      iconColor: muted,
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? muted.withValues(alpha: .4)
              : ink,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: border)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: muted,
        minimumSize: const Size(34, 34),
        padding: const EdgeInsets.all(7),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: muted, fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    ),
    cardTheme: CardThemeData(
      color: elevated,
      elevation: 0,
      shape: shape.copyWith(side: const BorderSide(color: border)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: elevated,
      surfaceTintColor: Colors.transparent,
      shape: shape.copyWith(side: const BorderSide(color: border)),
      textStyle: const TextStyle(color: ink, fontSize: 12),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(shape),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        side: const WidgetStatePropertyAll(BorderSide(color: border)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: .14)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? muted.withValues(alpha: .4)
              : states.contains(WidgetState.selected)
              ? accent
              : muted,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent.withValues(alpha: .2)
            : elevated,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(border),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: elevated,
      contentTextStyle: const TextStyle(color: ink, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: shape.copyWith(side: const BorderSide(color: border)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(color: ink, fontSize: 12),
      decoration: BoxDecoration(
        color: elevated,
        borderRadius: BorderRadius.all(Radius.circular(6)),
        border: Border.fromBorderSide(BorderSide(color: border)),
      ),
    ),
  );
}
