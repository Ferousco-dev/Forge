import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_radius.dart';

/// Primary call-to-action button.
///
/// Filled treatment: high-contrast background with foreground text. Sized
/// generously (56px height) for older-adult thumbs, with full-width default.
///
/// Press feedback: subtle scale to 0.98 + opacity 0.92. No ripple — replaced
/// with a quieter, more premium press response.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fillColor,
    this.foregroundColor,
    this.height = 56,
    this.borderRadius = AppRadius.full,
    this.isLoading = false,
    this.expand = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? fillColor;
  final Color? foregroundColor;
  final double height;
  final double borderRadius;
  final bool isLoading;
  final bool expand;
  final Widget? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = widget.fillColor ?? scheme.primary;
    final fg = widget.foregroundColor ?? scheme.onPrimary;
    final disabledFill = fill.withValues(alpha: 0.55);
    final disabledFg = fg.withValues(alpha: 0.65);

    final body = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      height: widget.height,
      decoration: BoxDecoration(
        color: _enabled ? fill : disabledFill,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: AppMotion.fast,
        child: widget.isLoading
            ? SizedBox(
                key: const ValueKey<String>('loading'),
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            : Row(
                key: const ValueKey<String>('content'),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    IconTheme.merge(
                      data: IconThemeData(
                        color: _enabled ? fg : disabledFg,
                        size: 20,
                      ),
                      child: widget.icon!,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.0,
                        letterSpacing: -0.1,
                        fontWeight: FontWeight.w600,
                        color: _enabled ? fg : disabledFg,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: AppMotion.instant,
          curve: AppMotion.enter,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.92 : 1.0,
            duration: AppMotion.instant,
            child: widget.expand
                ? SizedBox(width: double.infinity, child: body)
                : body,
          ),
        ),
      ),
    );
  }
}
