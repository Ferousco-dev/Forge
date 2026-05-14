import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Inter type system. Material 3 type scale, plus three currency variants
/// for prominent earnings/balance displays.
///
/// Font delivery: [GoogleFonts.inter] fetches Inter at runtime and caches
/// it. Production migration to bundled TTFs is a single-line change in
/// `main()` (`GoogleFonts.config.allowRuntimeFetching = false`); call
/// sites here remain identical.
class AppTextStyles {
  const AppTextStyles._();

  // ---------------------------------------------------------------------
  // Display
  // ---------------------------------------------------------------------
  static TextStyle get displayLarge => GoogleFonts.inter(
        fontSize: 57,
        height: 1.12,
        letterSpacing: -1.0,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get displayMedium => GoogleFonts.inter(
        fontSize: 45,
        height: 1.16,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get displaySmall => GoogleFonts.inter(
        fontSize: 36,
        height: 1.22,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w700,
      );

  // ---------------------------------------------------------------------
  // Headline
  // ---------------------------------------------------------------------
  static TextStyle get headlineLarge => GoogleFonts.inter(
        fontSize: 32,
        height: 1.25,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get headlineMedium => GoogleFonts.inter(
        fontSize: 28,
        height: 1.28,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get headlineSmall => GoogleFonts.inter(
        fontSize: 24,
        height: 1.32,
        letterSpacing: -0.1,
        fontWeight: FontWeight.w600,
      );

  // ---------------------------------------------------------------------
  // Title
  // ---------------------------------------------------------------------
  static TextStyle get titleLarge => GoogleFonts.inter(
        fontSize: 20,
        height: 1.32,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get titleMedium => GoogleFonts.inter(
        fontSize: 16,
        height: 1.40,
        letterSpacing: 0.05,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get titleSmall => GoogleFonts.inter(
        fontSize: 14,
        height: 1.42,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
      );

  // ---------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------
  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 17,
        height: 1.48,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 15,
        height: 1.50,
        letterSpacing: 0.05,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 13,
        height: 1.46,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w400,
      );

  // ---------------------------------------------------------------------
  // Label
  // ---------------------------------------------------------------------
  static TextStyle get labelLarge => GoogleFonts.inter(
        fontSize: 14,
        height: 1.32,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get labelMedium => GoogleFonts.inter(
        fontSize: 12,
        height: 1.32,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 11,
        height: 1.32,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w600,
      );

  // ---------------------------------------------------------------------
  // Currency — three sizes, optical-tabular figures, tighter tracking.
  // Used wherever a Naira amount is the focus of the visual.
  // ---------------------------------------------------------------------
  static TextStyle get currencyLarge => GoogleFonts.inter(
        fontSize: 44,
        height: 1.05,
        letterSpacing: -1.2,
        fontWeight: FontWeight.w700,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  static TextStyle get currencyMedium => GoogleFonts.inter(
        fontSize: 28,
        height: 1.10,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w700,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  static TextStyle get currencySmall => GoogleFonts.inter(
        fontSize: 18,
        height: 1.20,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w700,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  /// Builds a Material 3 [TextTheme] with all the slots populated. Color
  /// is applied at the slot level by [AppTheme] from the active palette.
  static TextTheme buildTextTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      displayLarge: displayLarge.copyWith(color: onSurface),
      displayMedium: displayMedium.copyWith(color: onSurface),
      displaySmall: displaySmall.copyWith(color: onSurface),
      headlineLarge: headlineLarge.copyWith(color: onSurface),
      headlineMedium: headlineMedium.copyWith(color: onSurface),
      headlineSmall: headlineSmall.copyWith(color: onSurface),
      titleLarge: titleLarge.copyWith(color: onSurface),
      titleMedium: titleMedium.copyWith(color: onSurface),
      titleSmall: titleSmall.copyWith(color: onSurface),
      bodyLarge: bodyLarge.copyWith(color: onSurface),
      bodyMedium: bodyMedium.copyWith(color: onSurface),
      bodySmall: bodySmall.copyWith(color: onSurfaceVariant),
      labelLarge: labelLarge.copyWith(color: onSurface),
      labelMedium: labelMedium.copyWith(color: onSurfaceVariant),
      labelSmall: labelSmall.copyWith(color: onSurfaceVariant),
    );
  }
}
