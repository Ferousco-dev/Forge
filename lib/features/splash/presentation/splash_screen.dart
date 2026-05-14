import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/branding/brand_wordmark.dart';
import 'widgets/splash_content.dart';
import 'widgets/splash_indicator.dart';

/// Brand splash. Calm warm-white surface that matches the in-app palette
/// (no separate aubergine brand surface) so the splash flows seamlessly
/// into the rest of the app — same `surface`, same teal hero color, same
/// muted text. The wordmark itself carries the brand.
///
/// Choreography (single [AnimationController], staggered Intervals):
///   0–22%   → bottom palette wash fades up (`easeOutSine`)
///   18–62%  → wordmark scale 0.94→1.0 + fade (`easeOutCubic`)
///   55–82%  → tagline fade (`easeOut`)
///
/// Accessibility:
/// - Respects [MediaQueryData.disableAnimations]: collapses to a 280 ms
///   cross-fade and stops looping animations entirely.
/// - All foreground colors clear WCAG AA against the warm surface.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.onReady,
    this.tagline = 'Strong work. Fair pay.',
  });

  /// Called once the entrance choreography has played out and the minimum
  /// dwell time has elapsed. The host decides what comes next.
  final VoidCallback? onReady;
  final String tagline;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;

  late final Animation<double> _washOpacity;
  late final Animation<double> _wordOpacity;
  late final Animation<double> _wordScale;
  late final Animation<double> _taglineOpacity;

  Timer? _readyTimer;
  bool _signaled = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: AppMotion.splashEntrance,
    );

    _washOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.00, 0.22, curve: AppMotion.gentle),
    );
    _wordOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.18, 0.62, curve: AppMotion.enter),
    );
    _wordScale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.18, 0.62, curve: AppMotion.enter),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 0.82, curve: Curves.easeOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _entrance.duration = AppMotion.medium;
      }
      _entrance.forward();
      _scheduleReadyCallback();
    });
  }

  void _scheduleReadyCallback() {
    final cb = widget.onReady;
    if (cb == null) return;
    _readyTimer = Timer(AppMotion.splashMinDwell, () {
      if (!mounted || _signaled) return;
      _signaled = true;
      cb();
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    // Wordmark scales with screen — clamped so it doesn't get tiny on small
    // phones or comically large on tablets.
    final wordmarkSize = (shortest * 0.13).clamp(40.0, 64.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light surface → dark status-bar glyphs.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: palette.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: palette.surface,
        body: Stack(
          children: <Widget>[
            // Subtle teal bottom wash — same atmospheric role the brand
            // glow played, but tinted to the in-app primary so the splash
            // visually belongs with the home screen.
            Positioned.fill(
              child: _PaletteWash(appearance: _washOpacity),
            ),

            // Hero composition.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // Heavier top spacer pushes content up to the optical
                    // sweet-spot (~38% from top).
                    const Spacer(flex: 8),

                    // Hero wordmark — deep teal on warm cream. Wrapped in
                    // Center to guarantee horizontal centering even if the
                    // ancestor flex resolves cross-axis differently.
                    Center(
                      // FadeTransition + ScaleTransition drive the
                      // opacity/scale on the layer directly — no per-
                      // frame Opacity widget rebuild, GPU-cheap.
                      child: FadeTransition(
                        opacity: _wordOpacity,
                        child: ScaleTransition(
                          scale: _wordScale,
                          child: BrandWordmark(
                            fontSize: wordmarkSize,
                            color: palette.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    AppSpacing.gapBase,

                    // Tagline — muted onSurfaceVariant.
                    FadeTransition(
                      opacity: _taglineOpacity,
                      child: Text(
                        widget.tagline,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          letterSpacing: 0.6,
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ),

                    const Spacer(flex: 11),

                    // Daily quote — single rotating Naija line, bottom
                    // of the screen, fades in with the tagline. Stable
                    // per UTC day so repeat cold starts on the same day
                    // show the same quote.
                    FadeTransition(
                      opacity: _taglineOpacity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Text(
                          quoteForToday(),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.primary.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                    AppSpacing.gapLg,

                    // Loading indicator in the bottom safe-area gutter.
                    SplashIndicator(
                      color: palette.onSurfaceVariant,
                    ),
                    AppSpacing.gapLg,
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

// ---------------------------------------------------------------------
// Atmospheric bottom wash — the in-palette analogue of the old aubergine
// brand glow. Soft teal radial bloom anchored just below the bottom edge
// so only the gentle fall-off is visible. Breathes very slowly to give
// the splash a sense of life without distracting from the wordmark.
// ---------------------------------------------------------------------

class _PaletteWash extends StatefulWidget {
  const _PaletteWash({this.appearance});

  /// Optional 0→1 appearance opacity controlled by the host's choreography.
  final Animation<double>? appearance;

  @override
  State<_PaletteWash> createState() => _PaletteWashState();
}

class _PaletteWashState extends State<_PaletteWash>
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
    final tint = context.palette.primary;
    // RepaintBoundary so the 6 s breathing wash owns its own layer
    // and doesn't invalidate the wordmark / overlay text above it on
    // every animation tick. Removes the subtle splash judder on
    // mid-range Android.
    final layer = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _breath,
        builder: (BuildContext context, _) {
          return CustomPaint(
            painter: _WashPainter(breathT: _breath.value, tint: tint),
            size: Size.infinite,
          );
        },
      ),
    );
    final appearance = widget.appearance;
    if (appearance == null) return IgnorePointer(child: layer);
    return IgnorePointer(
      child: FadeTransition(opacity: appearance, child: layer),
    );
  }
}

class _WashPainter extends CustomPainter {
  _WashPainter({required this.breathT, required this.tint});

  final double breathT;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    // Tall radial gradient anchored just below the bottom edge so the
    // brightest point is hidden — only the soft fall-off is visible.
    // Alphas are deliberately gentler than the on-brand version: a warm
    // light surface needs less wash to feel atmospheric than a deep
    // aubergine one.
    final breathScale = 1.0 + 0.05 * breathT;
    final center = Offset(size.width * 0.5, size.height * 1.05);
    final radius = size.shortestSide * 1.05 * breathScale;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          tint.withValues(alpha: 0.10),
          tint.withValues(alpha: 0.04),
          tint.withValues(alpha: 0.0),
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _WashPainter old) =>
      old.breathT != breathT || old.tint != tint;
}
