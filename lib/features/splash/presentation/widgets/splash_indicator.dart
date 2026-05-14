import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Three-dot pulse indicator anchored at the bottom safe-area.
///
/// Only fades in if the splash exceeds [appearAfter] — for fast cold starts
/// it never appears at all, which is the right behavior. We don't want to
/// flash a loading affordance for a 600 ms boot.
class SplashIndicator extends StatefulWidget {
  const SplashIndicator({
    super.key,
    this.appearAfter = const Duration(milliseconds: 1400),
    this.dotCount = 3,
    this.dotSize = 6.0,
    this.spacing = 10.0,
    this.color,
  });

  final Duration appearAfter;
  final int dotCount;
  final double dotSize;
  final double spacing;

  /// Override dot color. Defaults to the active palette's subtle text tone.
  final Color? color;

  @override
  State<SplashIndicator> createState() => _SplashIndicatorState();
}

class _SplashIndicatorState extends State<SplashIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _appearance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();
  Timer? _appearTimer;

  @override
  void initState() {
    super.initState();
    _appearTimer = Timer(widget.appearAfter, () {
      if (mounted) _appearance.forward();
    });
  }

  @override
  void dispose() {
    _appearTimer?.cancel();
    _appearance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final dotColor = widget.color ?? palette.onSurfaceVariant;

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _appearance,
        curve: Curves.easeOut,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(widget.dotCount, (int i) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, _) {
                if (reduceMotion) {
                  return _Dot(
                    size: widget.dotSize,
                    color: dotColor,
                    opacity: 0.6,
                  );
                }
                final phase = (_pulse.value + i / widget.dotCount) % 1.0;
                final t = (phase < 0.5)
                    ? phase * 2
                    : (1 - phase) * 2;
                final eased = Curves.easeInOut.transform(t);
                final opacity = 0.25 + 0.55 * eased;
                final scale = 0.85 + 0.25 * eased;
                return Transform.scale(
                  scale: scale,
                  child: _Dot(
                    size: widget.dotSize,
                    color: dotColor,
                    opacity: opacity,
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
