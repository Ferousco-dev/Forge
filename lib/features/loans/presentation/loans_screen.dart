import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/loans_state.dart';
import '../widgets/credit_score_gauge.dart';

/// Loans tab.
///
/// Brief calls for two layouts driven by data:
/// - **No active loan**: credit score hero + "How you're doing" stats +
///   eligibility CTA (or not-yet-eligible progress when score < 60).
/// - **Active loan**: outstanding balance card at top + repayment
///   history + the same credit score / stats below.
///
/// Both branches share the credit-score block; only the top section
/// swaps. Eligibility ceiling is derived from credit score per a
/// simple table the brief implies.
///
/// The "Loans" title is a pinned [SliverAppBar] so it stays anchored
/// at the top while the body scrolls underneath — same anchored-header
/// pattern as the Earnings tab.
/// Minimum number of completed jobs before we render the credit-score
/// gauge with the legacy `worker.credit_score` field. Below this we
/// show the "build your credit score" card instead — a single job is
/// not enough history for the score to be meaningful, and the backend's
/// default seed (mid-50s "Fair") reads like a real evaluation when it
/// isn't one.
///
/// Bypassed when the server has actually AI-scored the worker
/// (`CreditProfile.lastEvaluatedAt != null`) — in that case the gauge
/// is the model's real output regardless of job count.
const int _minJobsForScore = 3;

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(currentWorkerProvider)
      ..invalidate(activeLoanProvider)
      ..invalidate(creditProfileProvider);
    await Future.wait<dynamic>(<Future<dynamic>>[
      ref.read(currentWorkerProvider.future),
      ref.read(activeLoanProvider.future),
      ref.read(creditProfileProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);
    final loanAsync = ref.watch(activeLoanProvider);
    final creditAsync = ref.watch(creditProfileProvider);

    // Bottom inset is the nav-bar height + system gesture bar — see
    // HomeShell which injects this into MediaQuery.padding.bottom.
    final double bottomPad = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                floating: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: palette.surface,
                surfaceTintColor: Colors.transparent,
                automaticallyImplyLeading: false,
                titleSpacing: AppSpacing.lg,
                toolbarHeight: 56,
                title: Text(
                  'Loans',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              ...workerAsync.when(
                loading: () => const <Widget>[
                  SliverToBoxAdapter(child: _LoansLoadingSkeleton()),
                ],
                error: (Object _, StackTrace _) => <Widget>[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorStateView(
                      title: "Couldn't load your loan profile",
                      message: 'Try again — your record is safe.',
                      onRetry: () => ref.invalidate(currentWorkerProvider),
                    ),
                  ),
                ],
                data: (Worker worker) => <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(<Widget>[
                        // Top section depends on whether the worker has
                        // a loan.
                        loanAsync.when(
                          loading: () => const _ActiveLoanSkeleton(),
                          error: (Object _, StackTrace _) =>
                              const SizedBox.shrink(),
                          data: (Loan? loan) => loan == null
                              ? const SizedBox.shrink()
                              : _ActiveLoanCard(loan: loan),
                        ),
                        if (loanAsync.valueOrNull != null)
                          const SizedBox(height: AppSpacing.lg),

                        // Credit score hero.
                        //
                        // We render the gauge only when there's a real
                        // score to render. Two paths qualify:
                        //   1. Server has AI-evaluated the worker
                        //      (`last_evaluated_at` present). The number
                        //      is then the model's actual output.
                        //   2. Worker has completed enough jobs
                        //      (`_minJobsForScore`) that the legacy
                        //      `worker.credit_score` field is meaningful
                        //      even without an AI evaluation timestamp.
                        //
                        // Otherwise, the score is just the backend's
                        // default seed — surfacing a mid-50s "Fair"
                        // dial after a worker's first job (as in the
                        // bug screenshot) reads like a real evaluation
                        // when it isn't one. Replace the gauge with the
                        // "build your credit score" card so the message
                        // matches reality.
                        Builder(
                          builder: (BuildContext _) {
                            final credit = creditAsync.valueOrNull;
                            final hasServerEvaluation =
                                credit?.lastEvaluatedAt != null;
                            final hasEnoughHistory = worker.jobsCompleted >=
                                _minJobsForScore;
                            if (!hasServerEvaluation && !hasEnoughHistory) {
                              return _NoTrackRecordCard(
                                jobsCompleted: worker.jobsCompleted,
                                jobsNeeded:
                                    _minJobsForScore - worker.jobsCompleted,
                              );
                            }
                            return Column(
                              children: <Widget>[
                                Center(
                                  child: CreditScoreGauge(
                                    score: credit?.creditScore ??
                                        worker.creditScore,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _SubtitleLine(
                                  score: credit?.creditScore ??
                                      worker.creditScore,
                                  serverSubtitle: credit?.subtitle,
                                ),
                                if (credit?.lastEvaluatedAt != null) ...<Widget>[
                                  const SizedBox(height: AppSpacing.xs),
                                  _LastEvaluatedLine(
                                    at: credit!.lastEvaluatedAt!,
                                    modelVersion: credit.modelVersion,
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // How you're doing — 4 stat cards. Prefer
                        // server signals (AI input snapshot) when
                        // available so the numbers match what the
                        // model actually scored on.
                        Text(
                          "How you're doing",
                          style: AppTextStyles.titleLarge.copyWith(
                            color: palette.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _StatsGrid(
                          worker: worker,
                          signals: creditAsync.valueOrNull?.signals,
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // What's pulling the score down — the AI
                        // model's risk factors, server-rendered.
                        if ((creditAsync.valueOrNull?.riskFactors ??
                                const <CreditRiskFactor>[])
                            .isNotEmpty) ...<Widget>[
                          _RiskFactorsBlock(
                            factors: creditAsync.value!.riskFactors,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],

                        // Concrete next steps the model recommends.
                        if ((creditAsync.valueOrNull?.improvementActions ??
                                const <CreditImprovementAction>[])
                            .isNotEmpty) ...<Widget>[
                          _ImprovementActionsBlock(
                            actions:
                                creditAsync.value!.improvementActions,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],

                        // Eligibility CTA / repayment history.
                        loanAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (Object _, StackTrace _) =>
                              const SizedBox.shrink(),
                          data: (Loan? loan) {
                            if (loan != null) {
                              return _RepaymentHistory(loan: loan);
                            }
                            return _EligibilityCard(
                              worker: worker,
                              credit: creditAsync.valueOrNull,
                            );
                          },
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
              // Pad past the floating bottom nav so the last card
              // ("Apply for a loan") isn't half-covered.
              SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

/// Placeholder card that occupies the same vertical space as the
/// [CreditScoreGauge] while the worker still has too little history
/// for a meaningful score. The backend defaults a new account to a
/// mid-50s seed; rendering that as a real number under a tinted dial
/// misrepresents what's actually a "no track record yet" state. The
/// card also shows progress toward [_minJobsForScore] so a worker on
/// their first job sees a concrete target ("1 of 3 jobs done") rather
/// than a flat "do more jobs" prompt.
class _NoTrackRecordCard extends StatelessWidget {
  const _NoTrackRecordCard({
    required this.jobsCompleted,
    required this.jobsNeeded,
  });

  /// Jobs the worker has completed so far. Drives the progress chip.
  final int jobsCompleted;

  /// Jobs still required before the gauge unlocks. Always > 0 when
  /// this card is rendered (the gate at the call site guarantees it).
  final int jobsNeeded;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final double progress =
        (jobsCompleted / _minJobsForScore).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.trending_up_rounded,
              size: 28,
              color: palette.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Building your credit score',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            jobsCompleted == 0
                ? 'Your score will appear here once you have a record '
                    'we can evaluate. Complete $_minJobsForScore jobs to '
                    'unlock it.'
                : '$jobsCompleted of $_minJobsForScore jobs done — '
                    '${jobsNeeded == 1 ? 'one more job' : '$jobsNeeded more jobs'} '
                    'to unlock your score.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              valueColor:
                  AlwaysStoppedAnimation<Color>(palette.primary),
              backgroundColor: palette.surfaceContainerHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitleLine extends StatelessWidget {
  const _SubtitleLine({required this.score, this.serverSubtitle});
  final int score;

  /// Server-rendered, locale-aware copy from `GET /me/credit`. When
  /// present we render it verbatim — the AI scorer is the source of
  /// truth. Falls back to the legacy local table only if the
  /// endpoint hasn't shipped or returned an empty string.
  final String? serverSubtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fromServer = serverSubtitle?.trim();
    final subtitle = (fromServer != null && fromServer.isNotEmpty)
        ? fromServer
        : score < 60
            ? 'Building — keep working to grow your score.'
            : score < 70
                ? "Fair — almost there. Eligibility unlocks at 70."
                : score < 85
                    ? 'Good — keep working to qualify for higher amounts.'
                    : 'Excellent — you have access to our best loan terms.';
    return Center(
      child: Text(
        subtitle,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium.copyWith(
          color: palette.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Quiet "Updated 5 minutes ago · model v2.3" line under the subtitle.
/// Renders only when the server returned `last_evaluated_at`.
class _LastEvaluatedLine extends StatelessWidget {
  const _LastEvaluatedLine({required this.at, this.modelVersion});
  final DateTime at;
  final String? modelVersion;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ago = _relative(DateTime.now().difference(at));
    final tail = (modelVersion == null || modelVersion!.isEmpty)
        ? ''
        : ' · $modelVersion';
    return Center(
      child: Text(
        'Updated $ago$tail',
        style: AppTextStyles.labelSmall.copyWith(
          color: palette.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static String _relative(Duration d) {
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) {
      return '${d.inMinutes} min${d.inMinutes == 1 ? '' : 's'} ago';
    }
    if (d.inHours < 24) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
    }
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }
}

/// "What's pulling your score down" block — server-emitted risk
/// factors, render-only. Each row carries server-tuned copy and an
/// optional score-impact ("−4") chip.
class _RiskFactorsBlock extends StatelessWidget {
  const _RiskFactorsBlock({required this.factors});
  final List<CreditRiskFactor> factors;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          "What's pulling your score down",
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (int i = 0; i < factors.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _RiskFactorRow(factor: factors[i]),
        ],
      ],
    );
  }
}

class _RiskFactorRow extends StatelessWidget {
  const _RiskFactorRow({required this.factor});
  final CreditRiskFactor factor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = switch (factor.severity) {
      'high' => palette.error,
      'medium' => palette.warning,
      _ => palette.onSurfaceVariant,
    };
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(_iconFor(factor.code), size: 18, color: tint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              factor.copy,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurface,
              ),
            ),
          ),
          if (factor.scoreImpact != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '${factor.scoreImpact}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(String code) {
    switch (code) {
      case 'low_on_time_rate':
      case 'recent_no_show':
        return Icons.schedule_rounded;
      case 'low_completion_rate':
        return Icons.cancel_rounded;
      case 'wallet_drain':
        return Icons.water_drop_rounded;
      case 'prior_default':
      case 'recent_loan_late_repayment':
        return Icons.report_rounded;
      case 'low_tenure':
        return Icons.hourglass_bottom_rounded;
      case 'recent_rating_drop':
        return Icons.star_outline_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }
}

/// "Lift your score" block — concrete actions the model recommends.
/// Tappable when the server attached a `forge://` deeplink.
class _ImprovementActionsBlock extends StatelessWidget {
  const _ImprovementActionsBlock({required this.actions});
  final List<CreditImprovementAction> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Lift your score',
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _ImprovementRow(action: actions[i]),
        ],
      ],
    );
  }
}

class _ImprovementRow extends StatelessWidget {
  const _ImprovementRow({required this.action});
  final CreditImprovementAction action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasDeeplink =
        action.deeplink != null && action.deeplink!.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      onTap: hasDeeplink ? () => _handleTap(context, action.deeplink!) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.trending_up_rounded,
              size: 18,
              color: palette.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              action.copy,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurface,
              ),
            ),
          ),
          if (action.scoreLift != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '+${action.scoreLift}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (hasDeeplink) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: palette.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }

  static void _handleTap(BuildContext context, String deeplink) {
    // `forge://jobs` style. Map the host segment to the in-app
    // routes we already own. Unknown deeplinks no-op rather than
    // throwing — server might emit one we don't ship yet.
    final uri = Uri.tryParse(deeplink);
    if (uri == null || uri.scheme != 'forge') return;
    final segments = <String>[uri.host, ...uri.pathSegments]
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return;
    final target = switch (segments.first) {
      'jobs' => RoutePaths.jobs,
      'earnings' => RoutePaths.earnings,
      'loans' => RoutePaths.loans,
      'profile' => RoutePaths.profile,
      _ => null,
    };
    if (target != null) context.go(target);
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.worker, this.signals});
  final Worker worker;

  /// AI-input snapshot from `GET /me/credit`. Optional — if the
  /// endpoint is on the older shape we fall back to the worker
  /// fields. When present we render the model's exact inputs so the
  /// numbers match what scored the worker.
  final CreditSignals? signals;

  @override
  Widget build(BuildContext context) {
    // Tenure: prefer the server's days count (matches the model
    // input), else compute from joinedAt.
    final tenureDays = signals?.tenureDays ??
        DateTime.now().difference(worker.joinedAt).inDays;
    final tenureMonths = tenureDays ~/ 30;

    // On-time rate: AI signal is 0.0–1.0 fraction; worker.reliabilityScore
    // is the legacy 0–100. Prefer signal when present.
    final onTimePct = signals?.onTimeRate != null
        ? (signals!.onTimeRate * 100).round()
        : worker.reliabilityScore;

    final jobsCompleted = signals?.jobsCompleted ?? worker.jobsCompleted;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: <Widget>[
        _StatTile(
          icon: Icons.work_rounded,
          label: 'Jobs completed',
          value: jobsCompleted.toString(),
        ),
        _StatTile(
          icon: Icons.check_circle_rounded,
          label: 'On-time rate',
          // Showing "100%" before any job has been completed is
          // misleading — there's nothing to be on-time for. Em-dash
          // until the first job lands.
          value: jobsCompleted == 0 ? '—' : '$onTimePct%',
        ),
        _StatTile(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Total earned',
          value: '₦${_formatCompact(worker.totalEarned)}',
        ),
        _StatTile(
          icon: Icons.calendar_today_rounded,
          label: 'On platform',
          value: tenureMonths >= 1 ? '$tenureMonths mo' : '<1 mo',
        ),
      ],
    );
  }

  static String _formatCompact(int amount) {
    if (amount < 1000) return amount.toString();
    if (amount < 1000000) {
      return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k';
    }
    return '${(amount / 1000000).toStringAsFixed(1)}m';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: palette.primary),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleLarge.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Eligibility (no active loan)
// ---------------------------------------------------------------------

class _EligibilityCard extends StatelessWidget {
  const _EligibilityCard({required this.worker, this.credit});
  final Worker worker;

  /// AI-evaluated credit profile. When present we read
  /// `eligibility.is_eligible` + `eligibility.max_principal` directly —
  /// the server is authoritative. Falls back to the legacy
  /// score-keyed table only when the credit endpoint hasn't loaded.
  final CreditProfile? credit;

  /// Server-authoritative ceiling, or null when not eligible.
  int? eligibilityCeiling() {
    final c = credit;
    if (c != null) {
      return c.eligibility.isEligible ? c.eligibility.maxPrincipal : null;
    }
    // Legacy fallback (v1 thresholds, kept defensively for the
    // moment the endpoint is unreachable on first paint).
    final s = worker.creditScore;
    if (s >= 80) return 100000;
    if (s >= 70) return 50000;
    return null;
  }

  /// Jobs to unlock — prefer the AI estimate (`next_unlock`), else
  /// rough-derive from the score gap.
  int jobsToUnlock() {
    final c = credit;
    if (c?.nextUnlock != null) return c!.nextUnlock!.jobsToUnlockEstimate;
    final s = worker.creditScore;
    if (s >= 70) return 0;
    final pointsNeeded = 70 - s;
    return (pointsNeeded / 3).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ceiling = eligibilityCeiling();
    final notYet = ceiling == null;

    if (notYet) {
      final jobsNeeded = jobsToUnlock();
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        background: palette.surfaceContainerHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.lock_rounded,
                    size: 20, color: palette.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Not yet eligible',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Complete $jobsNeeded more job${jobsNeeded == 1 ? '' : 's'} '
              'to unlock loans.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (worker.jobsCompleted % 3) / 3,
                valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                backgroundColor: palette.outlineVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Apply for a loan',
                onPressed: null,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      background: palette.primaryContainer,
      borderColor: palette.primary.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.workspace_premium_rounded,
                  size: 20, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                "You're eligible",
                style: AppTextStyles.titleMedium.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Borrow up to',
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          CurrencyText(amount: ceiling, size: CurrencySize.medium),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Apply for a loan',
            onPressed: () => context.push(RoutePaths.loanApply),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Active loan
// ---------------------------------------------------------------------

class _ActiveLoanCard extends StatelessWidget {
  const _ActiveLoanCard({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final perJob = (loan.principal * loan.repaymentPercentPerJob).round();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.primary.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'OUTSTANDING',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.primary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppTextButton(
                label: 'View details',
                dense: true,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () =>
                    context.push(RoutePaths.loanDetail(loan.id)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CurrencyText(
            amount: loan.outstandingBalance,
            size: CurrencySize.large,
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: loan.progressFraction,
              valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
              backgroundColor: palette.outlineVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '${(loan.progressFraction * 100).round()}% repaid',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              Text(
                'of ₦${(loan.principal ~/ 1000)}k',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.bolt_rounded,
                    size: 18, color: palette.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurface,
                      ),
                      children: <InlineSpan>[
                        const TextSpan(text: 'Next payment: '),
                        TextSpan(
                          text: '₦$perJob',
                          style: TextStyle(
                            color: palette.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ' deducted on your next job.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepaymentHistory extends StatelessWidget {
  const _RepaymentHistory({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Repayment history',
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < loan.repayments.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: palette.outlineVariant,
                    indent: AppSpacing.lg,
                  ),
                _RepaymentRow(repayment: loan.repayments[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RepaymentRow extends StatelessWidget {
  const _RepaymentRow({required this.repayment});
  final LoanRepayment repayment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.success.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.check_rounded,
                size: 18, color: palette.success),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Auto-deducted',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatRelative(repayment.paidAt),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          CurrencyText(
            amount: -repayment.amount,
            size: CurrencySize.small,
            tone: CurrencyTone.debit,
            signed: true,
          ),
        ],
      ),
    );
  }

  static String _formatRelative(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inDays >= 7) return '${delta.inDays ~/ 7}w ago';
    if (delta.inDays >= 1) return '${delta.inDays}d ago';
    if (delta.inHours >= 1) return '${delta.inHours}h ago';
    return '${delta.inMinutes}m ago';
  }
}

// ---------------------------------------------------------------------
// Skeletons
// ---------------------------------------------------------------------

/// Body-only skeleton — the pinned [SliverAppBar] already renders the
/// "Loans" title above this, so we don't repeat it here.
class _LoansLoadingSkeleton extends StatelessWidget {
  const _LoansLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: LoadingShimmer.circle(size: 220)),
          SizedBox(height: AppSpacing.xl),
          LoadingShimmer.line(width: 220, height: 18),
          SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(child: LoadingShimmer.box(width: 0, height: 88)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: LoadingShimmer.box(width: 0, height: 88)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveLoanSkeleton extends StatelessWidget {
  const _ActiveLoanSkeleton();

  @override
  Widget build(BuildContext context) =>
      const LoadingShimmer.box(width: double.infinity, height: 200);
}
