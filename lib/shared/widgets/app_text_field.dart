import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Premium text field used across auth/onboarding/profile forms.
///
/// Visual treatment matches the reference auth screens: pill-shaped, white
/// fill, soft hairline border, comfortable 56pt height for older-adult
/// thumbs, with an optional trailing icon (the password eye-toggle is the
/// canonical use of this slot).
///
/// Built on top of [TextField] so we get accessibility, copy/paste, IME,
/// autofill, and password manager hooks for free — wrapping a raw
/// [TextEditingController] would lose all of that.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.allowReveal = false,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.autofocus = false,
    this.accentColor,
    this.prefixText,
    this.maxLength,
  });

  final String label;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;

  /// When true *and* [obscureText] is true, renders a trailing eye toggle
  /// the user can tap to reveal/hide the value.
  final bool allowReveal;

  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;

  /// Quiet helper line under the field. Hidden when [errorText] is set.
  final String? helperText;

  final bool enabled;
  final bool autofocus;

  /// Optional override for the focused border, focused glow, and cursor
  /// tint. Defaults to the active theme's primary.
  final Color? accentColor;

  /// Locked, non-editable text rendered inside the field on the leading
  /// edge. Used by the auth flow to show the `+234` country prefix —
  /// the user types only the local digits.
  final String? prefixText;

  /// Caps the maximum number of characters the user can type. Suppresses
  /// the default Material counter so the visual stays clean.
  final int? maxLength;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChanged);

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasError = widget.errorText != null;
    final focused = _focusNode.hasFocus;
    final accent = widget.accentColor ?? palette.primary;
    final borderColor = hasError
        ? palette.error
        : focused
            ? accent
            : palette.outline;
    final borderWidth = focused || hasError ? 1.5 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: <Widget>[
              if (widget.prefixText != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(
                    widget.prefixText!,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      color: palette.onSurface,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: palette.outline,
                ),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  obscureText: _obscured,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autofillHints: widget.autofillHints,
                  inputFormatters: widget.inputFormatters,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  maxLength: widget.maxLength,
                  cursorColor: accent,
                  cursorWidth: 1.6,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: palette.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.label,
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: palette.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: widget.prefixText != null ? 0 : 20,
                      vertical: 18,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              if (widget.obscureText && widget.allowReveal)
                _RevealToggle(
                  obscured: _obscured,
                  color: palette.onSurfaceVariant,
                  onTap: () => setState(() => _obscured = !_obscured),
                ),
              if (!widget.obscureText)
                const SizedBox(width: 8),
            ],
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              widget.errorText!,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.error,
              ),
            ),
          ),
        ] else if (widget.helperText != null) ...<Widget>[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              widget.helperText!,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RevealToggle extends StatelessWidget {
  const _RevealToggle({
    required this.obscured,
    required this.color,
    required this.onTap,
  });

  final bool obscured;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: obscured ? 'Show password' : 'Hide password',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Icon(
            obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 22,
            color: color,
          ),
        ),
      ),
    );
  }
}
