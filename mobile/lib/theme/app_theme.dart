import 'package:flutter/material.dart';

abstract final class PlantColors {
  static const olive = Color(0xFF727444);
  static const sand = Color(0xFFD2BD96);
  static const espresso = Color(0xFF2E3028);
  static const clay = Color(0xFF8A6B4E);
  static const sage = Color(0xFF6C806C);
  static const leaf = Color(0xFF344A3C);

  static const canvas = Color(0xFFF4F2EB);
  static const surface = Color(0xFFFFFEFA);
  static const darkCanvas = Color(0xFF242B25);
  static const darkSurface = Color(0xFF34433A);
  static const forest = Color(0xFF344A3C);
}

abstract final class AppTheme {
  static ThemeData get light => _buildTheme(
        brightness: Brightness.light,
        canvas: PlantColors.canvas,
        surface: PlantColors.surface,
        foreground: PlantColors.espresso,
        accent: PlantColors.olive,
      );

  static ThemeData get dark => _buildTheme(
        brightness: Brightness.dark,
        canvas: PlantColors.darkCanvas,
        surface: PlantColors.darkSurface,
        foreground: PlantColors.sand,
        accent: PlantColors.sand,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color canvas,
    required Color surface,
    required Color foreground,
    required Color accent,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: PlantColors.olive,
      brightness: brightness,
      primary: accent,
      onPrimary:
          brightness == Brightness.light ? Colors.white : PlantColors.espresso,
      secondary: PlantColors.clay,
      onSecondary: Colors.white,
      tertiary: PlantColors.leaf,
      surface: surface,
      onSurface: foreground,
      error: const Color(0xFFB4513E),
    );
    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: brightness == Brightness.light
            ? Colors.white.withValues(alpha: 0.78)
            : PlantColors.sand.withValues(alpha: 0.16),
      ),
    );
    final baseTextTheme = ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: 'Arial',
          bodyColor: foreground,
          displayColor: foreground,
        );
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(fontFamily: 'serif'),
      displayMedium: baseTextTheme.displayMedium?.copyWith(fontFamily: 'serif'),
      displaySmall: baseTextTheme.displaySmall?.copyWith(fontFamily: 'serif'),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(fontFamily: 'serif'),
      headlineMedium:
          baseTextTheme.headlineMedium?.copyWith(fontFamily: 'serif'),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontFamily: 'serif',
        letterSpacing: -0.45,
        height: 1.18,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(fontFamily: 'serif'),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: canvas,
      dividerColor: Colors.white.withValues(alpha: 0.54),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          fontFamily: 'serif',
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: brightness == Brightness.light
            ? surface.withValues(alpha: 0.78)
            : surface.withValues(alpha: 0.82),
        surfaceTintColor: Colors.transparent,
        elevation: brightness == Brightness.light ? 1 : 0,
        shadowColor: PlantColors.forest.withValues(alpha: 0.09),
        margin: EdgeInsets.zero,
        shape: roundedShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(
          alpha: brightness == Brightness.light ? 0.82 : 0.92,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: PlantColors.olive.withValues(alpha: 0.24)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: PlantColors.olive.withValues(alpha: 0.24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PlantColors.forest,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: PlantColors.olive.withValues(alpha: 0.35)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: PlantColors.olive.withValues(alpha: 0.16),
        elevation: 0,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: PlantColors.olive,
        thumbColor: PlantColors.olive,
        inactiveTrackColor: PlantColors.sand.withValues(alpha: 0.55),
        rangeThumbShape:
            const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: PlantColors.sand.withValues(alpha: 0.24),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
