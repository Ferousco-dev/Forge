import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../widgets/transaction_list_item.dart';

/// Full transaction history. Reachable from the "View all" link on the
/// Earnings home — the home keeps a recent-10 preview, this page shows
/// the entire ledger.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final txAsync = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: const BackButtonHeader(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'All transactions',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: palette.onSurface,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(transactionsProvider);
                  await ref.read(transactionsProvider.future);
                },
                child: txAsync.when(
                  loading: () => ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    itemCount: 8,
                    itemBuilder: (BuildContext _, int _) =>
                        const TransactionListItemSkeleton(),
                  ),
                  error: (Object _, StackTrace _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      const SizedBox(height: AppSpacing.xxl),
                      ErrorStateView(
                        title: "Couldn't load transactions",
                        message: "Try again — your earnings record is safe.",
                        onRetry: () =>
                            ref.invalidate(transactionsProvider),
                      ),
                    ],
                  ),
                  data: (List<Transaction> txs) {
                    if (txs.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const <Widget>[
                          SizedBox(height: AppSpacing.xxl),
                          EmptyStateView(
                            title: 'No transactions yet',
                            subtitle:
                                "Your earnings will appear here after your first job.",
                            illustration: Icon(
                              Icons.payments_outlined,
                              size: 56,
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      itemCount: txs.length,
                      itemBuilder: (BuildContext context, int i) {
                        final t = txs[i];
                        return TransactionListItem(
                          transaction: t,
                          onTap: () => context.push(
                            RoutePaths.transactionDetail(t.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
