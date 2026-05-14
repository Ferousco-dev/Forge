import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Lets a host widget drive the OTP input from outside — used to
/// implement a "Paste from clipboard" button on the OTP screen. The
/// host creates the controller, hands it to [OtpInput], and calls
/// `controller.fill('123456')` to populate the boxes (the existing
/// internal paste-distribute logic handles partial values too).
///
/// Dispose with [dispose] if the host owns the controller, otherwise
/// just let it go when the parent State is torn down.
class OtpInputController {
  _OtpInputState? _state;

  void _attach(_OtpInputState state) => _state = state;
  void _detach(_OtpInputState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Fill the boxes with [code]. Non-digit characters are stripped.
  /// Excess digits beyond the input's [OtpInput.length] are dropped.
  void fill(String code) => _state?._distribute(0, code);

  /// Clear every box and refocus the first.
  void clear() => _state?._clearAll();

  void dispose() {
    _state = null;
  }
}

/// 6-digit OTP input.
///
/// Six visually separate boxes with auto-advance on input, backspace
/// rewind, paste-friendly distribution, and an error state that tints
/// every box red. Designed for one-time codes; not a generalized PIN
/// input (no obscuring).
///
/// Notify the host of changes via [onChanged] (full string, possibly
/// shorter than [length]) and [onCompleted] (called once when all
/// boxes are filled). Pass an [OtpInputController] to drive the value
/// programmatically (e.g. paste-from-clipboard buttons).
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.errorText,
    this.autofocus = true,
    this.boxSize = 52,
    this.spacing = 10,
    this.controller,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final String? errorText;
  final bool autofocus;
  final double boxSize;
  final double spacing;
  final OtpInputController? controller;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(
      widget.length,
      (_) => FocusNode(),
    );
    for (final FocusNode n in _focusNodes) {
      n.addListener(_onFocus);
    }
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant OtpInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    for (final FocusNode n in _focusNodes) {
      n.removeListener(_onFocus);
      n.dispose();
    }
    super.dispose();
  }

  void _onFocus() => setState(() {});

  String get _value => _controllers.map((TextEditingController c) => c.text).join();

  void _emit() {
    final value = _value;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _onChanged(int i, String v) {
    // Paste handling — multi-character input gets distributed across
    // remaining boxes via the shared helper.
    if (v.length > 1) {
      _distribute(i, v);
      return;
    }

    if (v.isEmpty) {
      // Backspace on already-empty box: jump back.
      if (i > 0) _focusNodes[i - 1].requestFocus();
    } else if (i < widget.length - 1) {
      _focusNodes[i + 1].requestFocus();
    } else {
      _focusNodes[i].unfocus();
    }
    _emit();
  }

  /// Spread the digits of [code] across the boxes starting at [start].
  /// Non-digit characters are stripped; excess digits are dropped.
  /// Drives both the in-input paste flow and the external
  /// [OtpInputController.fill] entry point.
  void _distribute(int start, String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    for (int j = 0; j < widget.length - start; j++) {
      if (j >= digits.length) break;
      _controllers[start + j].text = digits[j];
    }
    final lastFilled =
        (start + digits.length).clamp(0, widget.length - 1);
    _focusNodes[lastFilled].requestFocus();
    _emit();
  }

  /// Empty every box and refocus the first. Used by
  /// [OtpInputController.clear].
  void _clearAll() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
    _emit();
  }

  KeyEventResult _onKey(int i, FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[i].text.isEmpty &&
        i > 0) {
      _focusNodes[i - 1].requestFocus();
      _controllers[i - 1].clear();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasError = widget.errorText != null;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Pick a box size that fits the container width without overflow,
        // capped at the requested [widget.boxSize] for spacious displays.
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.length * widget.boxSize +
                (widget.length - 1) * widget.spacing;
        final totalSpacing = widget.spacing * (widget.length - 1);
        final fitBoxSize =
            ((maxWidth - totalSpacing) / widget.length).clamp(36.0, widget.boxSize);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < widget.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: widget.spacing),
                  _Box(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    size: fitBoxSize,
                    hasError: hasError,
                    autofocus: widget.autofocus && i == 0,
                    onChanged: (String v) => _onChanged(i, v),
                    onKeyEvent: (FocusNode n, KeyEvent e) => _onKey(i, n, e),
                    accent: palette.primary,
                  ),
                ],
              ],
            ),
            if (hasError) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                widget.errorText!,
                style: AppTextStyles.bodySmall.copyWith(color: palette.error),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.controller,
    required this.focusNode,
    required this.size,
    required this.hasError,
    required this.autofocus,
    required this.onChanged,
    required this.onKeyEvent,
    required this.accent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double size;
  final bool hasError;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final focused = focusNode.hasFocus;
    final filled = controller.text.isNotEmpty;
    final borderColor = hasError
        ? palette.error
        : focused
            ? accent
            : filled
                ? palette.onSurfaceVariant
                : palette.outline;
    final borderWidth = focused || hasError ? 1.5 : 1.0;

    return Focus(
      onKeyEvent: onKeyEvent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: palette.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Center(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            textAlign: TextAlign.center,
            cursorColor: accent,
            cursorWidth: 1.6,
            maxLength: 1,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: AppTextStyles.headlineSmall.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
