import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../data/wallet_repository.dart';
import '../state/earnings_state.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import 'withdraw_receipt_screen.dart';

/// Withdraw — Squad-powered, server-routed.
///
/// Two-step flow:
///   1. Amount entry. "Continue" calls `GET /wallet/withdrawals/preview`
///      so the worker can see the destination bank, masked account,
///      fee, and ETA *before* confirming.
///   2. Confirmation sheet. "Confirm withdrawal" calls
///      `POST /wallet/withdrawals`; on success we route to the receipt
///      screen so the worker has a persistent record of where the
///      money went — replaces the prior 4-second snackbar.
///
/// If the worker has no linked bank account, we render a "link your
/// bank first" state instead of the amount field. Squad's
/// server-managed wallet may have a fallback destination, but the
/// product flow requires an explicit personal bank — withdrawal
/// always lands in the worker's own account.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final TextEditingController _amount = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _previewing = false;
  String? _error;

  /// Stable per-attempt id. Minted on the first submit; reused on
  /// every retry so the server's idempotency cache returns the same
  /// transaction instead of double-debiting. Reset only when the user
  /// edits the amount — that signals a new logical withdrawal.
  String? _attemptId;

  @override
  void dispose() {
    _amount.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _amountValue => int.tryParse(_amount.text) ?? 0;

  bool _validate(int balance) {
    String? err;
    if (_amountValue <= 0) {
      err = 'Enter how much to withdraw.';
    } else if (_amountValue > balance) {
      err = "You can't withdraw more than your wallet balance.";
    } else if (_amountValue < 500) {
      err = 'Minimum withdrawal is ₦500.';
    }
    setState(() => _error = err);
    return err == null;
  }

  void _setAmount(int v) {
    _amount.text = v.toString();
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    if (_error != null) setState(() => _error = null);
    // New amount = new logical withdrawal — drop any cached attempt id.
    _attemptId = null;
  }

  /// Fetch the preview, then open the confirmation sheet. The submit
  /// call only fires once the user explicitly taps "Confirm" from the
  /// sheet — so a wrong-button-press in the amount field can't cost
  /// the worker money.
  Future<void> _openPreviewSheet(int balance) async {
    _focusNode.unfocus();
    if (!_validate(balance)) return;
    setState(() {
      _previewing = true;
      _error = null;
    });

    WithdrawalPreview preview;
    try {
      preview = await ref
          .read(walletRepositoryProvider)
          .previewWithdrawal(amount: _amountValue);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _error = "Couldn't reach the bank — try again.";
      });
      return;
    }

    if (!mounted) return;
    setState(() => _previewing = false);

    _attemptId ??= const Uuid().v4();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl + 4),
        ),
      ),
      builder: (BuildContext sheetContext) => _PreviewSheet(
        preview: preview,
        attemptId: _attemptId!,
        onSuccess: (WithdrawalResult result) {
          // Invalidate eagerly so the earnings tab refreshes the
          // moment we route away. The receipt screen also re-invalidates
          // on its Done button to catch backends that commit slowly.
          ref
            ..invalidate(currentWorkerProvider)
            ..invalidate(transactionsProvider);
          _attemptId = null;
          Navigator.of(sheetContext).pop();
          context.pushReplacement(
            RoutePaths.withdrawReceipt,
            extra: WithdrawReceiptArgs(
              result: result,
              preview: preview,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);
    final banksAsync = ref.watch(bankAccountsProvider);

    final balance = workerAsync.maybeWhen(
      data: (Worker w) => w.walletBalance,
      orElse: () => 0,
    );

    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool kbOpen = keyboardInset > 0;

    final defaultBank = banksAsync.maybeWhen(
      data: (List<BankAccount> banks) {
        if (banks.isEmpty) return null;
        for (final BankAccount b in banks) {
          if (b.isDefault) return b;
        }
        return banks.first;
      },
      orElse: () => null,
    );

    final bool banksLoaded = banksAsync.hasValue;
    final bool noBankLinked = banksLoaded && defaultBank == null;

    return Scaffold(
      backgroundColor: palette.surface,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // Top bar.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const BackButtonHeader(),
                  Expanded(
                    child: Text(
                      'Withdraw',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: noBankLinked
                    ? const _NoBankLinkedBody()
                    : _AmountEntryBody(
                        amount: _amount,
                        focusNode: _focusNode,
                        errorText: _error,
                        onAmountChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                          // Editing invalidates the cached attempt id —
                          // any in-flight submit was for the old amount.
                          _attemptId = null;
                        },
                        onQuickPick: _setAmount,
                        balance: balance,
                        workerAsync: workerAsync,
                        destination: defaultBank,
                        destinationLoading: banksAsync.isLoading,
                      ),
              ),
            ),

            // Sticky CTA.
            Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: Container(
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
                  bottom: !kbOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: noBankLinked
                        ? PrimaryButton(
                            label: 'Link your bank',
                            icon: const Icon(Icons.add_link_rounded),
                            onPressed: () =>
                                context.push(RoutePaths.linkBank),
                          )
                        : PrimaryButton(
                            label: 'Review withdrawal',
                            isLoading: _previewing,
                            onPressed: (balance > 0 && !_previewing)
                                ? () => _openPreviewSheet(balance)
                                : null,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// No-bank-linked body
// ---------------------------------------------------------------------

class _NoBankLinkedBody extends StatelessWidget {
  const _NoBankLinkedBody();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_balance_rounded,
              size: 48,
              color: palette.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Link your bank to withdraw',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineSmall.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your Squad wallet sends money to your linked bank. '
            'Link an account once and every future withdrawal uses '
            "it. We'll keep the funds in your wallet until you do.",
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Amount entry body
// ---------------------------------------------------------------------

class _AmountEntryBody extends StatelessWidget {
  const _AmountEntryBody({
    required this.amount,
    required this.focusNode,
    required this.errorText,
    required this.onAmountChanged,
    required this.onQuickPick,
    required this.balance,
    required this.workerAsync,
    required this.destination,
    required this.destinationLoading,
  });

  final TextEditingController amount;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<int> onQuickPick;
  final int balance;
  final AsyncValue<Worker> workerAsync;
  final BankAccount? destination;
  final bool destinationLoading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.md),
        _BalanceLine(workerAsync: workerAsync),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Amount',
          style: AppTextStyles.labelLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AmountField(
          controller: amount,
          focusNode: focusNode,
          errorText: errorText,
          onChanged: onAmountChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        _QuickChips(balance: balance, onPick: onQuickPick),
        const SizedBox(height: AppSpacing.lg),
        _DestinationPreview(
          destination: destination,
          loading: destinationLoading,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Destination preview row on amount-entry screen
// ---------------------------------------------------------------------

class _DestinationPreview extends StatelessWidget {
  const _DestinationPreview({
    required this.destination,
    required this.loading,
  });

  final BankAccount? destination;
  final bool loading;

  /// Last 4 digits of an account number, masked-safe. The backend
  /// stores the full number; we only ever render the last four to the
  /// worker so a shoulder-surfer can't read off the full string from
  /// a glance at the withdraw screen.
  static String _last4(String accountNumber) {
    if (accountNumber.length <= 4) return accountNumber;
    return accountNumber.substring(accountNumber.length - 4);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.account_balance_rounded,
            size: 20,
            color: palette.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Going to',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                if (loading)
                  const LoadingShimmer.line(width: 160, height: 14)
                else
                  Text(
                    destination == null
                        ? 'No bank linked'
                        : '${destination!.bankName} · ****${_last4(destination!.accountNumber)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              Icon(
                Icons.flash_on_rounded,
                size: 14,
                color: palette.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Instant via Squad',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Preview sheet (Confirm withdrawal)
// ---------------------------------------------------------------------

class _PreviewSheet extends ConsumerStatefulWidget {
  const _PreviewSheet({
    required this.preview,
    required this.attemptId,
    required this.onSuccess,
  });

  final WithdrawalPreview preview;
  final String attemptId;
  final ValueChanged<WithdrawalResult> onSuccess;

  @override
  ConsumerState<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends ConsumerState<_PreviewSheet> {
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(walletRepositoryProvider)
          .submitWithdrawal(
            amount: widget.preview.amount,
            clientWithdrawalId: widget.attemptId,
          );
      if (!mounted) return;
      widget.onSuccess(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't complete the transfer. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = widget.preview;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.outline,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Confirm withdrawal',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "You'll be debited the moment you confirm. "
                'Cancel any time before that.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _AmountBlock(amount: p.amount),
              const SizedBox(height: AppSpacing.lg),
              _PreviewRow(
                label: 'To',
                value: '${p.destinationBank} · ****${p.destinationLast4}',
                emphasised: true,
              ),
              if (p.destinationAccountName.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _PreviewRow(label: 'Account name', value: p.destinationAccountName),
              ],
              const SizedBox(height: AppSpacing.sm),
              _PreviewRow(
                label: 'Fee',
                value: p.fee == 0 ? 'Free' : '₦${p.fee}',
              ),
              const SizedBox(height: AppSpacing.sm),
              _PreviewRow(
                label: 'Credited',
                value: '₦${p.amountCredited}',
                emphasised: true,
              ),
              if (p.estimatedArrival.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _PreviewRow(label: 'Arrives', value: p.estimatedArrival),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Confirm withdrawal',
                isLoading: _submitting,
                onPressed: _submitting ? null : _confirm,
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Cancel',
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountBlock extends StatelessWidget {
  const _AmountBlock({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'You will send',
            style: AppTextStyles.labelMedium.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          CurrencyText(
            amount: amount,
            size: CurrencySize.large,
            tone: CurrencyTone.debit,
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool emphasised;

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
            style: (emphasised
                    ? AppTextStyles.titleSmall
                    : AppTextStyles.bodyMedium)
                .copyWith(
              color: palette.onSurface,
              fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Sub-widgets retained from the original screen
// ---------------------------------------------------------------------

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.workerAsync});
  final AsyncValue<Worker> workerAsync;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            'Available balance',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        workerAsync.when(
          loading: () => const LoadingShimmer.line(width: 90, height: 16),
          error: (Object _, StackTrace _) => Text(
            '—',
            style: AppTextStyles.titleMedium
                .copyWith(color: palette.onSurfaceVariant),
          ),
          data: (Worker w) => CurrencyText(
            amount: w.walletBalance,
            size: CurrencySize.small,
          ),
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasError = errorText != null;
    final borderColor = hasError ? palette.error : palette.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: palette.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: borderColor, width: hasError ? 1.5 : 1),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                '₦',
                style: AppTextStyles.currencyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: onChanged,
                  cursorColor: palette.primary,
                  cursorWidth: 1.6,
                  style: AppTextStyles.currencyMedium.copyWith(
                    color: palette.onSurface,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.base),
            child: Text(
              errorText!,
              style: AppTextStyles.bodySmall.copyWith(color: palette.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickChips extends StatelessWidget {
  const _QuickChips({required this.balance, required this.onPick});
  final int balance;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final options = <(String, int)>[
      ('₦1,000', 1000),
      ('₦5,000', 5000),
      ('₦10,000', 10000),
      ('All', balance),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final (String label, int value) in options)
          Material(
            color: palette.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.full),
              onTap: value > 0 ? () => onPick(value) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  label,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: value > 0
                        ? palette.onSurface
                        : palette.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
