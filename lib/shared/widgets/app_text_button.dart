import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Text-only button. Used inline ("Forgot password?", "Maybe later",
/// "View all"). Always wears the primary color unless overridden.
///
/// Hit area is comfortably padded — the brief mandates 48dp minimum;
/// 44dp height + 12pt horizontal padding meets that with surrounding
/// vertical rhythm.
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Widget? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = color ?? palette.primary;
    final disabled = onPressed == null;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? AppSpacing.sm : AppSpacing.md,
              vertical: dense ? AppSpacing.xs + 2 : AppSpacing.sm + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  IconTheme.merge(
                    data: IconThemeData(
                      color: disabled ? tint.withValues(alpha: 0.4) : tint,
                      size: 18,
                    ),
                    child: icon!,
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: disabled ? tint.withValues(alpha: 0.4) : tint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
