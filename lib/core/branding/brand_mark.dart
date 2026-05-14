import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// Visual treatment for the [BrandMark]. The on-brand variant is what
/// renders inside a full-bleed brand surface (splash, auth landing).
enum BrandMarkVariant {
  /// Auto-pick from the active theme palette — primary fill, contrast
  /// inner, primary-tinted shadow. Use on light/dark content surfaces.
  themed,

  /// Inverted treatment for use *on* the brand surface itself: cream fill,
  /// deep-purple inner accents, much softer shadow.
  onBrand,
}

/// The "noname" brand mark.
///
/// Drawn entirely with [CustomPainter] so it stays crisp at every density,
/// adapts to theme tokens automatically, and never carries an asset payload.
///
/// Composition (inside-out):
/// 1. Soft drop shadow — color depends on variant.
/// 2. Rounded square base, 26% radius (squircle-adjacent).
/// 3. Inner top-edge highlight (themed variant only — adds depth on light).
/// 4. Orbital arc — thin stroke, ~220° sweep with an open mouth top-right.
/// 5. Focal dot — small filled circle in the arc's open mouth.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 96,
    this.variant = BrandMarkVariant.themed,
    this.semanticLabel = 'Forge',
  });

  final double size;
  final BrandMarkVariant variant;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color accent;
    final Color shadow;
    final double shadowOpacity;
    final bool drawHighlight;

    switch (variant) {
      case BrandMarkVariant.themed:
        // Themed variant reads from the theme extension. This requires a
        // host that wired AppTheme — typically the whole app via ForgeApp.
        final palette = context.palette;
        final isLightTheme = palette.brightness == Brightness.light;
        fill = palette.primary;
        accent = palette.onPrimary;
        shadow = palette.shadow;
        shadowOpacity = isLightTheme ? 0.18 : 0.55;
        drawHighlight = isLightTheme;
      case BrandMarkVariant.onBrand:
        // On the deep purple brand surface, the mark inverts: cream fill,
        // deep-purple inner. Theme-independent so it can render on any host.
        fill = BrandPalette.foreground;
        accent = BrandPalette.background;
        shadow = const Color(0xFF000000);
        shadowOpacity = 0.22;
        drawHighlight = false;
    }

    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _BrandMarkPainter(
              fill: fill,
              accent: accent,
              shadow: shadow,
              shadowOpacity: shadowOpacity,
              drawHighlight: drawHighlight,
            ),
            isComplex: false,
            willChange: false,
          ),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({
    required this.fill,
    required this.accent,
    required this.shadow,
    required this.shadowOpacity,
    required this.drawHighlight,
  });

  final Color fill;
  final Color accent;
  final Color shadow;
  final double shadowOpacity;
  final bool drawHighlight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Rect.fromLTWH(0, 0, s, s);
    final radius = Radius.circular(s * 0.26);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // 1. Drop shadow.
    final shadowOffset = Offset(0, s * 0.10);
    final shadowBlur = s * 0.22;
    final shadowPath = Path()..addRRect(rrect.shift(shadowOffset));
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = shadow.withValues(alpha: shadowOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur),
    );

    // 2. Rounded square base.
    canvas.drawRRect(rrect, Paint()..color = fill);

    // 3. Inner top-edge highlight — themed/light variant only.
    if (drawHighlight) {
      final highlightRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.08, s * 0.06, s * 0.84, s * 0.02),
        topLeft: Radius.circular(s * 0.02),
        topRight: Radius.circular(s * 0.02),
      );
      canvas.drawRRect(
        highlightRect,
        Paint()..color = accent.withValues(alpha: 0.10),
      );
    }

    // 4 + 5: Orbital arc + focal dot.
    canvas.save();
    canvas.translate(s / 2, s / 2);

    final orbitRadius = s * 0.24;
    final orbitRect = Rect.fromCircle(center: Offset.zero, radius: orbitRadius);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.045
      ..color = accent.withValues(alpha: 0.92);
    const startAngle = -2.9;
    const sweepAngle = 3.85;
    canvas.drawArc(orbitRect, startAngle, sweepAngle, false, orbitPaint);

    final dotCenter = Offset(orbitRadius * 0.78, -orbitRadius * 0.78);
    canvas.drawCircle(dotCenter, s * 0.058, Paint()..color = accent);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) {
    return old.fill != fill ||
        old.accent != accent ||
        old.shadow != shadow ||
        old.shadowOpacity != shadowOpacity ||
        old.drawHighlight != drawHighlight;
  }
}
