import 'package:flutter/material.dart';

class NeoColors {
  static const blue = Color(0xFF3494D6);
  static const blueDark = Color(0xFF176FAF);
  static const navy = Color(0xFF123A5D);
  static const ink = Color(0xFF17212B);
  static const muted = Color(0xFF617386);
  static const line = Color(0xFFDDE6EF);
  static const surface = Color(0xFFFFFFFF);
  static const page = Color(0xFFF5F8FB);
  static const success = Color(0xFF178A55);
  static const warning = Color(0xFFC98211);
  static const danger = Color(0xFFD13B3B);
}

class NeoSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class NeoRadius {
  static const sm = 6.0;
  static const md = 8.0;
}

class NeoTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: NeoColors.blue,
      brightness: Brightness.light,
      primary: NeoColors.blue,
      surface: NeoColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: NeoColors.page,
      fontFamily: 'Arial',
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: NeoColors.surface,
        foregroundColor: NeoColors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: NeoColors.line),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: NeoColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NeoRadius.sm),
          borderSide: const BorderSide(color: NeoColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NeoRadius.sm),
          borderSide: const BorderSide(color: NeoColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NeoRadius.sm),
          borderSide: const BorderSide(color: NeoColors.blue, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NeoColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NeoRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NeoColors.navy,
          side: const BorderSide(color: NeoColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NeoRadius.sm),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: NeoColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: NeoColors.line),
          borderRadius: BorderRadius.circular(NeoRadius.md),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: NeoColors.ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: NeoColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          color: NeoColors.ink,
          fontSize: 13,
        ),
        labelMedium: TextStyle(
          color: NeoColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
