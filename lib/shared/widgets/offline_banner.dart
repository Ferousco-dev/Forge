import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';
import '../../core/mock/mock_providers.dart';

/// Top banner shown when [isOfflineProvider] returns true.
///
/// Slides in from the top edge with a soft warning tint. Inert — the user
/// can't dismiss it (it disappears once connectivity returns).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    final palette = context.palette;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: !offline
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey<String>('offline-banner'),
              width: double.infinity,
              color: palette.warning.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.sm + 2,
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: palette.warning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'You\'re offline. Showing saved data.',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
