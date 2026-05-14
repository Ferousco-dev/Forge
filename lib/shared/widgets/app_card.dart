import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';

/// Consistent elevated card container.
///
/// Renders a `surfaceContainer` background with an `outline` hairline,
/// 16dp padding by default, and an `xl` radius. Optional `onTap` makes
/// the whole card a tappable surface with proper focus ring.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.borderRadius = AppRadius.allXl,
    this.onTap,
    this.background,
    this.borderColor,
    this.elevation = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback? onTap;
  final Color? background;
  final Color? borderColor;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = background ?? palette.surfaceContainer;
    final border = borderColor ?? palette.outline;
    final borderRadiusValue =
        borderRadius is BorderRadius ? borderRadius as BorderRadius : null;

    final body = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        border: Border.all(color: border, width: 1),
        boxShadow: elevation == 0
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.04 * elevation),
                  blurRadius: 12 * elevation,
                  offset: Offset(0, 4 * elevation),
                ),
              ],
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) return RepaintBoundary(child: body);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadiusValue,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadiusValue,
        child: RepaintBoundary(child: body),
      ),
    );
  }
}
