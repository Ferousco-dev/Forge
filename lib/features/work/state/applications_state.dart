import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/applications_repository.dart';

final Provider<ApplicationsRepository> applicationsRepositoryProvider =
    Provider<ApplicationsRepository>((Ref ref) {
  return ApplicationsRepository(client: ref.watch(apiClientProvider));
});

/// Active bucket — `applied`, `accepted`, `in_progress`.
final FutureProvider<List<JobApplication>> activeApplicationsProvider =
    FutureProvider<List<JobApplication>>((Ref ref) async {
  ref.keepAlive();
  final page = await ref
      .watch(applicationsRepositoryProvider)
      .fetchBucket(bucket: ApplicationsBucket.active);
  return page.items;
});

/// History bucket — `completed`, `rejected`, `withdrawn`.
final FutureProvider<List<JobApplication>> applicationHistoryProvider =
    FutureProvider<List<JobApplication>>((Ref ref) async {
  ref.keepAlive();
  final page = await ref
      .watch(applicationsRepositoryProvider)
      .fetchBucket(bucket: ApplicationsBucket.history);
  return page.items;
});

/// `GET /applications/:id` — application + (when in progress / completed)
/// embedded session record. Polled by `application_status_screen.dart`.
///
/// NOTE: not keepAlive because the status screen polls it; we want
/// `ref.invalidate()` calls there to actually re-fetch.
final FutureProviderFamily<ApplicationDetail, String>
    applicationDetailProvider =
    FutureProvider.family<ApplicationDetail, String>((Ref ref, String id) {
  return ref.watch(applicationsRepositoryProvider).fetchById(id);
});
