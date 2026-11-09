import 'package:flutter/material.dart';

/// A deliberately static backdrop.
///
/// Playing and blurring a full-screen video continuously competes with input,
/// scrolling, camera preview, and image analysis in a browser. A still image
/// gives the same visual identity while keeping raster work out of every frame.
class PlantBackdrop extends StatelessWidget {
  const PlantBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const _FallbackArtwork(), const _AtmosphereOverlay()],
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Image.asset(
      'assets/landscape.jpg',
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      excludeFromSemantics: true,
    ),
  );
}

class _AtmosphereOverlay extends StatelessWidget {
  const _AtmosphereOverlay();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(5, 31, 23, 0.44),
            Color.fromRGBO(23, 67, 51, 0.24),
            Color.fromRGBO(237, 247, 240, 0.34),
          ],
          stops: [0, 0.47, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -120,
            child: _GlowOrb(
              size: 410,
              color: Color.fromRGBO(180, 233, 168, 0.23),
            ),
          ),
          Positioned(
            left: -160,
            bottom: -210,
            child: _GlowOrb(
              size: 460,
              color: Color.fromRGBO(103, 185, 155, 0.19),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}
