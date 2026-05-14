import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_theme.dart';

/// Reusable back-arrow control sized for older-adult thumbs (44pt min hit
/// target — matches Apple HIG). Sits in the top-left of form screens, in
/// line with the auth-flow reference design.
class BackButtonHeader extends StatelessWidget {
  const BackButtonHeader({
    super.key,
    this.onPressed,
    this.color,
    this.semanticLabel = 'Back',
  });

  final VoidCallback? onPressed;
  final Color? color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.palette.onSurface;
    final handler = onPressed ?? () => Navigator.of(context).maybePop();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: handler,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 24,
              color: tint,
            ),
          ),
        ),
      ),
    );
  }
}
