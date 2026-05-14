import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/notifications_repository.dart';

final Provider<NotificationsRepository> notificationsRepositoryProvider =
    Provider<NotificationsRepository>((Ref ref) {
  return NotificationsRepository(client: ref.watch(apiClientProvider));
});

/// Top page of the in-app notifications feed. Carries `unreadCount`
/// alongside the items so the bell-icon badge can read from a single
/// source.
final FutureProvider<NotificationsPage> notificationsPageProvider =
    FutureProvider<NotificationsPage>((Ref ref) {
  ref.keepAlive();
  return ref.watch(notificationsRepositoryProvider).fetchPage();
});

/// Backwards-compat list — used by the older mock-symbol callers.
final FutureProvider<List<AppNotification>> notificationsProvider =
    FutureProvider<List<AppNotification>>((Ref ref) async {
  final page = await ref.watch(notificationsPageProvider.future);
  return page.items;
});
