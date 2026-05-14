import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../state/loans_state.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';

/// Loan application — amount slider + terms + disclosure + agreement.
///
/// Eligibility ceiling is computed from the worker's credit score and
/// drives the upper slider bound. Terms (interest rate, duration,
/// repayment per job, total repayable) are computed from the chosen
/// amount via the same mock-only formula used elsewhere; backend
/// integration replaces the formula with a server-side decision.
class LoanApplicationScreen extends ConsumerStatefulWidget {
  const LoanApplicationScreen({super.key});

  @override
  ConsumerState<LoanApplicationScreen> createState() =>
      _LoanApplicationScreenState();
}

class _LoanApplicationScreenState extends ConsumerState<LoanApplicationScreen> {
  static const int _minAmount = 5000;

  // Mock loan terms — flat 8% fee, 90-day term, 15% repayment per job.
  static const double _interestPercent = 8.0;
  static const int _durationDays = 90;
  static const double _repaymentPercentPerJob = 0.15;

  double? _amount;
  bool _agreed = false;
  bool _disclosureExpanded = false;
  bool _submitting = false;

  /// Stable per-attempt id. Reused across retries (network blip,
  /// 5xx) so the server returns the existing loan instead of
  /// creating a duplicate. Reset on terminal success/rejection or
  /// when the user changes the principal — both are signals that
  /// the next submit is a new logical attempt.
  String? _attemptId;

  int _ceilingFor(int score) {
    if (score >= 80) return 100000;
    if (score >= 70) return 50000;
    if (score >= 60) return 20000;
    return 0;
  }

  int get _selectedAmount => (_amount ?? _minAmount.toDouble()).round();
  int get _totalRepayable =>
      (_selectedAmount * (1 + _interestPercent / 100)).round();
  int get _perJobAmount =>
      (_selectedAmount * _repaymentPercentPerJob).round();

