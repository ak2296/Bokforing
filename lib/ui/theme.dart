import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const seed = Color(0xFF0B6B4E);
  static const ink = Color(0xFF10201B);
  static const muted = Color(0xFF62706A);
  static const background = Color(0xFFF5F7F4);
  static const hairline = Color(0xFFE8ECE6);
  static const tint = Color(0xFFE4F2EC);
  static const warning = Color(0xFF8A5300);
  static const warningTint = Color(0xFFFFF6E5);
  static const warningBorder = Color(0xFFF4E2BC);
  static const ok = Color(0xFF0B6B4E);
  /// Pumpkin orange, the second brand colour: expenses and "Osäker" readings.
  static const pumpkin = Color(0xFFE2600D);
  static const pumpkinLight = Color(0xFFF2832E);
  static const pumpkinPale = Color(0xFFF9B27A);
  static const pumpkinTint = Color(0xFFFDE6D3);
  static const pumpkinBorder = Color(0xFFF8C29A);
  static const pumpkinText = Color(0xFFB04A0A);

  /// "Osäker" readings: a stronger orange field than the yellow "Kontrollera".
  static const unsure = Color(0xFF873605);
  static const unsureTint = Color(0xFFF9C08E);

  /// Invoices missing data the reports need ("Fyll i"); red stays for overdue.
  static const fix = Color(0xFF3C3489);
  static const fixTint = Color(0xFFEEEDFE);
  static const fixBorder = Color(0xFFCECBF6);
  static const online = Color(0xFF7E3D12);
  static const onlineTint = Color(0xFFFCEBDD);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
      primary: seed,
      onSurface: ink,
      onSurfaceVariant: muted,
      surface: background,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: tint,
      outlineVariant: hairline,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Inter');
    final text = base.textTheme;
    final radius12 = BorderRadius.circular(14);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w500, color: ink),
        headlineSmall: text.headlineSmall?.copyWith(fontSize: 21, fontWeight: FontWeight.w500, color: ink),
        titleLarge: text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: ink),
        titleMedium: text.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: ink),
        titleSmall: text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: ink),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 14.5, color: ink),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 13.5, color: ink),
        bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: muted),
        labelLarge: text.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w500, color: ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: radius12, borderSide: const BorderSide(color: hairline)),
        enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: const BorderSide(color: hairline)),
        disabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: const BorderSide(color: hairline)),
        focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: const BorderSide(color: seed, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: hairline),
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: seed, textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500)),
      ),
      dividerTheme: const DividerThemeData(color: hairline, space: 1, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
      tabBarTheme: const TabBarThemeData(dividerColor: Colors.transparent),
    );
  }
}

/// Right-aligned tabular figures for money columns.
const moneyStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// A small rounded icon tile, as in the lists on the overview.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color color;
  const IconTile(this.icon, {super.key, this.background = AppTheme.tint, this.color = AppTheme.seed});

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, size: 18, color: color),
      );
}
