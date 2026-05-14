import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../earnings/state/earnings_state.dart';
import '../../loans/state/loans_state.dart';
import '../../profile/state/profile_state.dart';
import '../state/applications_state.dart';
import '../state/sessions_state.dart';
import '../state/work_session_controller.dart';

/// "Awaiting employer confirmation" screen.
///
/// Sits between [SubmittingScreen] and [WorkCompleteScreen] when the
/// server holds the payment in the employer-signed payout window
/// (see `endpoint_resources/26_employer_signed_payouts.md`).
///
/// Three things happen here:
///   1. 1 Hz countdown ticker drives the visible "1h 42m 03s" timer.
///   2. 30s poller hits `GET /v1/sessions/{id}`. When the server flips
///      `pay_amount_disbursed > 0` (auto-release fires, OR the
///      employer hit Confirm) we transition to the complete screen.
///      When the server flips `verification_state = disputed` we
///      render the dispute state and stop polling.
///   3. Once the local countdown hits zero we accelerate polling to
///      every 10s — the server's cron should release within ~60s but
///      we don't want the UI lagging the actual settlement.
///
/// PopScope disabled — back-nav from this screen has no useful
/// destination. The worker either waits, opens another tab, or hits
/// "Find more jobs".
class PendingReviewScreen extends ConsumerStatefulWidget {
  const PendingReviewScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<PendingReviewScreen> createState() =>
      _PendingReviewScreenState();
}

class _PendingReviewScreenState extends ConsumerState<PendingReviewScreen> {
  Timer? _countdownTicker;
  Timer? _poller;

  /// Server-confirmed pollable view. Starts null; gets populated by
  /// the first poll. Drives the dispute-vs-pending UI split.
  WorkSessionRecord? _latest;

  /// Set when the polling pipeline can't reach the server. We don't
  /// crash the screen — just surface a small inline note. The poller
  /// keeps trying.
  bool _pollErrorOnce = false;

  @override
  void initState() {
    super.initState();
    // 1 Hz countdown — cheap setState, drives the "1h 42m 03s" text.
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Fire one poll on entry so the UI matches the server within a
    // few hundred ms — much better than waiting 30s for the first
    // tick.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _schedulePoller(const Duration(seconds: 30));
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _poller?.cancel();
    super.dispose();
  }

