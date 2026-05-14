import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_text_button.dart';
import '../../../../shared/widgets/back_button_header.dart';
import '../../../../shared/widgets/primary_button.dart';

/// Shared layout for permission-prompt screens.
///
/// Brief calls for the same shape on `/auth/permissions/location` and
/// `/auth/permissions/notifications`: hero illustration, headline, body
/// copy, primary "Enable" CTA, and a secondary text button (one is
/// "Maybe later" with a dimmed warning tone, the other is plain "Skip").
///
/// The decline label is styled `dimmed` when [warnOnDecline] is true,
/// and a small warning hint renders below the button — captures the
/// brief's "(dimmed, with warning that app won't work well)".
class PermissionScaffold extends StatefulWidget {
  const PermissionScaffold({
    super.key,
    required this.illustration,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.declineLabel,
    required this.onPrimary,
    required this.onDecline,
    this.warnOnDecline = false,
    this.declineWarning,
  });

  final Widget illustration;
  final String title;
  final String body;
  final String primaryLabel;
  final String declineLabel;
  final VoidCallback onPrimary;
  final VoidCallback onDecline;
  final bool warnOnDecline;
  final String? declineWarning;

  @override
  State<PermissionScaffold> createState() => _PermissionScaffoldState();
}

class _PermissionScaffoldState extends State<PermissionScaffold> {
  bool _enabling = false;

  Future<void> _enable() async {
    setState(() => _enabling = true);
    // Simulates the system permission dialog round-trip. Real prompt
    // wires in via `permission_handler` once a backend is wired.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _enabling = false);
    widget.onPrimary();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            children: <Widget>[
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: BackButtonHeader(),
              ),
              const Spacer(flex: 3),
              widget.illustration,
              const SizedBox(height: AppSpacing.xl),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  widget.body,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: widget.primaryLabel,
                  isLoading: _enabling,
                  onPressed: _enable,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextButton(
                label: widget.declineLabel,
                onPressed: widget.onDecline,
                color: widget.warnOnDecline
                    ? palette.onSurfaceVariant
                    : null,
              ),
              if (widget.warnOnDecline && widget.declineWarning != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    widget.declineWarning!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
