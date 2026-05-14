import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Placeholder body mounted under every route until the real screen
/// is implemented in its feature phase.
///
/// Renders the route name + optional ID as a centered card with a
/// "Coming in Phase X" tag. Lets the team navigate the whole app
/// end-to-end during foundation work without any visual rough edges.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.phase,
    this.routeId,
  });

  final String title;
  final String phase;
  final String? routeId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: palette.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.architecture_rounded,
                  size: 44,
                  color: palette.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Implementation lands in $phase.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              if (routeId != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    routeId!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
