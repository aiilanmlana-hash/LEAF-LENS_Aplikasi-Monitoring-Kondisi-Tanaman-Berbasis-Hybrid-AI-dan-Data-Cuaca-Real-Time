import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.padding,
    this.tint = Colors.white,
    this.opacity = 0.76,
    this.radius = 20,
    this.borderOpacity = 0.74,
    this.shadow = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color tint;
  final double opacity;
  final double radius;
  final double borderOpacity;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: borderOpacity),
        ),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: PlantColors.forest.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
