import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confetti_overlay.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../state/work_session_controller.dart';

/// Final screen of the work flow.
///
/// Brief: confetti animation (one-shot on entry), big green check,
/// "Work complete!" headline, earnings card showing the amount sent
/// to the wallet, transaction details (collapsed), two CTAs:
/// "Find more jobs" and "View my earnings".
///
/// Both CTAs reset the [WorkSessionController] so the next accepted
/// application starts a fresh session.
class WorkCompleteScreen extends ConsumerWidget {
  const WorkCompleteScreen({super.key, required this.jobId});
  final String jobId;

  void _findMoreJobs(BuildContext context, WidgetRef ref) {
    ref.read(workSessionProvider.notifier).remove(jobId);
    context.go(RoutePaths.jobs);
  }

  void _viewEarnings(BuildContext context, WidgetRef ref) {
    ref.read(workSessionProvider.notifier).remove(jobId);
    context.go(RoutePaths.earnings);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final session = ref.watch(workSessionForJobProvider(jobId));

    if (session == null || session.phase != WorkPhase.done) {
      return Scaffold(
        backgroundColor: palette.surface,
        body: const SafeArea(
          child: EmptyStateView(
            title: 'No completed session',
            subtitle: 'Head back to your applications.',
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.surface,
        body: Stack(
          children: <Widget>[
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SuccessHero(),
                    const SizedBox(height: AppSpacing.xl),
                    _EarningsCard(amount: session.job.payAmount),
                    const SizedBox(height: AppSpacing.lg),
                    _TransactionDetails(session: session),
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: 'Find more jobs',
                      onPressed: () => _findMoreJobs(context, ref),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SecondaryButton(
                      label: 'View my earnings',
                      onPressed: () => _viewEarnings(context, ref),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned.fill(child: ConfettiOverlay()),
          ],
        ),
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: palette.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_circle_rounded,
            size: 64,
            color: palette.success,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Work complete!',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          "You've added another job to your record.",
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.success.withValues(alpha: 0.30),
      background: palette.success.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: palette.success,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Sent to your wallet',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.success,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CurrencyText(
            amount: amount,
            size: CurrencySize.large,
            tone: CurrencyTone.credit,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Paid instantly via Squad',
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionDetails extends StatefulWidget {
  const _TransactionDetails({required this.session});
  final WorkSession session;

  @override
  State<_TransactionDetails> createState() => _TransactionDetailsState();
}

class _TransactionDetailsState extends State<_TransactionDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final job = widget.session.job;
    final completedAt = DateFormat('EEE, MMM d · h:mm a').format(DateTime.now());
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Transaction details',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
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
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                0,
                AppSpacing.base,
                AppSpacing.base,
              ),
              child: Column(
                children: <Widget>[
                  Divider(height: 1, color: palette.outlineVariant),
                  const SizedBox(height: AppSpacing.sm),
                  _DetailLine(label: 'Job', value: job.title),
                  const SizedBox(height: AppSpacing.sm),
                  _DetailLine(label: 'Employer', value: job.employer.name),
                  const SizedBox(height: AppSpacing.sm),
                  _DetailLine(label: 'Completed', value: completedAt),
                  const SizedBox(height: AppSpacing.sm),
                  _DetailLine(
                    label: 'Location',
                    value: job.locationAddress,
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