  Future<void> _submit() async {
    if (!_agreed || _submitting) return;
    // Mint once per attempt; reuse across retries.
    _attemptId ??= const Uuid().v4();
    setState(() => _submitting = true);
    Loan? loan;
    try {
      loan = await ref.read(loansRepositoryProvider).apply(
            principal: _selectedAmount,
            repaymentPercentPerJob: _repaymentPercentPerJob,
            clientLoanId: _attemptId!,
          );
      ref.invalidate(activeLoanProvider);
      // Server returned a terminal decision — a future re-submit
      // (e.g. user retries after editing) is a new logical attempt.
      _attemptId = null;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.base),
          content: Text(e.message),
        ));
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    // Branch on the server's decision: instant approval vs. queued
    // review vs. immediate rejection (per `14_loan_apply.md`).
    final destination = switch (loan.status) {
      LoanStatus.approved => RoutePaths.loanApproved,
      LoanStatus.rejected => RoutePaths.loanRejected,
      _ => RoutePaths.loanPending,
    };
    context.pushReplacement(destination);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);

    return workerAsync.when(
      loading: () => Scaffold(
        backgroundColor: palette.surface,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object _, StackTrace _) => Scaffold(
        backgroundColor: palette.surface,
        body: const SafeArea(
          child: EmptyStateView(
            title: 'Profile temporarily unavailable',
            subtitle: 'Try again in a moment.',
          ),
        ),
      ),
      data: (Worker worker) {
        final ceiling = _ceilingFor(worker.creditScore);
        if (ceiling == 0) {
          return Scaffold(
            backgroundColor: palette.surface,
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  const BackButtonHeader(),
                  Expanded(
                    child: EmptyStateView(
                      title: 'Not yet eligible',
                      subtitle:
                          'Complete a few more on-time jobs and your loan '
                          'eligibility will unlock automatically.',
                      illustration: Icon(
                        Icons.lock_rounded,
                        size: 56,
                        color: palette.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        _amount ??= _minAmount.toDouble();

        return Scaffold(
          backgroundColor: palette.surface,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'How much do you need?',
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: palette.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'You\'re pre-approved up to '
                          '₦${_formatThousands(ceiling)}.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Center(
                          child: CurrencyText(
                            amount: _selectedAmount,
                            size: CurrencySize.large,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _AmountSlider(
                          value: _amount!,
                          min: _minAmount.toDouble(),
                          max: ceiling.toDouble(),
                          onChanged: (double v) =>
                              setState(() => _amount = v),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _TermsCard(
                          interestPercent: _interestPercent,
                          durationDays: _durationDays,
                          perJobAmount: _perJobAmount,
                          totalRepayable: _totalRepayable,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _Disclosure(
                          expanded: _disclosureExpanded,
                          onToggle: () => setState(() =>
                              _disclosureExpanded = !_disclosureExpanded),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _AgreementCheckbox(
                          value: _agreed,
                          onChanged: (bool v) =>
                              setState(() => _agreed = v),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
                _StickyButton(
                  enabled: _agreed,
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const BackButtonHeader(),
          Expanded(
            child: Text(
              'Apply for a loan',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _AmountSlider extends StatelessWidget {
  const _AmountSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: palette.primary,
            inactiveTrackColor: palette.outline,
            thumbColor: palette.primary,
            overlayColor: palette.primary.withValues(alpha: 0.10),
            trackHeight: 4,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 12),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: 20,
            label: '₦${_formatThousands(value.round())}',
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '₦${_formatThousands(min.round())}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              Text(
                '₦${_formatThousands(max.round())}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({
    required this.interestPercent,
    required this.durationDays,
    required this.perJobAmount,
    required this.totalRepayable,
  });

  final double interestPercent;
  final int durationDays;
  final int perJobAmount;
  final int totalRepayable;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      child: Column(
        children: <Widget>[
          _Row(
            label: 'Interest',
            value: '${interestPercent.toStringAsFixed(0)}%',
          ),
          Divider(height: AppSpacing.lg, color: palette.outlineVariant),
          _Row(
            label: 'Repayment duration',
            value: '$durationDays days',
          ),
          Divider(height: AppSpacing.lg, color: palette.outlineVariant),
          _Row(
            label: 'Per-job repayment',
            value: '₦${_formatThousands(perJobAmount)}',
          ),
          Divider(height: AppSpacing.lg, color: palette.outlineVariant),
          _Row(
            label: 'Total repayable',
            value: '₦${_formatThousands(totalRepayable)}',
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: emphasized ? palette.primary : palette.onSurface,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.expanded, required this.onToggle});
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: AppRadius.allLg,
      background: palette.surfaceContainerHigh,
      borderColor: palette.outlineVariant,
      child: Column(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: palette.onSurface),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'How repayment works',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                0,
                AppSpacing.base,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _DisclosureBullet(
                    text: 'Repayments are deducted automatically '
                        'from your earnings (10–20% per job).',
                  ),
                  _DisclosureBullet(
                    text: 'Loans are only available while you\'re '
                        'actively working through Forge.',
                  ),
                  _DisclosureBullet(
                    text: 'Late or missed payments may affect your '
                        'credit score and future eligibility.',
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}

class _DisclosureBullet extends StatelessWidget {
  const _DisclosureBullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6, right: AppSpacing.sm),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: palette.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgreementCheckbox extends StatelessWidget {
  const _AgreementCheckbox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Checkbox(
                value: value,
                onChanged: (bool? v) => onChanged(v ?? false),
                visualDensity: VisualDensity.compact,
                activeColor: palette.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'I understand and agree to these terms.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyButton extends StatelessWidget {
  const _StickyButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: PrimaryButton(
            label: 'Submit application',
            isLoading: loading,
            onPressed: enabled ? onPressed : null,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

String _formatThousands(int amount) {
  final s = amount.toString();
  if (s.length <= 3) return s;
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
