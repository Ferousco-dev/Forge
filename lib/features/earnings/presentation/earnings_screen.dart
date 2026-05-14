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
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/primary_button.dart';
import '../widgets/transaction_list_item.dart';

/// Earnings tab — wallet balance hero + stats + transactions list.
///
/// The "Earnings" title is a pinned [SliverAppBar]: it stays put while
/// the body scrolls underneath, matching iOS Wallet's anchored header.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  /// How many transactions to preview on the home screen before the
  /// "View all" link kicks in. Picked to fit comfortably above the
  /// bottom nav without dominating the page.
  static const int _previewCount = 10;

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(currentWorkerProvider)
      ..invalidate(transactionsProvider);
    await Future.wait<dynamic>(<Future<dynamic>>[
      ref.read(currentWorkerProvider.future),
      ref.read(transactionsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);
    final txAsync = ref.watch(transactionsProvider);
    // HomeShell injects the bottom-nav height + system gesture inset
    // into MediaQuery.padding so child scrollables can keep their last
    // item clear of the floating nav bar. We use SafeArea(bottom: false)
    // to avoid double-applying it on the SafeArea boundary, then add
    // it manually as the bottom of the SliverPadding.
    final navInset = MediaQuery.paddingOf(context).bottom;

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
                  'Earnings',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg + navInset,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(<Widget>[
                    _WalletHero(workerAsync: workerAsync),
                    const SizedBox(height: AppSpacing.lg),
                    _StatsRow(txAsync: txAsync, workerAsync: workerAsync),
                    const SizedBox(height: AppSpacing.xl),
                    _TransactionsHeader(txAsync: txAsync),
                    const SizedBox(height: AppSpacing.sm),
                    _TransactionsSection(
                      asyncList: txAsync,
                      ref: ref,
                      previewCount: _previewCount,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Hero — wallet balance
// ---------------------------------------------------------------------

class _WalletHero extends StatelessWidget {
  const _WalletHero({required this.workerAsync});
  final AsyncValue<Worker> workerAsync;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.primary.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 18,
                color: palette.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'WALLET BALANCE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.primary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          workerAsync.when(
            loading: () => const LoadingShimmer.box(width: 220, height: 44),
            error: (Object _, StackTrace _) => Text(
              '—',
              style: AppTextStyles.currencyLarge.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            data: (Worker w) => CurrencyText(
              amount: w.walletBalance,
              size: CurrencySize.large,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Withdraw',
            icon: const Icon(Icons.arrow_outward_rounded),
            onPressed: () => context.push(RoutePaths.withdraw),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Stats row — This week / This month / All time
// ---------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.txAsync, required this.workerAsync});
  final AsyncValue<List<Transaction>> txAsync;
  final AsyncValue<Worker> workerAsync;

  int _sumCreditsSince(List<Transaction> txs, DateTime since) {
    return txs
        .where((Transaction t) =>
            t.kind == TransactionKind.jobPayment &&
            t.timestamp.isAfter(since))
        .fold<int>(0, (int sum, Transaction t) => sum + t.amount);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisWeek = now.subtract(const Duration(days: 7));
    final thisMonth = now.subtract(const Duration(days: 30));

    final week = txAsync.maybeWhen(
      data: (List<Transaction> ts) => _sumCreditsSince(ts, thisWeek),
      orElse: () => null,
    );
    final month = txAsync.maybeWhen(
      data: (List<Transaction> ts) => _sumCreditsSince(ts, thisMonth),
      orElse: () => null,
    );
    final allTime = workerAsync.maybeWhen(
      data: (Worker w) => w.totalEarned,
      orElse: () => null,
    );

    return Row(
      children: <Widget>[
        Expanded(
          child: _StatCard(label: 'This week', amount: week),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(label: 'This month', amount: month),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(label: 'All time', amount: allTime),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.amount});

  final String label;
  final int? amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (amount == null)
            const LoadingShimmer.line(width: 70, height: 16)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CurrencyText(amount: amount!, size: CurrencySize.small),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Transactions section
// ---------------------------------------------------------------------

/// Title row with the "View all" link on the right. The link only
/// appears when there are more than [EarningsScreen._previewCount]
/// transactions to view — otherwise the preview already shows them all.
class _TransactionsHeader extends StatelessWidget {
  const _TransactionsHeader({required this.txAsync});
  final AsyncValue<List<Transaction>> txAsync;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasMore = txAsync.maybeWhen(
      data: (List<Transaction> ts) =>
          ts.length > EarningsScreen._previewCount,
      orElse: () => false,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            'Recent transactions',
            style: AppTextStyles.titleLarge.copyWith(
              color: palette.onSurface,
            ),
          ),
        ),
        if (hasMore)
          AppTextButton(
            label: 'View all',
            dense: true,
            onPressed: () => context.push(RoutePaths.transactions),
          ),
      ],
    );
  }
}

class _TransactionsSection extends StatelessWidget {
  const _TransactionsSection({
    required this.asyncList,
    required this.ref,
    required this.previewCount,
  });
  final AsyncValue<List<Transaction>> asyncList;
  final WidgetRef ref;
  final int previewCount;

  @override
  Widget build(BuildContext context) {
    return asyncList.when(
      loading: () => Column(
        children: List<Widget>.generate(
          5,
          (_) => const TransactionListItemSkeleton(),
        ),
      ),
      error: (Object _, StackTrace _) => ErrorStateView(
        title: "Couldn't load transactions",
        message: "Try again — your earnings record is safe.",
        onRetry: () => ref.invalidate(transactionsProvider),
      ),
      data: (List<Transaction> txs) {
        if (txs.isEmpty) {
          return const EmptyStateView(
            title: 'No earnings yet',
            subtitle:
                "Your earnings will appear here after your first job.",
            illustration: Icon(
              Icons.payments_outlined,
              size: 56,
            ),
          );
        }
        final preview = txs.length > previewCount
            ? txs.sublist(0, previewCount)
            : txs;
        return Column(
          children: <Widget>[
            for (final Transaction t in preview)
              TransactionListItem(
                transaction: t,
                onTap: () => context.push(
                  RoutePaths.transactionDetail(t.id),
                ),
              ),
          ],
        );
      },
    );
  }
}
