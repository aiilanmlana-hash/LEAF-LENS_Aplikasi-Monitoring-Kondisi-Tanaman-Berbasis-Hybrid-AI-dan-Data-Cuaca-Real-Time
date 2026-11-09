import 'package:flutter/material.dart';

class GardenArtwork extends StatelessWidget {
  const GardenArtwork({
    required this.asset,
    this.opacity = 0.24,
    this.fit = BoxFit.contain,
    super.key,
  });

  final String asset;
  final double opacity;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(
          opacity: opacity,
          child: Image.asset(asset, fit: fit, filterQuality: FilterQuality.low),
        ),
      ),
    );
  }
}
