import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/primary_button.dart';

/// Shared layout for the login + signup phone-entry screens.
///
/// Both screens are structurally identical — back arrow, title,
/// description, single phone field with `+234` locked prefix, primary
/// CTA, and a footer link. Only the copy and the navigation targets
/// differ. Extracting this scaffold keeps the two leaves below 60 lines
/// each and guarantees they stay visually in sync.
class PhoneEntryScaffold extends StatefulWidget {
  const PhoneEntryScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.footerPrompt,
    required this.footerActionLabel,
    required this.onContinue,
    required this.onFooterAction,
    this.showBack = true,
    this.greeting,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String ctaLabel;
  final String footerPrompt;
  final String footerActionLabel;

  /// Called with the local 10-digit phone number when the user taps
  /// the primary CTA. The scaffold guarantees [phone] is exactly 10
  /// digits before invoking, awaits the returned `Future`, and pins
  /// the button into its loading state until it resolves. Throw an
  /// [ApiException] from inside to render the message inline.
  final Future<void> Function(String phone) onContinue;

  final VoidCallback onFooterAction;

  /// Whether to render the leading back-arrow. Login is the entry
  /// point of the auth flow and has nowhere to go back to, so it
  /// passes `false`. Signup defaults to `true`.
  final bool showBack;

  /// Optional small kicker above the title — used for the time-based
  /// "Good morning / afternoon / evening" greeting on login.
  final String? greeting;

  /// Optional widget rendered below the footer link. Used for
  /// auxiliary affordances (e.g. the dev test-notification button).
  final Widget? trailing;

  @override
  State<PhoneEntryScaffold> createState() => _PhoneEntryScaffoldState();
}

class _PhoneEntryScaffoldState extends State<PhoneEntryScaffold> {
  final TextEditingController _phone = TextEditingController();
  String? _error;
  bool _submitting = false;

  bool get _isValid => _phone.text.length == 10;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) {
      setState(() => _error = 'Enter all 10 digits of your phone number');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onContinue(_phone.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: palette.surface,
      // Keyboard inset is absorbed by the scroll view's bottom padding
      // below — keeps the layout stable while the focused field still
      // scrolls into view above the keyboard.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg + keyboardInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.showBack)
                const BackButtonHeader()
              else
                // Reserve the same top spacing the back button would
                // have occupied so the title doesn't jump up against
                // the status bar.
                const SizedBox(height: AppSpacing.md),
              const SizedBox(height: AppSpacing.xl),
              if (widget.greeting != null) ...<Widget>[
                Text(
                  widget.greeting!,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: palette.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                widget.title,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.subtitle,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                label: '801 234 5678',
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                maxLength: 10,
                prefixText: '+234',
                helperText: "We'll send you a code to verify your number.",
                errorText: _error,
                autofocus: true,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                  if (_isValid != (_phone.text.length == 10)) setState(() {});
                  setState(() {});
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: widget.ctaLabel,
                isLoading: _submitting,
                onPressed: _isValid ? _submit : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    widget.footerPrompt.trimRight(),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                  AppTextButton(
                    label: widget.footerActionLabel,
                    onPressed: widget.onFooterAction,
                    dense: true,
                  ),
                ],
              ),
              if (widget.trailing != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
