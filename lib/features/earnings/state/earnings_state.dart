import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/transactions_repository.dart';
import '../data/wallet_repository.dart';

final Provider<TransactionsRepository> transactionsRepositoryProvider =
    Provider<TransactionsRepository>((Ref ref) {
  return TransactionsRepository(client: ref.watch(apiClientProvider));
});

final Provider<WalletRepository> walletRepositoryProvider =
    Provider<WalletRepository>((Ref ref) {
  return WalletRepository(client: ref.watch(apiClientProvider));
});

/// Top page of the worker's transaction ledger. Drives the earnings-home
/// preview ("Recent 10") and the all-transactions screen. Pull-to-refresh
/// invalidates this and re-fetches.
final FutureProvider<List<Transaction>> transactionsProvider =
    FutureProvider<List<Transaction>>((Ref ref) async {
  ref.keepAlive();
  final page = await ref
      .watch(transactionsRepositoryProvider)
      .fetchPage(limit: 30);
  return page.items;
});

final FutureProviderFamily<Transaction, String> transactionByIdProvider =
    FutureProvider.family<Transaction, String>((Ref ref, String id) {
  ref.keepAlive();
  return ref.watch(transactionsRepositoryProvider).fetchById(id);
});

final FutureProvider<List<BankAccount>> bankAccountsProvider =
    FutureProvider<List<BankAccount>>((Ref ref) {
  ref.keepAlive();
  return ref.watch(walletRepositoryProvider).fetchMyAccounts();
});

final FutureProvider<List<Bank>> supportedBanksProvider =
    FutureProvider<List<Bank>>((Ref ref) {
  // Bank list almost never changes — cache aggressively.
  ref.keepAlive();
  return ref.watch(walletRepositoryProvider).fetchSupportedBanks();
});
