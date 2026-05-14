import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/models.dart';

/// Abstract Lagos basemap.
///
/// Not a real map — and not pretending to be. The visual language is
/// closer to a *map illustration* than a topographic basemap: muted
/// surface wash, a soft river curve, three hairline arterials, four
/// faintly-tinted neighborhood labels, plus the active job pins on top.
///
/// Three flavors:
/// - [MapPlaceholder] — full-bleed, multiple pins, hero use on the
///   immersive jobs view.
/// - [MapPlaceholder.snippet] — short, single-pin variant used in
///   detail screens and inline previews.
/// - [MapPlaceholder.preview] — same as the full version, but with a
///   "you are here" centerpoint so the home preview reads as
///   "centered on me."
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({
    super.key,
    required this.jobs,
    this.focusedJobId,
    this.showCurrentLocation = false,
  })  : _snippetJob = null,
        isSnippet = false;

  const MapPlaceholder.snippet({
    super.key,
    required Job job,
  })  : jobs = const <Job>[],
        focusedJobId = null,
        showCurrentLocation = false,
        isSnippet = true,
        _snippetJob = job;

  const MapPlaceholder.preview({
    super.key,
    required this.jobs,
    this.focusedJobId,
  })  : showCurrentLocation = true,
        _snippetJob = null,
        isSnippet = false;

  final List<Job> jobs;
  final String? focusedJobId;
  final bool isSnippet;
  final bool showCurrentLocation;
  final Job? _snippetJob;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final List<Job> renderedJobs =
        _snippetJob != null ? <Job>[_snippetJob] : jobs;

    return Semantics(
      label: 'Map preview',
      image: true,
      child: ClipRect(
        child: CustomPaint(
          painter: _MapPainter(
            jobs: renderedJobs,
            focusedJobId: focusedJobId ?? _snippetJob?.id,
            isSnippet: isSnippet,
            showCurrentLocation: showCurrentLocation,
            base: palette.surfaceContainerHigh,
            land: palette.surfaceContainer,
            land2: palette.surface,
            road: palette.outline,
            water: palette.info.withValues(alpha: 0.10),
            river: palette.info.withValues(alpha: 0.18),
            neighborhoodText: palette.onSurfaceVariant.withValues(alpha: 0.45),
            primary: palette.primary,
            primaryDeep: palette.onSurface,
            secondary: palette.secondary,
            currentLocation: palette.primary,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.jobs,
    required this.focusedJobId,
    required this.isSnippet,
    required this.showCurrentLocation,
    required this.base,
    required this.land,
    required this.land2,
    required this.road,
    required this.water,
    required this.river,
    required this.neighborhoodText,
    required this.primary,
    required this.primaryDeep,
    required this.secondary,
    required this.currentLocation,
  });

  final List<Job> jobs;
  final String? focusedJobId;
  final bool isSnippet;
  final bool showCurrentLocation;
  final Color base;
  final Color land;
  final Color land2;
  final Color road;
  final Color water;
  final Color river;
  final Color neighborhoodText;
  final Color primary;
  final Color primaryDeep;
  final Color secondary;
  final Color currentLocation;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Base wash.
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    // 2. Soft "land" plates — overlapping rounded rects, subtle tonal
    //    variation. Not blobs anymore; closer to neighborhood polygons.
    _drawPlate(canvas, Rect.fromLTWH(-w * 0.10, h * 0.05, w * 0.65, h * 0.40), land);
    _drawPlate(canvas, Rect.fromLTWH(w * 0.45, h * 0.20, w * 0.65, h * 0.50), land2);
    _drawPlate(canvas, Rect.fromLTWH(w * 0.05, h * 0.55, w * 0.55, h * 0.50), land);
    _drawPlate(canvas, Rect.fromLTWH(w * 0.55, h * 0.65, w * 0.55, h * 0.45), land2);

    // 3. Lagoon curve — a gentle arc cutting through the lower-right.
    //    Provides a single point of identity ("this is Lagos, not just a grid").
    final lagoonPaint = Paint()
      ..color = water
      ..style = PaintingStyle.fill;
    final lagoonPath = Path()
      ..moveTo(w * 1.05, h * 0.40)
      ..quadraticBezierTo(w * 0.55, h * 0.78, w * 1.05, h * 1.05)
      ..lineTo(w * 1.05, h * 1.05)
      ..close();
    canvas.drawPath(lagoonPath, lagoonPaint);
    final riverPaint = Paint()
      ..color = river
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(lagoonPath, riverPaint);

    // 4. Major arterials. Two diagonal hairlines + one minor cross
    //    street. Stroke widths follow road hierarchy.
    final arterialPaint = Paint()
      ..color = road
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final art1 = Path()
      ..moveTo(-w * 0.05, h * 0.55)
      ..quadraticBezierTo(w * 0.50, h * 0.40, w * 1.05, h * 0.70);
    canvas.drawPath(art1, arterialPaint);

    final art2 = Path()
      ..moveTo(w * 0.18, -h * 0.05)
      ..quadraticBezierTo(w * 0.50, h * 0.55, w * 0.85, h * 1.05);
    canvas.drawPath(art2, arterialPaint);

    // Minor street — thinner.
    final minorPaint = Paint()
      ..color = road.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.08, h * 0.20),
      Offset(w * 0.95, h * 0.32),
      minorPaint,
    );

    // 5. Neighborhood labels — only on the full-size map. Subtle,
    //    spaced widely, all-caps, very light tint.
    if (!isSnippet && size.shortestSide > 200) {
      _drawLabel(canvas, 'OWODE-ONIRIN', Offset(w * 0.18, h * 0.22));
      _drawLabel(canvas, 'COKER', Offset(w * 0.78, h * 0.34));
      _drawLabel(canvas, 'APAPA', Offset(w * 0.30, h * 0.78));
      _drawLabel(canvas, 'IPONRI', Offset(w * 0.72, h * 0.86));
    }

    // 6. Pins.
    if (jobs.isEmpty) {
      // No pins, but show "you are here" if requested so the preview
      // doesn't read as empty.
      if (showCurrentLocation) {
        _drawCurrentLocation(canvas, Offset(w * 0.5, h * 0.5));
      }
      return;
    }
    for (int i = 0; i < jobs.length; i++) {
      final j = jobs[i];
      final isFocused = j.id == focusedJobId;
      final seed = j.id.hashCode;
      final rng = math.Random(seed);
      // Within the central 80% of the canvas to keep pins visible.
      final x = w * (0.15 + rng.nextDouble() * 0.70);
      final y = h * (0.20 + rng.nextDouble() * 0.55);
      _drawPin(
        canvas,
        Offset(x, y),
        isFocused ? 38 : 28,
        isFocused ? secondary : primary,
        primaryDeep,
        focused: isFocused,
      );
    }

    // 7. "You are here" — drawn last so it sits above everything.
    if (showCurrentLocation) {
      _drawCurrentLocation(canvas, Offset(w * 0.5, h * 0.5));
    }
  }

  void _drawPlate(Canvas canvas, Rect rect, Color color) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawRRect(rrect, Paint()..color = color);
  }

  void _drawLabel(Canvas canvas, String text, Offset center) {
    final textStyle = AppTextStyles.labelSmall.copyWith(
      color: neighborhoodText,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w600,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  void _drawCurrentLocation(Canvas canvas, Offset center) {
    // Soft outer ring (8% opacity).
    canvas.drawCircle(
      center,
      24,
      Paint()..color = currentLocation.withValues(alpha: 0.08),
    );
    canvas.drawCircle(
      center,
      14,
      Paint()..color = currentLocation.withValues(alpha: 0.18),
    );
    // White stroke ring around the dot for contrast.
    canvas.drawCircle(
      center,
      8,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(center, 6, Paint()..color = currentLocation);
  }

  void _drawPin(
    Canvas canvas,
    Offset tip,
    double height,
    Color fill,
    Color outline, {
    bool focused = false,
  }) {
    // Soft halo beneath the focused pin — sits behind the shadow so
    // the pin reads as "selected" without losing the depth cue.
    if (focused) {
      canvas.drawCircle(
        tip.translate(0, -height * 0.55),
        height * 0.92,
        Paint()
          ..color = fill.withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, height * 0.30),
      );
    }

    // Drop shadow under the tip.
    canvas.drawCircle(
      tip.translate(0, height * 0.10),
      height * 0.20,
      Paint()
        ..color = outline.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, height * 0.12),
    );

    final headRadius = height * 0.42;
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
    canvas.drawPath(body, Paint()..color = fill);

    // Inner highlight — gives the pin head subtle dimensionality.
    canvas.drawCircle(
      headCenter,
      headRadius * 0.42,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.jobs.length != jobs.length ||
      old.focusedJobId != focusedJobId ||
      old.showCurrentLocation != showCurrentLocation ||
      old.primary != primary;
}
