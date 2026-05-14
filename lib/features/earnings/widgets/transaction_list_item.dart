import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/loading_shimmer.dart';

/// One row in the earnings transaction list.
///
/// Layout: leading circular icon (kind-driven) · title + subtitle stack ·
/// trailing currency. Tap-targets are 56dp tall (the brief mandates ≥48dp;
/// a touch more breathing room helps for older-adult users).
class TransactionListItem extends StatelessWidget {
  const TransactionListItem({
    super.key,
    required this.transaction,
    this.onTap,
  });

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              _LeadingIcon(kind: transaction.kind, isCredit: transaction.isCredit),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      transaction.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSubtitle(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              CurrencyText(
                amount: transaction.amount,
                size: CurrencySize.small,
                tone: transaction.isCredit
                    ? CurrencyTone.credit
                    : CurrencyTone.debit,
                signed: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSubtitle(Transaction t) {
    final time = DateFormat('MMM d · h:mm a').format(t.timestamp.toLocal());
    return '${t.subtitle} · $time';
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.kind, required this.isCredit});

  final TransactionKind kind;
  final bool isCredit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (IconData icon, Color tint) = _stylesFor(palette);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: tint),
    );
  }

  (IconData, Color) _stylesFor(dynamic palette) {
    switch (kind) {
      case TransactionKind.jobPayment:
        return (Icons.work_rounded, palette.success as Color);
      case TransactionKind.loanDisbursement:
        return (Icons.south_west_rounded, palette.info as Color);
      case TransactionKind.loanRepayment:
        return (Icons.north_east_rounded, palette.warning as Color);
      case TransactionKind.withdrawal:
        return (
          Icons.account_balance_rounded,
          palette.onSurfaceVariant as Color,
        );
    }
  }
}

/// Skeleton row used while [transactionsProvider] resolves. Same vertical
/// rhythm as [TransactionListItem] so the layout doesn't jump on data
/// arrival.
class TransactionListItemSkeleton extends StatelessWidget {
  const TransactionListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          LoadingShimmer.circle(size: 40),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LoadingShimmer.line(width: 160, height: 14),
                SizedBox(height: 6),
                LoadingShimmer.line(width: 220, height: 11),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          LoadingShimmer.box(width: 84, height: 18),
        ],
      ),
    );
  }
}
