import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/earnings_state.dart';

/// Link a Nigerian bank account.
///
/// Brief: bank dropdown, account number input, account name field that
/// auto-populates after the number is entered, primary "Link account"
/// CTA. The auto-populate is mocked with a 600 ms debounce + a stable
/// pseudo-name derived from the digits.
class LinkBankScreen extends ConsumerStatefulWidget {
  const LinkBankScreen({super.key});

  @override
  ConsumerState<LinkBankScreen> createState() => _LinkBankScreenState();
}

class _LinkBankScreenState extends ConsumerState<LinkBankScreen> {
  Bank? _bank;
  final TextEditingController _accountNumber = TextEditingController();
  String? _accountNameError;
  String? _resolvedName;
  bool _resolving = false;
  bool _submitting = false;
  String? _submitError;
  Timer? _debounce;

  @override
  void dispose() {
    _accountNumber.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onAccountNumberChanged(String v) {
    setState(() => _accountNameError = null);
    _debounce?.cancel();
    if (v.length != 10 || _bank == null) {
      setState(() {
        _resolvedName = null;
        _resolving = false;
      });
      return;
    }
    setState(() {
      _resolving = true;
      _resolvedName = null;
    });
    _debounce =
        Timer(const Duration(milliseconds: 600), _resolveAccountName);
  }

  Future<void> _resolveAccountName() async {
    final bank = _bank;
    final number = _accountNumber.text;
    if (bank == null || number.length != 10) return;
    try {
      final name = await ref
          .read(walletRepositoryProvider)
          .resolveAccountName(
            bankCode: bank.code,
            accountNumber: number,
          );
      if (!mounted) return;
      // Bail out if inputs changed during the in-flight call.
      if (_accountNumber.text != number || _bank?.code != bank.code) return;
      setState(() {
        _resolving = false;
        _resolvedName = name;
        _accountNameError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolvedName = null;
        _accountNameError = e.message;
      });
    }
  }

  bool get _canSubmit =>
      _bank != null &&
      _accountNumber.text.length == 10 &&
      _resolvedName != null &&
      !_resolving;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(walletRepositoryProvider).linkAccount(
            bankCode: _bank!.code,
            accountNumber: _accountNumber.text,
            accountName: _resolvedName!,
            setAsDefault: true,
          );
      ref.invalidate(bankAccountsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    final palette = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        backgroundColor: palette.surfaceContainerHigh,
        content: Text(
          'Bank account linked.',
          style: TextStyle(color: palette.onSurface),
        ),
      ));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool kbOpen = keyboardInset > 0;

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
                      'Link bank',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Link your bank account',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      "We'll send your wallet earnings here when you "
                      'withdraw.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _FieldLabel('Bank'),
                    const SizedBox(height: AppSpacing.sm),
                    _BankDropdown(
                      value: _bank,
                      onChanged: (Bank? v) {
                        setState(() {
                          _bank = v;
                          _resolvedName = null;
                          _resolving = _accountNumber.text.length == 10;
                        });
                        if (_accountNumber.text.length == 10) {
                          _onAccountNumberChanged(_accountNumber.text);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _FieldLabel('Account number'),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      label: '10-digit account number',
                      controller: _accountNumber,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 10,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      errorText: _accountNameError,
                      onChanged: _onAccountNumberChanged,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _FieldLabel('Account name'),
                    const SizedBox(height: AppSpacing.sm),
                    _AccountNameField(
                      resolving: _resolving,
                      name: _resolvedName,
                      hasInputs: _bank != null &&
                          _accountNumber.text.length == 10,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),

            // Sticky CTA — sits flush above the keyboard when open,
            // and respects the system bottom inset when dismissed.
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_submitError != null) ...<Widget>[
                          Text(
                            _submitError!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: palette.error),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        PrimaryButton(
                          label: 'Link account',
                          isLoading: _submitting,
                          onPressed: _canSubmit ? _submit : null,
                        ),
                      ],
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(color: palette.onSurface),
    );
  }
}

class _BankDropdown extends ConsumerWidget {
  const _BankDropdown({required this.value, required this.onChanged});
  final Bank? value;
  final ValueChanged<Bank?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final asyncBanks = ref.watch(supportedBanksProvider);
    final banks = asyncBanks.valueOrNull ?? const <Bank>[];
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outline, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Bank>(
          value: value,
          isExpanded: true,
          hint: Text(
            asyncBanks.isLoading ? 'Loading banks…' : 'Select your bank',
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: palette.onSurfaceVariant),
          style: AppTextStyles.bodyLarge.copyWith(color: palette.onSurface),
          dropdownColor: palette.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onChanged: onChanged,
          items: <DropdownMenuItem<Bank>>[
            for (final Bank bank in banks)
              DropdownMenuItem<Bank>(value: bank, child: Text(bank.name)),
          ],
        ),
      ),
    );
  }
}

class _AccountNameField extends StatelessWidget {
  const _AccountNameField({
    required this.resolving,
    required this.name,
    required this.hasInputs,
  });
  final bool resolving;
  final String? name;
  final bool hasInputs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final Widget content;
    if (resolving) {
      content = Row(
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(palette.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Resolving account name…',
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      );
    } else if (name != null) {
      content = Row(
        children: <Widget>[
          Icon(Icons.check_circle_rounded,
              size: 18, color: palette.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name!,
              style: AppTextStyles.titleSmall.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    } else if (hasInputs) {
      content = const LoadingShimmer.line(width: 200, height: 16);
    } else {
      content = Text(
        'Pick a bank, then enter your account number.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: palette.onSurfaceVariant,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outlineVariant, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md + 2,
      ),
      child: content,
    );
  }
}
