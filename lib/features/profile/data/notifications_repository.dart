import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// `19_notifications.md`.
class NotificationsRepository {
  NotificationsRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<NotificationsPage> fetchPage({
    String? cursor,
    int limit = 30,
  }) async {
    final json = await _client.get(
      '/me/notifications',
      authenticated: true,
      query: <String, String>{
        'limit': limit.toString(),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final items = (json['items'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList(growable: false);
    return NotificationsPage(
      items: items,
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> markRead(String id) async {
    await _client.post(
      '/me/notifications/$id/read',
      authenticated: true,
    );
  }

  Future<void> markAllRead() async {
    await _client.post(
      '/me/notifications/read-all',
      authenticated: true,
    );
  }
}

class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.hasMore,
    required this.unreadCount,
    this.nextCursor,
  });
  final List<AppNotification> items;
  final String? nextCursor;
  final bool hasMore;
  final int unreadCount;
}
