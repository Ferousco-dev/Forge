import 'package:flutter/material.dart';

/// Hand-tuned palette tokens for content surfaces.
///
/// Two coexisting systems live in this file:
///
/// 1. [AppColors] — content-screen palette (teal primary, amber accent,
///    off-white surfaces). Used by every screen post-auth: jobs, earnings,
///    loans, profile. Material-3 calm, distinct from the sea of fintech
///    blues. Both light and dark variants.
///
/// 2. [BrandPalette] — always-on aubergine **brand surface** for the
///    splash and auth landing. Theme-independent. Survives because the
///    brand identity moment is constant — Spotify is always black, Venmo
///    is always blue, Forge is always aubergine on the way in.
///
/// Hybrid model agreed in the design-direction brief: branded entrance,
/// calm content interior. Don't merge these into one palette.
@immutable
class AppColors {
  const AppColors._({
    required this.brightness,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.error,
    required this.onError,
    required this.success,
    required this.warning,
    required this.info,
    required this.shadow,
  });

  final Brightness brightness;

  /// Deep teal — communicates trust + growth + groundedness. Distinct
  /// from fintech-blue saturation. WCAG AAA against [surface].
  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;

  /// Warm amber — earnings, success highlights, points of attention.
  /// Used sparingly; never as primary CTA.
  final Color secondary;
  final Color onSecondary;

  /// Background of the screen.
  final Color surface;

  /// Card / sheet / chip surfaces — subtly elevated above [surface].
  final Color surfaceContainer;
  final Color surfaceContainerHigh;

  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;

  final Color error;
  final Color onError;
  final Color success;
  final Color warning;
  final Color info;

  final Color shadow;

  static const AppColors light = AppColors._(
    brightness: Brightness.light,

    // Deeper teal — feels earned and authoritative rather than
    // medical/wellness. Slightly warmer on the chroma axis to bridge
    // toward the aubergine brand surface.
    primary: Color(0xFF0E695F),
    // Replaces the minty pastel `#CCFBF1`. This sage-green tint is
    // calmer and reads as fintech rather than spa.
    primaryContainer: Color(0xFFD9EBE7),
    onPrimary: Color(0xFFFFFFFF),

    // Amber stays — it's the only warmth in the system — but ticked
    // half a step warmer so it reads as money, not caution.
    secondary: Color(0xFFE89108),
    onSecondary: Color(0xFF1A1207),

    // Inverted from before. Page background is the *cleanest* surface
    // (warm near-white), cards are subtle off-white tints. Apple-bar:
    // cards recede into the page rhythm rather than popping out of it.
    surface: Color(0xFFFCFCFA),
    surfaceContainer: Color(0xFFF6F5F1),
    surfaceContainerHigh: Color(0xFFEFEEE9),

    // Warmer text — `#111418` reads as ink, not steel. Pairs better
    // with the warm surfaces; less clash with the aubergine brand.
    onSurface: Color(0xFF111418),
    onSurfaceVariant: Color(0xFF6B7280),

    // Hairlines warmed to match. The cool-gray `#E2E8F0` was the
    // single biggest "fragmented" cue in v1.
    outline: Color(0xFFE5E2DB),
    outlineVariant: Color(0xFFEFEDE7),

    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    success: Color(0xFF16A34A),
    warning: Color(0xFFE89108),
    info: Color(0xFF2563EB),

    // Shadow tracks onSurface so depth feels like ink.
    shadow: Color(0xFF111418),
  );

  static const AppColors dark = AppColors._(
    brightness: Brightness.dark,
    primary: Color(0xFF2DD4BF),
    primaryContainer: Color(0xFF134E4A),
    onPrimary: Color(0xFF042F2E),
    secondary: Color(0xFFFBBF24),
    onSecondary: Color(0xFF1A1207),
    surface: Color(0xFF0B1014),
    surfaceContainer: Color(0xFF12181D),
    surfaceContainerHigh: Color(0xFF1A222A),
    onSurface: Color(0xFFE5E7EB),
    onSurfaceVariant: Color(0xFF94A3B8),
    outline: Color(0xFF1F2933),
    outlineVariant: Color(0xFF2A343F),
    error: Color(0xFFEF4444),
    onError: Color(0xFFFFFFFF),
    success: Color(0xFF22C55E),
    warning: Color(0xFFFBBF24),
    info: Color(0xFF60A5FA),
    shadow: Color(0xFF000000),
  );

  ColorScheme toColorScheme() {
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onSurface,
      secondary: secondary,
      onSecondary: onSecondary,
      tertiary: info,
      onTertiary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceContainerHigh,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainer: surfaceContainer,
      surfaceContainerLow: surface,
      surfaceContainerLowest: surface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      error: error,
      onError: onError,
      shadow: shadow,
    );
  }
}

/// Theme extension so widgets can read the rich palette via
/// `Theme.of(context).extension<AppColorsTheme>()` without a singleton.
@immutable
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme(this.colors);

  final AppColors colors;

  @override
  AppColorsTheme copyWith({AppColors? colors}) =>
      AppColorsTheme(colors ?? this.colors);

  @override
  AppColorsTheme lerp(ThemeExtension<AppColorsTheme>? other, double t) {
    if (other is! AppColorsTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// Brand surface palette — applied only to the splash and auth landing.
/// Always-on aubergine regardless of OS theme. The brand entrance is a
/// constant; once the user crosses into [AppColors] content surfaces it
/// goes away.
@immutable
class BrandPalette {
  const BrandPalette._();

  /// Deep aubergine — canonical brand background.
  static const Color background = Color(0xFF3D2566);

  /// Slightly lighter step — for cards / chips on brand surface.
  static const Color surface = Color(0xFF4D3279);

  /// Even lighter — hover/pressed states or elevated containers on brand.
  static const Color surfaceHigh = Color(0xFF5A3F88);

  /// Warm cream — primary foreground on brand. Avoids pure white, which
  /// strobes against deep purple.
  static const Color foreground = Color(0xFFF5EDD8);

  /// Muted lilac — secondary text, captions on brand surfaces.
  static const Color muted = Color(0xFFB5A8C9);

  /// Hairline at 14% foreground.
  static Color hairline = foreground.withValues(alpha: 0.14);

  /// Glow — soft warm light used in brand-surface decorative passes.
  static const Color glow = Color(0xFFFFE9B8);

  /// Inverted brand-mark fill for on-brand contexts.
  static const Color markFill = foreground;

  /// Inverted brand-mark accent for on-brand contexts.
  static const Color markAccent = background;
}
