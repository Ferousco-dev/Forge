import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Decorative atmosphere layer used on brand surfaces.
///
/// A single soft warm glow rising from the bottom edge — calm, atmospheric,
/// no distraction. Earlier iterations layered a star constellation over
/// the glow; that read as cluttered against the wordmark, so the
/// background is now a single quiet element.
///
/// The glow breathes very slowly (1.00 ↔ 1.05 over 6 s). Halts under
/// [MediaQueryData.disableAnimations].
class BrandGlow extends StatefulWidget {
  const BrandGlow({
    super.key,
    this.appearance,
  });

  /// Optional 0→1 appearance opacity controlled by the host's choreography.
  /// If `null`, the glow is fully visible immediately.
  final Animation<double>? appearance;

  @override
  State<BrandGlow> createState() => _BrandGlowState();
}

class _BrandGlowState extends State<BrandGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6000),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (!reduce) {
        _breath.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = widget.appearance;
    final layer = AnimatedBuilder(
      animation: _breath,
      builder: (BuildContext context, _) {
        return CustomPaint(
          painter: _GlowPainter(breathT: _breath.value),
          size: Size.infinite,
        );
      },
    );
    if (appearance == null) return IgnorePointer(child: layer);
    return IgnorePointer(
      child: FadeTransition(opacity: appearance, child: layer),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.breathT});

  final double breathT;

  @override
  void paint(Canvas canvas, Size size) {
    // Tall radial gradient anchored just below the bottom edge so the
    // brightest point is hidden — only the soft fall-off is visible.
    final breathScale = 1.0 + 0.05 * breathT;
    final glowCenter = Offset(size.width * 0.5, size.height * 1.05);
    final glowRadius = size.shortestSide * 1.05 * breathScale;
    final glowRect = Rect.fromCircle(center: glowCenter, radius: glowRadius);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          BrandPalette.glow.withValues(alpha: 0.18),
          BrandPalette.glow.withValues(alpha: 0.06),
          BrandPalette.glow.withValues(alpha: 0.0),
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(glowRect);
    canvas.drawRect(Offset.zero & size, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => old.breathT != breathT;
}
