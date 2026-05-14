import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/preferences_repository.dart';

final Provider<PreferencesRepository> preferencesRepositoryProvider =
    Provider<PreferencesRepository>((Ref ref) {
  return PreferencesRepository(client: ref.watch(apiClientProvider));
});

/// Server-synced preferences (notifications + privacy). The settings
/// screen overlays its local toggles on top of this snapshot, then
/// persists changes via [PreferencesRepository.patch].
final FutureProvider<RemotePreferences> remotePreferencesProvider =
    FutureProvider<RemotePreferences>((Ref ref) {
  ref.keepAlive();
  return ref.watch(preferencesRepositoryProvider).fetch();
});
