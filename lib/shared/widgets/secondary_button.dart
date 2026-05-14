import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_radius.dart';

/// Secondary / "ghost" button. Outlined treatment, transparent fill.
///
/// Same dimensions as [PrimaryButton] so vertically stacked button pairs
/// align cleanly. Border + label tint share the same color so brand
/// surfaces just need one color value.
class SecondaryButton extends StatefulWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.height = 56,
    this.borderRadius = AppRadius.full,
    this.borderWidth = 1.5,
    this.expand = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final double height;
  final double borderRadius;
  final double borderWidth;
  final bool expand;
  final Widget? icon;

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? Theme.of(context).colorScheme.primary;
    final resolved = _enabled ? base : base.withValues(alpha: 0.45);
    // Pressed state tints the fill faintly so the button reads as active
    // without a hard ripple.
    final pressedFill = base.withValues(alpha: 0.10);

    final body = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      height: widget.height,
      decoration: BoxDecoration(
        color: _pressed ? pressedFill : Colors.transparent,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: resolved, width: widget.borderWidth),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (widget.icon != null) ...<Widget>[
            IconTheme.merge(
              data: IconThemeData(color: resolved, size: 20),
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
                color: resolved,
              ),
            ),
          ),
        ],
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
          child: widget.expand
              ? SizedBox(width: double.infinity, child: body)
              : body,
        ),
      ),
    );
  }
}