  void _schedulePoller(Duration interval) {
    _poller?.cancel();
    _poller = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> _poll() async {
    final session = ref.read(workSessionForJobProvider(widget.jobId));
    if (session == null) return;
    final sid = session.serverSessionId;
    if (sid == null) return;
    try {
      final record =
          await ref.read(sessionsRepositoryProvider).fetch(sid);
      if (!mounted) return;
      setState(() {
        _latest = record;
        _pollErrorOnce = false;
      });

      // Released — payment is on its way / landed.
      if (record.payAmountDisbursed > 0) {
        ref.read(workSessionProvider.notifier).complete(widget.jobId);
        // Same cross-feature refresh the synchronous payout path runs:
        // drop the `/me` and `/credit` caches so the loans screen's
        // unlock gate (3-jobs threshold) and AI score reflect this
        // completion the next time the worker opens those tabs. Also
        // bust earnings + applications so a new payout row and the
        // app's "active applications" pill update on their own.
        ref.invalidate(currentWorkerProvider);
        ref.invalidate(creditProfileProvider);
        ref.invalidate(transactionsProvider);
        ref.invalidate(activeApplicationsProvider);
        if (!mounted) return;
        context.pushReplacement(
          RoutePaths.jobClockOutComplete(widget.jobId),
        );
        return;
      }

      // Employer disputed. Stop polling, render the dispute state.
      if (record.verificationState ==
          WorkSessionVerificationState.disputed) {
        _poller?.cancel();
        return;
      }

      // Past the local countdown but server hasn't released yet —
      // tighten the polling cadence so we surface the release as
      // soon as the server cron fires (~60s after the hold expires).
      final releaseAt = record.holdReleaseAt ?? session.holdReleaseAt;
      if (releaseAt != null &&
          DateTime.now().toUtc().isAfter(releaseAt) &&
          _poller?.tick != null) {
        _schedulePoller(const Duration(seconds: 10));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pollErrorOnce = true);
    }
  }

  /// Best-known release time: prefer the freshly-polled record, fall
  /// back to whatever the controller stashed at submit time.
  DateTime? get _releaseAt {
    return _latest?.holdReleaseAt ??
        ref.read(workSessionForJobProvider(widget.jobId))?.holdReleaseAt;
  }

  Duration get _remaining {
    final releaseAt = _releaseAt;
    if (releaseAt == null) return Duration.zero;
    final diff = releaseAt.difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  String _formatCountdown(Duration d) {
    if (d == Duration.zero) return 'Releasing…';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '$m:$s';
  }

  void _findMoreJobs() {
    // Don't reset() — the worker still has a session in flight. Just
    // route them back to the feed. They can come back to /jobs/:id/
    // clock-out/pending via the active-session card on the home
    // sheet.
    context.go(RoutePaths.jobs);
  }

  void _viewEarnings() {
    context.go(RoutePaths.earnings);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = ref.watch(workSessionForJobProvider(widget.jobId));

    if (session == null ||
        (session.phase != WorkPhase.pendingReview &&
            session.phase != WorkPhase.submitting)) {
      return Scaffold(
        backgroundColor: palette.surface,
        body: const SafeArea(
          child: EmptyStateView(
            title: 'No session pending review',
            subtitle: 'Head back to your jobs.',
          ),
        ),
      );
    }

    final disputed = _latest?.verificationState ==
        WorkSessionVerificationState.disputed;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.surface,
        body: SafeArea(
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
                if (disputed)
                  _DisputeHero()
                else
                  _PendingHero(
                    countdownLabel: _formatCountdown(_remaining),
                  ),
                const SizedBox(height: AppSpacing.xl),
                _AmountCard(
                  amount: session.pendingAmount ?? session.job.payAmount,
                  jobTitle: session.job.title,
                  employerName: session.job.employer.name,
                  disputed: disputed,
                ),
                const SizedBox(height: AppSpacing.lg),
                _VerificationChecklist(disputed: disputed),
                if (_pollErrorOnce) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Couldn't sync the latest status. We'll try again "
                    'in a moment.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (disputed)
                  PrimaryButton(
                    label: 'View my earnings',
                    onPressed: _viewEarnings,
                  )
                else
                  PrimaryButton(
                    label: 'Find more jobs',
                    onPressed: _findMoreJobs,
                  ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: disputed ? 'Back to jobs' : 'View my earnings',
                  onPressed: disputed ? _findMoreJobs : _viewEarnings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingHero extends StatelessWidget {
  const _PendingHero({required this.countdownLabel});
  final String countdownLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: palette.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.hourglass_top_rounded,
            size: 48,
            color: palette.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Awaiting employer confirmation',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your employer has 2 hours to review. If they don\'t '
          'respond, you\'ll be paid automatically.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          countdownLabel,
          style: AppTextStyles.displayMedium.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            fontFeatures: const <FontFeature>[
              FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'until auto-release',
          style: AppTextStyles.labelMedium.copyWith(
            color: palette.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _DisputeHero extends StatelessWidget {
  const _DisputeHero();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: palette.error.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.gavel_rounded,
            size: 44,
            color: palette.error,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Your employer flagged this clock-out',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          "We're reviewing the details. You'll hear back within 24 "
          "hours — your payment is frozen until then.",
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.amount,
    required this.jobTitle,
    required this.employerName,
    required this.disputed,
  });

  final int amount;
  final String jobTitle;
  final String employerName;
  final bool disputed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            disputed ? 'Held for review' : 'Pending payment',
            style: AppTextStyles.labelMedium.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          CurrencyText(amount: amount, size: CurrencySize.large),
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: palette.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            jobTitle,
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            employerName,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationChecklist extends StatelessWidget {
  const _VerificationChecklist({required this.disputed});
  final bool disputed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Row(
            tint: palette.success,
            icon: Icons.check_circle_rounded,
            label: 'Photo verified',
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            tint: palette.success,
            icon: Icons.check_circle_rounded,
            label: 'Location verified',
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            tint: palette.success,
            icon: Icons.check_circle_rounded,
            label: 'Time on the job verified',
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            tint: disputed ? palette.error : palette.onSurfaceVariant,
            icon: disputed
                ? Icons.cancel_rounded
                : Icons.hourglass_bottom_rounded,
            label: disputed
                ? 'Employer review — flagged'
                : 'Employer review — pending',
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.tint, required this.icon, required this.label});
  final Color tint;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: tint),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
