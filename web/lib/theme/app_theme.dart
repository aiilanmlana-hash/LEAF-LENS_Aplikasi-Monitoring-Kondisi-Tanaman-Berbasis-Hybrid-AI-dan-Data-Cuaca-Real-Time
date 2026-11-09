import 'package:flutter/material.dart';

abstract final class PlantPalette {
  // The palette stays botanical, but uses the cooler, brighter contrast of
  // contemporary Apple-style translucent surfaces.
  static const forest = Color(0xFF193D35);
  static const sage = Color(0xFF56766A);
  static const olive = Color(0xFF61793B);
  static const sand = Color(0xFFE0D7C0);
  static const clay = Color(0xFF8E6D51);
  static const ink = Color(0xFF13261F);
  static const canvas = Color(0xFFF1F6F2);
  static const paper = Color(0xFFF9FCFA);
  static const border = Color(0xFFD7E6DE);
  static const red = Color(0xFF9A4540);
  static const orange = Color(0xFF8F4E1F);
}

abstract final class PlantTheme {
  static const _fontFamily = 'Avenir Next';

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: PlantPalette.forest,
      brightness: Brightness.light,
      primary: PlantPalette.forest,
      onPrimary: Colors.white,
      secondary: PlantPalette.olive,
      surface: PlantPalette.paper.withValues(alpha: 0.78),
      onSurface: PlantPalette.ink,
      error: PlantPalette.red,
    );
    final baseTextTheme = ThemeData.light().textTheme.apply(
      fontFamily: _fontFamily,
      fontFamilyFallback: const ['Inter', 'Arial', 'sans-serif'],
      bodyColor: PlantPalette.ink,
      displayColor: PlantPalette.ink,
    );
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.08,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.08,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.12,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.12,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.14,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.18,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontFamily: _fontFamily,
        letterSpacing: 0,
        height: 1.2,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: Colors.white.withValues(alpha: 0.55),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: PlantPalette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: PlantPalette.paper.withValues(alpha: 0.60),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: PlantPalette.forest.withValues(alpha: 0.10),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.48),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PlantPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PlantPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PlantPalette.sage, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PlantPalette.forest,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PlantPalette.forest,
          minimumSize: const Size(44, 48),
          side: const BorderSide(color: PlantPalette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: PlantPalette.olive,
        thumbColor: PlantPalette.forest,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: const IconThemeData(color: PlantPalette.forest),
        unselectedIconTheme: const IconThemeData(color: PlantPalette.sage),
        selectedLabelTextStyle: const TextStyle(
          color: PlantPalette.forest,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: PlantPalette.sage),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: PlantPalette.sage.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(color: PlantPalette.forest),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PlantPalette.paper.withValues(alpha: 0.84),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}
