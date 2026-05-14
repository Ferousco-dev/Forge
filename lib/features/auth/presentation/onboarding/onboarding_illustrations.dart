import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Three custom-painted illustrations for the onboarding carousel.
///
/// Cohesive style across all three:
/// - Soft rounded-square or circular containers in `primaryContainer`,
///   so the illustrations feel like one family.
/// - Primary teal as the dominant fill, amber as the highlight accent.
/// - 4dp stroke weight everywhere — same line language.
/// - Slight diagonal motion baked in (pin tilt, chart slope, coin float)
///   to avoid the static-clip-art look.
///
/// Each is a self-contained `StatelessWidget`; size driven by the parent
/// (default 180dp). No external assets, no network, no bundle weight.

const double _defaultIllustrationSize = 180;

class IllustrationFindWorkNearby extends StatelessWidget {
  const IllustrationFindWorkNearby({super.key, this.size = _defaultIllustrationSize});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Map with location pins',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _MapPinsPainter(
              container: palette.primaryContainer,
              primary: palette.primary,
              secondary: palette.secondary,
              outline: palette.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class IllustrationGetPaidInstantly extends StatelessWidget {
  const IllustrationGetPaidInstantly({super.key, this.size = _defaultIllustrationSize});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Phone with money',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _PhoneWithMoneyPainter(
              container: palette.primaryContainer,
              primary: palette.primary,
              secondary: palette.secondary,
              surface: palette.surfaceContainer,
              outline: palette.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class IllustrationBuildYourCredit extends StatelessWidget {
  const IllustrationBuildYourCredit({super.key, this.size = _defaultIllustrationSize});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Growth chart',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _GrowthChartPainter(
              container: palette.primaryContainer,
              primary: palette.primary,
              secondary: palette.secondary,
              outline: palette.outline,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------

class _MapPinsPainter extends CustomPainter {
  _MapPinsPainter({
    required this.container,
    required this.primary,
    required this.secondary,
    required this.outline,
  });

  final Color container;
  final Color primary;
  final Color secondary;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    // Container — rounded square backdrop.
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.20),
    );
    canvas.drawRRect(bg, Paint()..color = container);

    // Map grid — 3 horizontal + 3 vertical hairlines, slightly curved
    // to suggest distance.
    final gridPaint = Paint()
      ..color = outline.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012;
    for (int i = 1; i < 4; i++) {
      final y = s * (0.20 + i * 0.18);
      final path = Path()..moveTo(s * 0.10, y);
      path.quadraticBezierTo(s * 0.5, y - s * 0.02, s * 0.90, y);
      canvas.drawPath(path, gridPaint);
    }
    for (int i = 1; i < 4; i++) {
      final x = s * (0.18 + i * 0.18);
      final path = Path()..moveTo(x, s * 0.18);
      path.quadraticBezierTo(x + s * 0.02, s * 0.5, x, s * 0.86);
      canvas.drawPath(path, gridPaint);
    }

    // Three pins at increasing depth — primary (large), primary (medium),
    // secondary (small accent).
    _drawPin(canvas, Offset(s * 0.32, s * 0.45), s * 0.22, primary);
    _drawPin(canvas, Offset(s * 0.62, s * 0.55), s * 0.18, primary);
    _drawPin(canvas, Offset(s * 0.50, s * 0.32), s * 0.16, secondary);
  }

  void _drawPin(Canvas canvas, Offset tip, double height, Color color) {
    // Soft drop shadow under the pin's tip.
    canvas.drawCircle(
      tip.translate(0, height * 0.10),
      height * 0.16,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, height * 0.10),
    );

    // Teardrop shape: circular head + triangular tail.
    final headRadius = height * 0.32;
    final headCenter = Offset(tip.dx, tip.dy - height * 0.55);
    final body = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx - headRadius * 1.2,
        tip.dy - height * 0.40,
        tip.dx - headRadius,
        headCenter.dy,
      )
      ..arcToPoint(
        Offset(tip.dx + headRadius, headCenter.dy),
        radius: Radius.circular(headRadius),
        clockwise: true,
      )
      ..quadraticBezierTo(
        tip.dx + headRadius * 1.2,
        tip.dy - height * 0.40,
        tip.dx,
        tip.dy,
      )
      ..close();
    canvas.drawPath(body, Paint()..color = color);

    // Inner dot (cream highlight).
    canvas.drawCircle(
      headCenter,
      headRadius * 0.42,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPinsPainter old) =>
      old.container != container || old.primary != primary;
}

class _PhoneWithMoneyPainter extends CustomPainter {
  _PhoneWithMoneyPainter({
    required this.container,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.outline,
  });

