import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Semantic colors for status badges.
enum StatusBadgeTone {
  /// Pending / informational (info blue).
  info,

  /// Positive (success green).
  success,

  /// Caution (warning amber).
  warning,

  /// Failure (error red).
  error,

  /// Neutral / default state.
  neutral,
}

/// Colored pill used to communicate status — application status, loan
/// status, transaction status. Smaller and less interactive than
/// [AppChip]; not tappable, not focusable.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.dense = false,
  });

  final String label;
  final StatusBadgeTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final (Color fg, Color bg) = switch (tone) {
      StatusBadgeTone.info => (palette.info, palette.info.withValues(alpha: 0.10)),
      StatusBadgeTone.success => (
          palette.success,
          palette.success.withValues(alpha: 0.10),
        ),
      StatusBadgeTone.warning => (
          palette.warning,
          palette.warning.withValues(alpha: 0.12),
        ),
      StatusBadgeTone.error => (
          palette.error,
          palette.error.withValues(alpha: 0.10),
        ),
      StatusBadgeTone.neutral => (
          palette.onSurfaceVariant,
          palette.surfaceContainerHigh,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? AppSpacing.xs : AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelMedium.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
