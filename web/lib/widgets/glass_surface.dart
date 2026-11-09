import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 22,
    this.tint = Colors.white,
    this.opacity = 0.62,
    this.blur = 18,
    this.borderOpacity = 0.72,
    this.shadowOpacity = 0.08,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color tint;
  final double opacity;
  final double blur;
  final double borderOpacity;
  final double shadowOpacity;

  // Keep the translucent surface lightweight by default. Blur is opt-in and
  // capped so it does not dominate repaint cost on integrated GPUs.
  static const _enableBackdropBlur = bool.fromEnvironment(
    'ENABLE_GLASS_BLUR',
    defaultValue: false,
  );

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final highlightOpacity = (opacity + 0.12).clamp(0.0, 1.0);
    final shadeOpacity = (opacity - 0.10).clamp(0.0, 1.0);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: PlantPalette.forest.withValues(alpha: shadowOpacity),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: highlightOpacity),
              tint.withValues(alpha: opacity),
              tint.withValues(alpha: shadeOpacity),
            ],
          ),
          borderRadius: borderRadius,
          border: Border.all(
            color: Colors.white.withValues(alpha: borderOpacity),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.50),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      ),
    );
    final clippedSurface = ClipRRect(
      borderRadius: borderRadius,
      child: _enableBackdropBlur && blur > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blur.clamp(0, 8).toDouble(),
                sigmaY: blur.clamp(0, 8).toDouble(),
              ),
              child: surface,
            )
          : surface,
    );
    return RepaintBoundary(child: clippedSurface);
  }
}
