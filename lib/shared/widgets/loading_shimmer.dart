import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_theme.dart';

/// Lightweight shimmer used in skeleton loaders.
///
/// Hand-rolled (no package dependency) — a single `AnimatedBuilder` over
/// a `LinearGradient` that sweeps left→right. ~30 lines, identical look
/// to the `shimmer` package, zero external risk.
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  /// Convenience for rectangular block placeholders.
  const LoadingShimmer.box({
    super.key,
    required this.width,
    required this.height,
    double radius = AppRadius.md,
  }) : borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md));

  /// Convenience for round (avatar) placeholders.
  const LoadingShimmer.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = const BorderRadius.all(Radius.circular(AppRadius.full));

  /// Convenience for short single-line text placeholders.
  const LoadingShimmer.line({
    super.key,
    required this.width,
    this.height = 12,
  }) : borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sm));

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final base = palette.surfaceContainerHigh;
    final highlight = palette.outlineVariant;
    final radius = widget.borderRadius ??
        const BorderRadius.all(Radius.circular(AppRadius.md));

    if (reduceMotion) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final t = _controller.value;
        return ClipRRect(
          borderRadius: radius,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(color: base),
            child: ShaderMask(
              shaderCallback: (Rect bounds) => LinearGradient(
                begin: Alignment(-1.0 + 2 * t, 0),
                end: Alignment(1.0 + 2 * t, 0),
                colors: <Color>[base, highlight, base],
                stops: const <double>[0.35, 0.5, 0.65],
              ).createShader(bounds),
              blendMode: BlendMode.srcATop,
              child: Container(color: highlight),
            ),
          ),
        );
      },
    );
  }
}
