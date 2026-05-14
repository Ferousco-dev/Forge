import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../data/wallet_repository.dart';

/// Payload passed via GoRouter's `extra` from [WithdrawScreen] after a
/// successful `POST /wallet/withdrawals`. Carries everything needed to
/// render the receipt without re-fetching the server — the same shape
/// the wallet API just gave us, just bundled.
class WithdrawReceiptArgs {
  const WithdrawReceiptArgs({
    required this.result,
    required this.preview,
  });

  /// Server's response to the submit call. Contains the new transaction
  /// row + post-debit wallet balance.
  final WithdrawalResult result;

  /// Preview that the worker confirmed. Carries the destination bank
  /// + last-4 + ETA copy, which the bare [WithdrawalResult] doesn't
  /// guarantee.
  final WithdrawalPreview preview;
}

/// Withdrawal receipt — the "where did my money go" answer.
///
/// Replaces the prior 4-second snackbar with a screen that sticks
/// around: destination bank, masked account, amount debited, fee,
/// reference number, ETA. Shows the worker the paper trail before
/// the actual `/transactions` row finishes propagating server-side.
class WithdrawReceiptScreen extends ConsumerWidget {
  const WithdrawReceiptScreen({super.key, required this.args});
  final WithdrawReceiptArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    final a = args;
    if (a == null) {
      // Deeplinked / refreshed without state — nothing to render. Bounce
      // back to earnings rather than a blank screen.
      return Scaffold(
        backgroundColor: palette.surface,
        appBar: AppBar(
          title: const Text('Withdrawal'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go(RoutePaths.earnings),
          ),
        ),
        body: const SafeArea(
          child: EmptyStateView(
            title: 'No receipt to show',
            subtitle: 'Open this from a fresh withdrawal.',
          ),
        ),
      );
    }

    final tx = a.result.transaction;
    final preview = a.preview;
    final amount = preview.amount;
    final destination =
        '${preview.destinationBank} · ****${preview.destinationLast4}';

    return PopScope(
      // Don't let the worker back-swipe to the preview / amount entry —
      // the transaction is done. Forward them to earnings instead.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) context.go(RoutePaths.earnings);
      },
      child: Scaffold(
        backgroundColor: palette.surface,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
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
                      _SuccessHero(amount: amount),
                      const SizedBox(height: AppSpacing.xl),
                      _DestinationCard(
                        bank: preview.destinationBank,
                        last4: preview.destinationLast4,
                        accountName: preview.destinationAccountName,
                        eta: preview.estimatedArrival,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _DetailsCard(
                        amount: amount,
                        fee: preview.fee,
                        amountCredited: preview.amountCredited,
                        reference: tx.squadReference,
                        timestamp: tx.timestamp.toLocal(),
                        destination: destination,
                        walletBalanceAfter: a.result.walletBalanceAfter,
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    children: <Widget>[
                      PrimaryButton(
                        label: 'Done',
                        onPressed: () {
                          // Force the transactions list to re-fetch so
                          // the new row lands the moment we return. The
                          // submit handler already invalidated it; we
                          // re-invalidate here in case the worker sat on
                          // this screen long enough for the cache to
                          // become stale.
                          ref.invalidate(transactionsProvider);
                          ref.invalidate(currentWorkerProvider);
                          context.go(RoutePaths.earnings);
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryButton(
                        label: 'View in transactions',
                        onPressed: () => context.go(
                          RoutePaths.transactionDetail(tx.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  const _SuccessHero({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: palette.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_circle_rounded,
            size: 56,
            color: palette.success,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Withdrawal sent',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        CurrencyText(
          amount: amount,
          size: CurrencySize.large,
          tone: CurrencyTone.debit,
        ),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.bank,
    required this.last4,
    required this.accountName,
    required this.eta,
  });

  final String bank;
  final String last4;
  final String accountName;
  final String eta;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      borderColor: palette.primary.withValues(alpha: 0.25),
      background: palette.primary.withValues(alpha: 0.05),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_balance_rounded,
              size: 22,
              color: palette.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Sent to',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$bank · ****$last4',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (accountName.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    accountName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
                if (eta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.flash_on_rounded,
                        size: 12,
                        color: palette.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          eta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.amount,
    required this.fee,
    required this.amountCredited,
    required this.reference,
    required this.timestamp,
    required this.destination,
    required this.walletBalanceAfter,
  });

  final int amount;
  final int fee;
  final int amountCredited;
  final String? reference;
  final DateTime timestamp;
  final String destination;
  final int walletBalanceAfter;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final timestampFmt = DateFormat('MMM d, y · h:mm a').format(timestamp);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Row(label: 'Amount', value: _ngn(amount)),
          if (fee > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _Row(label: 'Fee', value: _ngn(fee)),
            const SizedBox(height: AppSpacing.sm),
            _Row(
              label: 'Credited',
              value: _ngn(amountCredited),
              emphasised: true,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          _Row(
            label: 'Reference',
            // Squad's reference is the worker's trace number for any
            // future bank-side dispute. Surface it verbatim — copying
            // is enough; we don't need a dedicated copy affordance for
            // a hackathon build.
            value: (reference == null || reference!.isEmpty)
                ? '—'
                : reference!,
            monospaced: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(label: 'When', value: timestampFmt),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            label: 'Wallet balance',
            value: _ngn(walletBalanceAfter),
          ),
        ],
      ),
    );
  }

  static String _ngn(int amount) {
    final fmt = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    return fmt.format(amount);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasised = false,
    this.monospaced = false,
  });

  final String label;
  final String value;
  final bool emphasised;
  final bool monospaced;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final valueStyle = (emphasised
            ? AppTextStyles.titleSmall
            : AppTextStyles.bodyMedium)
        .copyWith(
      color: palette.onSurface,
      fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
      fontFeatures: monospaced
          ? const <FontFeature>[FontFeature.tabularFigures()]
          : null,
    );
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
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}
