import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';
import '../../../core/notifications/device_repository.dart';
import '../../../core/notifications/notifications_service.dart';
import '../../../core/storage/session_storage.dart';
import '../data/auth_repository.dart';

/// Singletons for the auth stack. They live as long as the app — the
/// splash gate reads them on boot, every screen reads them inside its
/// build, and `ref.invalidate(authSessionProvider)` re-resolves the
/// session after login / logout.

final Provider<SessionStorage> sessionStorageProvider =
    Provider<SessionStorage>((Ref ref) => SessionStorage());

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final client = ApiClient(storage: ref.watch(sessionStorageProvider));
  ref.onDispose(client.close);
  return client;
});

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
  return AuthRepository(
    client: ref.watch(apiClientProvider),
    storage: ref.watch(sessionStorageProvider),
  );
});

/// Push device-registration repo (`POST` / `DELETE /me/devices`).
/// Consumed by [notificationsServiceProvider] and by the logout flow.
final Provider<DeviceRepository> deviceRepositoryProvider =
    Provider<DeviceRepository>((Ref ref) {
  return DeviceRepository(
    client: ref.watch(apiClientProvider),
    storage: ref.watch(sessionStorageProvider),
  );
});

/// FCM push runtime — token, permission, foreground display, tap stream.
/// Initialised once from `app.dart`; lives for the app's lifetime.
final Provider<NotificationsService> notificationsServiceProvider =
    Provider<NotificationsService>((Ref ref) {
  final svc = NotificationsService(
    deviceRepository: ref.watch(deviceRepositoryProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Cold-start session snapshot. Splash awaits this before deciding
/// where to send the user. Invalidate after login / logout to force a
/// re-read from secure storage.
final FutureProvider<SessionSnapshot> authSessionProvider =
    FutureProvider<SessionSnapshot>((Ref ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.resolveSession();
});

/// Currently-authenticated worker, sourced from the session snapshot.
/// Null means either signed-out or signup-in-progress (profile-setup
/// not yet completed). Screens that need the live worker can either
/// watch this or fall through to the existing mock provider while
/// other features are still on mocks.
final Provider<Worker?> sessionWorkerProvider = Provider<Worker?>((Ref ref) {
  final session = ref.watch(authSessionProvider).valueOrNull;
  return switch (session) {
    Authenticated(:final worker) => worker,
    _ => null,
  };
});
