import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/profile_repository.dart';

/// Singleton repository — wraps the API client + session storage from
/// the auth state module so the profile feature shares the same
/// authenticated client as everything else.
final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>((Ref ref) {
  return ProfileRepository(
    client: ref.watch(apiClientProvider),
    storage: ref.watch(sessionStorageProvider),
  );
});

/// `GET /me`. Hit on every cold start (after auth) and on every
/// pull-to-refresh in earnings, profile, and loans (per
/// `endpoint_resources/16_profile.md`).
///
/// Lives under the same name the rest of the codebase already imports
/// from `core/mock/mock_providers.dart` — that file re-exports this
/// symbol so call sites don't need to change as features migrate off
/// mocks.
final FutureProvider<Worker> currentWorkerProvider =
    FutureProvider<Worker>((Ref ref) async {
  // Cache /me for the session. The edit-profile screen calls
  // `ref.invalidate(currentWorkerProvider)` after saving so the new
  // values flow back through the rest of the app.
  ref.keepAlive();
  return ref.watch(profileRepositoryProvider).fetchMe();
});
