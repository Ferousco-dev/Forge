import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Visual variant of [AppChip].
///
/// - [neutral] — outlined hairline, transparent fill, used for tags and
///   filters that aren't yet active.
/// - [primary] — filled in primary-container tint, used for the *active*
///   filter / selected state.
/// - [tonal] — soft surface fill, used as a passive label.
enum AppChipVariant { neutral, primary, tonal }

/// Pill-shaped tag / filter / status chip.
///
/// Sized with comfortable hit area (32dp tall, 12pt horizontal padding).
/// Optional [leading] icon, optional [onTap] for interactive chips.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.variant = AppChipVariant.neutral,
    this.leading,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final AppChipVariant variant;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final Color bg;
    final Color fg;
    final Color? border;

    final effectiveVariant =
        selected ? AppChipVariant.primary : variant;

    switch (effectiveVariant) {
      case AppChipVariant.neutral:
        bg = Colors.transparent;
        fg = palette.onSurface;
        border = palette.outline;
      case AppChipVariant.primary:
        bg = palette.primaryContainer;
        fg = palette.primary;
        border = null;
      case AppChipVariant.tonal:
        bg = palette.surfaceContainerHigh;
        fg = palette.onSurface;
        border = null;
    }

    Widget body = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: border == null ? null : Border.all(color: border, width: 1),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            IconTheme.merge(
              data: IconThemeData(color: fg, size: 13),
              child: leading!,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              height: 1.0,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: body,
        ),
      );
    }

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      child: body,
    );
  }
}
