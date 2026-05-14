import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/help_repository.dart';

final Provider<HelpRepository> helpRepositoryProvider =
    Provider<HelpRepository>((Ref ref) {
  return HelpRepository(client: ref.watch(apiClientProvider));
});

/// FAQ list. Public endpoint — works during onboarding before login.
/// Optional category filter is keyed by the family parameter; pass an
/// empty string for "all".
final FutureProviderFamily<List<HelpArticle>, String>
    helpArticlesProvider =
    FutureProvider.family<List<HelpArticle>, String>(
  (Ref ref, String category) async {
    // FAQ content rarely changes — cache for the session.
    ref.keepAlive();
    return ref.watch(helpRepositoryProvider).fetchArticles(
          category: category.isEmpty ? null : category,
        );
  },
);