  final Color container;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    // Container backdrop.
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.20),
    );
    canvas.drawRRect(bg, Paint()..color = container);

    // Phone — vertical rounded rect, primary color, slightly tilted.
    canvas.save();
    canvas.translate(s * 0.50, s * 0.52);
    canvas.rotate(-0.06);
    canvas.translate(-s * 0.50, -s * 0.52);

    final phoneRect = Rect.fromCenter(
      center: Offset(s * 0.50, s * 0.52),
      width: s * 0.40,
      height: s * 0.56,
    );
    final phone = RRect.fromRectAndRadius(
      phoneRect,
      Radius.circular(s * 0.06),
    );

    // Soft drop shadow.
    canvas.drawRRect(
      phone.shift(Offset(0, s * 0.025)),
      Paint()
        ..color = primary.withValues(alpha: 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04),
    );
    canvas.drawRRect(phone, Paint()..color = primary);

    // Phone screen.
    final screenRect = Rect.fromCenter(
      center: phoneRect.center.translate(0, -s * 0.02),
      width: phoneRect.width * 0.82,
      height: phoneRect.height * 0.78,
    );
    final screen = RRect.fromRectAndRadius(screenRect, Radius.circular(s * 0.03));
    canvas.drawRRect(screen, Paint()..color = surface);

    // Naira sign in the screen — bold, secondary color.
    final nairaCenter = screenRect.center;
    final nairaPaint = Paint()
      ..color = secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.030
      ..strokeCap = StrokeCap.round;
    final nh = s * 0.16;
    final nw = s * 0.10;
    // Left vertical
    canvas.drawLine(
      Offset(nairaCenter.dx - nw / 2, nairaCenter.dy - nh / 2),
      Offset(nairaCenter.dx - nw / 2, nairaCenter.dy + nh / 2),
      nairaPaint,
    );
    // Right vertical
    canvas.drawLine(
      Offset(nairaCenter.dx + nw / 2, nairaCenter.dy - nh / 2),
      Offset(nairaCenter.dx + nw / 2, nairaCenter.dy + nh / 2),
      nairaPaint,
    );
    // Diagonal
    canvas.drawLine(
      Offset(nairaCenter.dx - nw / 2, nairaCenter.dy - nh / 2),
      Offset(nairaCenter.dx + nw / 2, nairaCenter.dy + nh / 2),
      nairaPaint,
    );
    // Two horizontal bars
    canvas.drawLine(
      Offset(nairaCenter.dx - nw / 2, nairaCenter.dy - nh * 0.18),
      Offset(nairaCenter.dx + nw / 2, nairaCenter.dy - nh * 0.18),
      nairaPaint,
    );
    canvas.drawLine(
      Offset(nairaCenter.dx - nw / 2, nairaCenter.dy + nh * 0.18),
      Offset(nairaCenter.dx + nw / 2, nairaCenter.dy + nh * 0.18),
      nairaPaint,
    );

    canvas.restore();

    // Floating coins — three secondary-color circles to the upper-right.
    _drawCoin(canvas, Offset(s * 0.78, s * 0.30), s * 0.060, secondary);
    _drawCoin(canvas, Offset(s * 0.85, s * 0.46), s * 0.050, secondary);
    _drawCoin(canvas, Offset(s * 0.18, s * 0.30), s * 0.045, secondary);
  }

  void _drawCoin(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center.translate(0, radius * 0.30),
      radius * 0.95,
      Paint()
        ..color = color.withValues(alpha: 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.40),
    );
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius * 0.55,
      Paint()
        ..color = color.withValues(alpha: 0.0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.10
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _PhoneWithMoneyPainter old) =>
      old.container != container || old.primary != primary;
}

class _GrowthChartPainter extends CustomPainter {
  _GrowthChartPainter({
    required this.container,
    required this.primary,
    required this.secondary,
    required this.outline,
  });

  final Color container;
  final Color primary;
  final Color secondary;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    // Container backdrop.
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.20),
    );
    canvas.drawRRect(bg, Paint()..color = container);

    // Bars — 4 ascending heights, primary fill.
    const int barCount = 4;
    final barWidth = s * 0.10;
    final barGap = s * 0.04;
    final groupWidth = barCount * barWidth + (barCount - 1) * barGap;
    final groupLeft = (s - groupWidth) / 2 - s * 0.06;
    final baseline = s * 0.78;

    for (int i = 0; i < barCount; i++) {
      final h = s * (0.18 + i * 0.10);
      final x = groupLeft + i * (barWidth + barGap);
      final rect = Rect.fromLTWH(x, baseline - h, barWidth, h);
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(barWidth * 0.4),
        topRight: Radius.circular(barWidth * 0.4),
      );
      // Drop shadow on each bar.
      canvas.drawRRect(
        rrect.shift(Offset(0, s * 0.012)),
        Paint()
          ..color = primary.withValues(alpha: 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.020),
      );
      canvas.drawRRect(rrect, Paint()..color = primary);
    }

    // Trend line — diagonal from lower-left to upper-right with arrow.
    final linePaint = Paint()
      ..color = secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.030
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final start = Offset(s * 0.18, s * 0.62);
    final end = Offset(s * 0.82, s * 0.22);
    canvas.drawLine(start, end, linePaint);

    // Arrowhead.
    final arrowAngle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const arrowSize = 0.09;
    final arrowLen = s * arrowSize;
    final tip = end;
    final left = Offset(
      tip.dx - arrowLen * math.cos(arrowAngle - math.pi / 6),
      tip.dy - arrowLen * math.sin(arrowAngle - math.pi / 6),
    );
    final right = Offset(
      tip.dx - arrowLen * math.cos(arrowAngle + math.pi / 6),
      tip.dy - arrowLen * math.sin(arrowAngle + math.pi / 6),
    );
    canvas.drawLine(tip, left, linePaint);
    canvas.drawLine(tip, right, linePaint);

    // Endpoint dot — large primary dot at start of trend.
    canvas.drawCircle(start, s * 0.025, Paint()..color = secondary);
  }

  @override
  bool shouldRepaint(covariant _GrowthChartPainter old) =>
      old.container != container || old.primary != primary;
}
