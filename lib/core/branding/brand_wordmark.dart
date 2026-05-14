import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Wordmark for the Forge brand.
///
/// Plain centered text — the previous "noname" version used a Stack with a
/// positioned accent dot, which subtly biased the visual mass to the right
/// and made the splash composition look off-centered. Restraint reads
/// more premium anyway and keeps the wordmark legible at small sizes
/// (e.g. on a paper invoice header or a Squad transaction memo).
///
/// The wordmark uses [GoogleFonts.inter] directly rather than the project
/// `AppTextStyles` slots — wordmark sizing is screen-driven (clamped to
/// the splash's hero scale) so it doesn't fit any Material 3 type slot.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.fontSize = 28,
    this.color,
    this.fontWeight,
  });

  static const String _text = 'Forge';

  final double fontSize;
  final Color? color;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = color ?? scheme.onSurface;

    return Semantics(
      header: true,
      label: _text,
      child: Text(
        _text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: fontSize,
          height: 1.0,
          letterSpacing: -0.4,
          fontWeight: fontWeight ?? FontWeight.w600,
          color: resolved,
        ),
      ),
    );
  }
}
