import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/status_badge.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});
  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final asyncTx = ref.watch(transactionByIdProvider(transactionId));

    return Scaffold(
      backgroundColor: palette.surface,
      body: asyncTx.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => SafeArea(
          child: Column(
            children: <Widget>[
              const BackButtonHeader(),
              Expanded(
                child: ErrorStateView(
                  title: "Couldn't load this transaction",
                  message: 'Try again — the record is safe.',
                  onRetry: () => ref.invalidate(
                    transactionByIdProvider(transactionId),
                  ),
                ),
              ),
            ],
          ),
        ),
        data: (Transaction t) => _Body(transaction: t),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.transaction});
  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final dateFormat = DateFormat('EEE, MMM d, yyyy · h:mm a');

    return SafeArea(
      child: Column(
        children: <Widget>[
          const BackButtonHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Hero amount.
                  Center(
                    child: Column(
                      children: <Widget>[
                        Text(
                          transaction.kind.label,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: palette.onSurfaceVariant,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CurrencyText(
                          amount: transaction.amount,
                          size: CurrencySize.large,
                          tone: transaction.isCredit
                              ? CurrencyTone.credit
                              : CurrencyTone.debit,
                          signed: true,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const StatusBadge(
                          label: 'Completed',
                          tone: StatusBadgeTone.success,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Transaction details.
                  Text(
                    'Transaction details',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    child: Column(
                      children: <Widget>[
                        _DetailLine(
                          label: 'Date',
                          value: dateFormat
                              .format(transaction.timestamp.toLocal()),
                        ),
                        Divider(height: AppSpacing.lg, color: palette.outlineVariant),
                        _DetailLine(
                          label: 'Title',
                          value: transaction.title,
                        ),
                        Divider(height: AppSpacing.lg, color: palette.outlineVariant),
                        _DetailLine(
                          label: 'Description',
                          value: transaction.subtitle,
                        ),
                        if (transaction.squadReference != null) ...<Widget>[
                          Divider(
                            height: AppSpacing.lg,
                            color: palette.outlineVariant,
                          ),
                          _SquadReferenceLine(
                            reference: transaction.squadReference!,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Work summary + verification checklist. Job payments
                  // are the only kind tied to a verifiable session, so
                  // gate on `relatedJobId`. Both sections render from
                  // data the transaction itself carries — they don't
                  // re-fetch the live job listing, which 404s once the
                  // listing is filled (the bug a worker hit when they
                  // saw "Job no longer available" on the receipt for a
                  // job they'd just completed).
                  if (transaction.relatedJobId != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Work details',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _WorkSummaryCard(
                      summary: transaction.relatedJobSummary,
                      fallbackSubtitle: transaction.subtitle,
                      employerName: transaction.title,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Verified by',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _VerificationChecklist(),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                  // Footer links — Wrap so they break to two lines on
                  // narrow screens instead of overflowing.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: <Widget>[
                      AppTextButton(
                        label: 'View receipt',
                        icon: const Icon(Icons.receipt_long_rounded),
                        onPressed: () {},
                      ),
                      AppTextButton(
                        label: 'Report issue',
                        icon: const Icon(Icons.flag_outlined),
                        color: palette.onSurfaceVariant,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
          width: 110,
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
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SquadReferenceLine extends StatelessWidget {
  const _SquadReferenceLine({required this.reference});
  final String reference;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(
            'Squad reference',
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            reference,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w500,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy reference',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: reference));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(AppSpacing.base),
                backgroundColor: palette.surfaceContainerHigh,
                content: Text(
                  'Reference copied.',
                  style: TextStyle(color: palette.onSurface),
                ),
              ));
          },
          icon: Icon(Icons.copy_rounded,
              size: 18, color: palette.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Resilient work-summary card.
///
/// Renders everything the worker needs to identify the job from the
/// transaction itself — never from a live job fetch. The original
/// version called `jobByIdProvider` and rendered "Job no longer
/// available" the moment the listing closed, which is the bug a
/// worker hit when they opened a transaction for a job they'd
/// already completed.
///
/// Priority order:
///   1. `RelatedJobSummary` shipped on the transaction-detail
///      response — preferred because it's the server's curated
///      snapshot at payout time.
///   2. The transaction's own `subtitle` (e.g. "loader · Mercy of God
///      hostel 16") which the list rendering already trusts.
class _WorkSummaryCard extends StatelessWidget {
  const _WorkSummaryCard({
    required this.summary,
    required this.fallbackSubtitle,
    required this.employerName,
  });

  final RelatedJobSummary? summary;

  /// The transaction's own `subtitle` line — already in the form
  /// `[job kind] · [location]`. Used when [summary] isn't available.
  final String fallbackSubtitle;

  /// The transaction's `title` (employer name for job payments). Used
  /// as a footer line when we have a [summary] so the worker can see
  /// both the job and the employer in one card.
  final String employerName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = summary;
    if (s == null) {
      // No structured summary — render the transaction's existing
      // subtitle. Better than nothing and matches what the worker
      // already saw on the earnings list.
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: <Widget>[
            _IconBadge(
              icon: Icons.work_outline_rounded,
              tint: palette.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                fallbackSubtitle,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconBadge(
                icon: Icons.work_outline_rounded,
                tint: palette.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.type.label} · ${s.durationHours}h',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          _SummaryRow(
            icon: Icons.location_on_outlined,
            label: s.locationAddress,
          ),
          if (employerName.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(
              icon: Icons.business_rounded,
              label: employerName,
            ),
          ],
          if (s.completedAt != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(
              icon: Icons.event_available_rounded,
              label: DateFormat('EEE, MMM d · h:mm a')
                  .format(s.completedAt!.toLocal()),
            ),
          ],
        ],
      ),
    );
  }
}

/// Static three-row checklist. Once payment is disbursed the server has
/// already cleared photo, location, and time verification — those
/// can't change after the fact. Rendering them server-blind keeps the
/// section honest even when the live job listing is gone.
class _VerificationChecklist extends StatelessWidget {
  const _VerificationChecklist();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: <Widget>[
          _ChecklistRow(label: 'Photo proof'),
          SizedBox(height: AppSpacing.sm),
          _ChecklistRow(label: 'Location verified'),
          SizedBox(height: AppSpacing.sm),
          _ChecklistRow(label: 'Time on the job verified'),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: <Widget>[
        Icon(
          Icons.check_circle_rounded,
          size: 20,
          color: palette.success,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: palette.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurface,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: tint, size: 20),
    );
  }
}
