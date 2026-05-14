import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';

/// Radial credit-score gauge.
///
/// Renders a 240° arc (the conventional "speedometer" sweep) with the
/// score number and a tier label inside. Color tinting follows tier:
/// red → amber → blue → green as the score climbs from 0 to 100.
class CreditScoreGauge extends StatefulWidget {
  const CreditScoreGauge({
    super.key,
    required this.score,
    this.size = 220,
  })  : assert(score >= 0 && score <= 100, 'score must be 0..100');

  /// Score 0..100.
  final int score;
  final double size;

  @override
  State<CreditScoreGauge> createState() => _CreditScoreGaugeState();
}

class _CreditScoreGaugeState extends State<CreditScoreGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late Animation<double> _animatedScore = Tween<double>(
    begin: 0,
    end: widget.score.toDouble(),
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant CreditScoreGauge old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _animatedScore = Tween<double>(
        begin: _animatedScore.value,
        end: widget.score.toDouble(),
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _animatedScore,
        builder: (BuildContext context, _) {
          final value =
              reduceMotion ? widget.score.toDouble() : _animatedScore.value;
          final tier = _tierFor(value, palette);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: Size.square(widget.size),
                painter: _GaugePainter(
                  value: value / 100,
                  trackColor: palette.surfaceContainerHigh,
                  fillColor: tier.color,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    value.round().toString(),
                    style: AppTextStyles.displayMedium.copyWith(
                      color: palette.onSurface,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Credit score',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tier.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tier.label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: tier.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  ({String label, Color color}) _tierFor(double v, dynamic palette) {
    if (v < 40) return (label: 'Building', color: palette.error as Color);
    if (v < 60) return (label: 'Fair', color: palette.warning as Color);
    if (v < 80) return (label: 'Good', color: palette.info as Color);
    return (label: 'Excellent', color: palette.success as Color);
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.trackColor,
    required this.fillColor,
  });

  /// 0..1.
  final double value;
  final Color trackColor;
  final Color fillColor;

  // Total arc sweep — 240° centered at the bottom of the circle.
  static const double _startAngle = math.pi * 0.75; // 135°
  static const double _sweepAngle = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 14.0;

    // Track.
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (value <= 0) return;
    // Filled sweep.
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.fillColor != fillColor;
}
