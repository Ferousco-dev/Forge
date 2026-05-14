import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Naira amount, consistently formatted.
///
/// Three sizes match [AppTextStyles.currency*]. Negative amounts render
/// with a leading minus and inherit [palette.error] unless [color] is set.
/// Positive amounts inherit [color] or [palette.onSurface].
///
/// Always uses tabular figures (set in the underlying text styles) so
/// columns of amounts in the transactions list align cleanly.
enum CurrencySize { small, medium, large }

class CurrencyText extends StatelessWidget {
  const CurrencyText({
    super.key,
    required this.amount,
    this.size = CurrencySize.medium,
    this.color,
    this.signed = false,
    this.tone,
    this.maxLines = 1,
  });

  /// Amount in **kobo-free Naira integer units** (e.g., 5000 = ₦5,000).
  final int amount;

  final CurrencySize size;

  /// Optional explicit color. Wins over [tone].
  final Color? color;

  /// When `true`, prepend `+` for positive amounts (debits already
  /// render with `-`). Useful for transaction lists.
  final bool signed;

  /// Semantic tone — `null` (default), `credit` (success green),
  /// `debit` (error red). Ignored if [color] is set.
  final CurrencyTone? tone;

  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final TextStyle baseStyle;
    switch (size) {
      case CurrencySize.small:
        baseStyle = AppTextStyles.currencySmall;
      case CurrencySize.medium:
        baseStyle = AppTextStyles.currencyMedium;
      case CurrencySize.large:
        baseStyle = AppTextStyles.currencyLarge;
    }

    final Color resolved = color ??
        switch (tone) {
          CurrencyTone.credit => palette.success,
          CurrencyTone.debit => palette.error,
          null => palette.onSurface,
        };

    final formatter = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );

    final isNegative = amount < 0;
    final magnitude = amount.abs();
    final formatted = formatter.format(magnitude);
    final display = isNegative
        ? '-$formatted'
        : signed
            ? '+$formatted'
            : formatted;

    return Text(
      display,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: baseStyle.copyWith(color: resolved),
      semanticsLabel: '$display naira',
    );
  }
}

enum CurrencyTone { credit, debit }
