import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// One-shot confetti overlay used on success screens.
///
/// Hand-painted (no package) — 24 small rectangles fall from the top
/// edge with random horizontal positions, individual rotation, and
/// staggered start times. The overall animation runs for 1800ms then
/// goes inert; the [IgnorePointer] wrapper means it never blocks taps.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({
    super.key,
    this.duration = const Duration(milliseconds: 1800),
    this.pieceCount = 24,
  });

  final Duration duration;
  final int pieceCount;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _pieces = List<_Piece>.generate(widget.pieceCount, (int i) {
      return _Piece(
        startX: rng.nextDouble(),
        endX: rng.nextDouble(),
        delay: rng.nextDouble() * 0.30,
        rotations: 1 + rng.nextDouble() * 2.5,
        sizeFactor: 0.6 + rng.nextDouble() * 0.6,
        colorIndex: rng.nextInt(4),
      );
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = <Color>[
      palette.primary,
      palette.secondary,
      palette.success,
      palette.info,
    ];
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              t: _controller.value,
              pieces: _pieces,
              colors: colors,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.startX,
    required this.endX,
    required this.delay,
    required this.rotations,
    required this.sizeFactor,
    required this.colorIndex,
  });

  /// Horizontal start position 0..1 (fraction of width).
  final double startX;

  /// Horizontal end position 0..1.
  final double endX;

  /// Delay 0..1 — fraction of total duration before this piece starts.
  final double delay;

  /// Number of full rotations across its lifetime.
  final double rotations;

  /// Size multiplier 0.6..1.2 (base 8 × 4 dp).
  final double sizeFactor;

  final int colorIndex;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.t,
    required this.pieces,
    required this.colors,
  });

  final double t;
  final List<_Piece> pieces;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Piece piece in pieces) {
      final localT = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      final x = lerpDouble(piece.startX, piece.endX, localT)! * size.width;
      // Easing for the fall — accelerate slightly past midpoint.
      final eased = Curves.easeIn.transform(localT);
      final y = -20 + eased * (size.height + 80);

      final fadeOut = localT > 0.85
          ? 1 - (localT - 0.85) / 0.15
          : 1.0;

      final width = 8 * piece.sizeFactor;
      final height = 4 * piece.sizeFactor;
      final color = colors[piece.colorIndex].withValues(alpha: fadeOut);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.rotations * 2 * math.pi * localT);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: width, height: height),
          const Radius.circular(1.5),
        ),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
