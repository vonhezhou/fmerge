import 'dart:io';

import 'package:flutter/material.dart';

import '../palette.dart';

ThemeData buildAppTheme({AppPalette? palette}) {
  final colors = palette ?? palettes[ColorTheme.fmergeDark]!;
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
    brightness: colors.brightness,
    extensions: [colors],
    useMaterial3: true,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: colors.brightness,
      primary: colors.accent,
      onPrimary: colors.bg,
      secondary: colors.accent,
      surface: colors.panel,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      outline: colors.border,
      error: colors.red,
    ),
    fontFamily: Platform.isMacOS ? 'PingFang SC' : null,
    dividerColor: colors.border,
    dividerTheme: DividerThemeData(
      color: colors.border,
      space: 1,
      thickness: 1,
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: colors.ink, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, color: colors.muted, height: 1.5),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(fontSize: 13, color: colors.ink),
      subtitleTextStyle: TextStyle(fontSize: 12, color: colors.muted),
      iconColor: colors.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.muted.withValues(alpha: .4)
              : colors.ink,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.muted,
        minimumSize: const Size(34, 34),
        padding: const EdgeInsets.all(7),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: colors.muted, fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.accent, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    ),
    cardTheme: CardThemeData(
      color: colors.elevated,
      elevation: 0,
      shape: shape.copyWith(side: BorderSide(color: colors.border)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.elevated,
      surfaceTintColor: Colors.transparent,
      shape: shape.copyWith(side: BorderSide(color: colors.border)),
      textStyle: TextStyle(color: colors.ink, fontSize: 12),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(shape),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent.withValues(alpha: .14)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.muted.withValues(alpha: .4)
              : states.contains(WidgetState.selected)
              ? colors.accent
              : colors.muted,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent.withValues(alpha: .2)
            : colors.elevated,
      ),
      trackOutlineColor: WidgetStatePropertyAll(colors.border),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.elevated,
      contentTextStyle: TextStyle(color: colors.ink, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: shape.copyWith(side: BorderSide(color: colors.border)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(color: colors.ink, fontSize: 12),
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.all(Radius.circular(6)),
        border: Border.fromBorderSide(BorderSide(color: colors.border)),
      ),
    ),
  );
}
