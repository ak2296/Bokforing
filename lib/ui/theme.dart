import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const seed = Color(0xFF1F5C4D);
  static const warning = Color(0xFFB26A00);
  static const ok = Color(0xFF2E7D32);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}

/// Right-aligned tabular figures for money columns.
const moneyStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
