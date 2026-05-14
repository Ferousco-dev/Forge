import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/loans_repository.dart';

final Provider<LoansRepository> loansRepositoryProvider =
    Provider<LoansRepository>((Ref ref) {
  return LoansRepository(client: ref.watch(apiClientProvider));
});

final FutureProvider<CreditProfile> creditProfileProvider =
    FutureProvider<CreditProfile>((Ref ref) {
  ref.keepAlive();
  return ref.watch(loansRepositoryProvider).fetchCredit();
});

/// Active loan or null. Drives the loans-home branching (eligibility CTA
/// vs. outstanding-balance card).
final FutureProvider<Loan?> activeLoanProvider =
    FutureProvider<Loan?>((Ref ref) {
  ref.keepAlive();
  return ref.watch(loansRepositoryProvider).fetchActive();
});

final FutureProviderFamily<Loan, String> loanDetailProvider =
    FutureProvider.family<Loan, String>((Ref ref, String id) {
  ref.keepAlive();
  return ref.watch(loansRepositoryProvider).fetchById(id);
});
