import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_state.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

/// Singleton repository — wraps the shared authenticated API client.
final Provider<AiRepository> aiRepositoryProvider = Provider<AiRepository>(
  (Ref ref) => AiRepository(client: ref.watch(apiClientProvider)),
);

/// Job summary, keyed by job id. KeepAlive because the same job appears
/// in multiple lists (home feed, search results, bookmarks) — pay
/// Anthropic once per app session per job. Server cache is 7 days, so
/// even invalidation here re-hits the cache on the next call.
final FutureProviderFamily<JobSummary, String> jobSummaryProvider =
    FutureProvider.family<JobSummary, String>((Ref ref, String jobId) async {
  ref.keepAlive();
  return ref.watch(aiRepositoryProvider).summarizeJob(jobId);
});
