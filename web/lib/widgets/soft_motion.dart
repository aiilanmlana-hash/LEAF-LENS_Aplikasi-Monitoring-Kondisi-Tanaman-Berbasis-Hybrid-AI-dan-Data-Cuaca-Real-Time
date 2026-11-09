import 'dart:async';

import 'package:flutter/material.dart';

class SoftEntrance extends StatefulWidget {
  const SoftEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 620),
    this.offset = 18,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<SoftEntrance> createState() => _SoftEntranceState();
}

class _SoftEntranceState extends State<SoftEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reducedMotion == reducedMotion) return;
    _reducedMotion = reducedMotion;
    _delayTimer?.cancel();
    if (reducedMotion) {
      _controller.value = 1;
      return;
    }
    _controller.value = 0;
    _delayTimer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(covariant SoftEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reducedMotion == true) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = Curves.easeOutQuart.transform(_controller.value);
        return Opacity(
          opacity: progress,
          child: Transform.scale(
            scale: 0.985 + (0.015 * progress),
            alignment: Alignment.topCenter,
            child: Transform.translate(
              offset: Offset(0, widget.offset * (1 - progress)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class HoverLift extends StatefulWidget {
  const HoverLift({required this.child, this.lift = 3, super.key});

  final Widget child;
  final double lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class PressScale extends StatefulWidget {
  const PressScale({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (!widget.enabled ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
        _pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.98 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A small, low-key status pulse used for live system indicators.
class BreathingDot extends StatefulWidget {
  const BreathingDot({this.color = const Color(0xFF95B25A), super.key});

  final Color color;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return _dot(1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => _dot(0.68 + (_controller.value * 0.32)),
    );
  }

  Widget _dot(double opacity) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: widget.color.withValues(alpha: opacity),
      boxShadow: [
        BoxShadow(
          color: widget.color.withValues(alpha: opacity * 0.5),
          blurRadius: 8,
          spreadRadius: 1,
        ),
      ],
    ),
  );
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final lift = _hovered && !reduceMotion ? widget.lift : 0.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 230),
        curve: Curves.easeOutQuart,
        transform: Matrix4.translationValues(0, -lift, 0),
        transformAlignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
