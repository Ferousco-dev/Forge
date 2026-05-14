import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Hero illustrations for the permission screens.
///
/// Both share the same family language as the onboarding illustrations:
/// a tinted container backdrop + a richer-than-icon glyph. Built with
/// composable widgets (no `CustomPainter`) so they stay readable and
/// the icon size + ripple density can be tweaked from one place.

class IllustrationLocationPin extends StatelessWidget {
  const IllustrationLocationPin({super.key, this.size = 180});
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Location permission',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Outer ripple — faintest.
            _Ring(
              size: size,
              color: palette.primary.withValues(alpha: 0.10),
            ),
            // Mid ripple.
            _Ring(
              size: size * 0.78,
              color: palette.primary.withValues(alpha: 0.16),
            ),
            // Inner solid container.
            Container(
              width: size * 0.56,
              height: size * 0.56,
              decoration: BoxDecoration(
                color: palette.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.location_on_rounded,
                size: size * 0.34,
                color: palette.primary,
              ),
            ),
            // Amber accent dot — top-right satellite, suggests "ping".
            Positioned(
              top: size * 0.18,
              right: size * 0.20,
              child: Container(
                width: size * 0.07,
                height: size * 0.07,
                decoration: BoxDecoration(
                  color: palette.secondary,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.secondary.withValues(alpha: 0.40),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IllustrationBell extends StatelessWidget {
  const IllustrationBell({super.key, this.size = 180});
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Notification permission',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            _Ring(
              size: size,
              color: palette.primary.withValues(alpha: 0.10),
            ),
            _Ring(
              size: size * 0.78,
              color: palette.primary.withValues(alpha: 0.16),
            ),
            Container(
              width: size * 0.56,
              height: size * 0.56,
              decoration: BoxDecoration(
                color: palette.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: -0.10,
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: size * 0.36,
                  color: palette.primary,
                ),
              ),
            ),
            // Notification badge — small amber dot at upper-right.
            Positioned(
              top: size * 0.20,
              right: size * 0.22,
              child: Container(
                width: size * 0.10,
                height: size * 0.10,
                decoration: BoxDecoration(
                  color: palette.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
