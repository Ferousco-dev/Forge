import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// `06_my_applications.md` + `05_application_status.md`.
class ApplicationsRepository {
  ApplicationsRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<ApplicationsPage> fetchBucket({
    required ApplicationsBucket bucket,
    String? cursor,
    int limit = 20,
  }) async {
    final json = await _client.get(
      '/applications',
      authenticated: true,
      query: <String, String>{
        'bucket': bucket.wire,
        'limit': limit.toString(),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final items = (json['items'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(JobApplication.fromJson)
        .toList(growable: false);
    return ApplicationsPage(
      items: items,
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  /// `GET /applications/:id` — single application + (when in_progress
  /// or completed) embedded session record.
  Future<ApplicationDetail> fetchById(String id) async {
    final json = await _client.get(
      '/applications/$id',
      authenticated: true,
    );
    return ApplicationDetail(
      application: JobApplication.fromJson(json),
      session: json['session'] is Map<String, dynamic>
          ? WorkSessionRecord.fromJson(
              json['session'] as Map<String, dynamic>)
          : null,
    );
  }

  /// `POST /applications/:id/withdraw` — pull back before decision.
  Future<void> withdraw(String id) async {
    await _client.post(
      '/applications/$id/withdraw',
      authenticated: true,
    );
  }
}

enum ApplicationsBucket {
  active('active'),
  history('history');

  const ApplicationsBucket(this.wire);
  final String wire;
}

class ApplicationsPage {
  const ApplicationsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
  final List<JobApplication> items;
  final String? nextCursor;
  final bool hasMore;
}

class ApplicationDetail {
  const ApplicationDetail({required this.application, this.session});
  final JobApplication application;
  final WorkSessionRecord? session;
}
