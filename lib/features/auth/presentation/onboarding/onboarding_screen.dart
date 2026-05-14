import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_paths.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_text_button.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../state/onboarding_state.dart';
import 'onboarding_illustrations.dart';

/// Three-slide onboarding carousel.
///
/// Layout per the brief:
/// - Top-right: "Skip" link (hidden on the final slide).
/// - Center: hero illustration + title + subtitle.
/// - Bottom: page indicator dots, then primary CTA ("Next" → "Get
///   Started" on the final slide).
///
/// Behavior:
/// - Swipeable horizontally.
/// - Tapping "Next" advances by one page with a 320 ms eased animation.
/// - Tapping "Get Started" or "Skip" sets [hasSeenOnboardingProvider] =
///   true and routes to `/auth/login`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const List<_Slide> _slides = <_Slide>[
    _Slide(
      title: 'Find work nearby',
      subtitle: 'Jobs in your area, ranked by distance and pay.',
    ),
    _Slide(
      title: 'Get paid instantly',
      subtitle: 'Verified work means instant payment to your wallet.',
    ),
    _Slide(
      title: 'Build your credit',
      subtitle: 'Every job builds your record. Unlock loans as you work.',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    await ref.read(hasSeenOnboardingProvider.notifier).markSeen();
    if (!mounted) return;
    context.go(RoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar — Skip on the right (only when not on final slide).
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isLast
                          ? const SizedBox(
                              key: ValueKey<String>('skip-hidden'),
                              width: 0,
                              height: 0,
                            )
                          : AppTextButton(
                              key: const ValueKey<String>('skip-shown'),
                              label: 'Skip',
                              onPressed: () => _finish(),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // Pager.
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (int i) => setState(() => _index = i),
                itemCount: _slides.length,
                itemBuilder: (BuildContext context, int i) {
                  return _SlideView(
                    slide: _slides[i],
                    illustration: switch (i) {
                      0 => const IllustrationFindWorkNearby(),
                      1 => const IllustrationGetPaidInstantly(),
                      _ => const IllustrationBuildYourCredit(),
                    },
                  );
                },
              ),
            ),

            // Page indicator + CTA.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: <Widget>[
                  _PageIndicator(
                    count: _slides.length,
                    active: _index,
                    activeColor: palette.primary,
                    inactiveColor: palette.outline,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: _isLast ? 'Get started' : 'Next',
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.illustration});

  final _Slide slide;
  final Widget illustration;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          illustration,
          const SizedBox(height: AppSpacing.xl),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              slide.subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int count;
  final int active;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 8,
            width: i == active ? 24 : 8,
            decoration: BoxDecoration(
              color: i == active ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        ],
      ],
    );
  }
}
