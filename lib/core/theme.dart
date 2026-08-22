import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dark, instrument-panel aesthetic: near-black background, teal accent
/// for live/active states, soft gold for highlights - matches the Zentra
/// marketing site's visual language.
class ZentraColors {
  static const background = Color(0xFF0A0E14);
  static const surface = Color(0xFF12171F);
  static const surfaceElevated = Color(0xFF1A212C);
  static const teal = Color(0xFF2DD4BF);
  static const gold = Color(0xFFE8B04B);
  static const danger = Color(0xFFE05C5C);
  static const textPrimary = Color(0xFFF4F6F8);
  static const textSecondary = Color(0xFF8C99A8);
  static const divider = Color(0xFF232B37);
}

ThemeData buildZentraTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: ZentraColors.textPrimary,
    displayColor: ZentraColors.textPrimary,
  );

  return base.copyWith(
    scaffoldBackgroundColor: ZentraColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: ZentraColors.teal,
      secondary: ZentraColors.gold,
      surface: ZentraColors.surface,
      error: ZentraColors.danger,
    ),
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: ZentraColors.background,
      elevation: 0,
      centerTitle: false,
      foregroundColor: ZentraColors.textPrimary,
    ),
    cardTheme: CardThemeData(
      color: ZentraColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: ZentraColors.divider),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: ZentraColors.surface,
      selectedItemColor: ZentraColors.teal,
      unselectedItemColor: ZentraColors.textSecondary,
      type: BottomNavigationBarType.fixed,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ZentraColors.teal,
        foregroundColor: ZentraColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    dividerColor: ZentraColors.divider,
  );
}
