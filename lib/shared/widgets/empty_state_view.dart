import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Empty-state placeholder. Centered illustration + title + subtitle +
/// optional CTA.
///
/// Pass any widget for [illustration] — typically an [Icon] in the
/// neutral chip color, or a small custom-painted vignette. Default
/// illustration is a soft inbox icon to keep call sites concise.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.subtitle,
    this.illustration,
    this.action,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xl,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? illustration;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // SingleChildScrollView so this empty state survives being placed
    // in a vertically squeezed container (e.g. search "no results"
    // while the on-screen keyboard is up). When height is plentiful,
    // Center inside ensures the content sits visually centered.
    return SingleChildScrollView(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            illustration ??
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: palette.onSurfaceVariant.withValues(alpha: 0.7),
                ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
