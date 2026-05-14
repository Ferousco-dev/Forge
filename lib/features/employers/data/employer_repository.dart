import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// Backend-facing surface for the employer profile feature.
///
/// - `GET /employers/:id` — `25_employer_profile.md`
/// - `GET /employers/:id/jobs` — `25_employer_profile.md`
class EmployerRepository {
  EmployerRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  /// `GET /employers/:id`. Full profile + server-computed stats.
  Future<EmployerProfile> fetchProfile({required String id}) async {
    final json = await _client.get(
      '/employers/$id',
      authenticated: true,
    );
    return EmployerProfile.fromJson(json);
  }

  /// `GET /employers/:id/jobs`. Paginated job list scoped to one
  /// employer. [lat]/[lng] are the worker's current location and
  /// drive the per-row distance fields server-side. [status] filters
  /// to `open` / `closed` / `all` (default `all`); the screen relies
  /// on the server's "open first, then closed" ordering to split the
  /// rendered list at the first `closed` row.
  Future<EmployerJobsPage> fetchJobs({
    required String id,
    required double lat,
    required double lng,
    EmployerJobStatus? status,
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      'limit': limit.toString(),
      if (status != null) 'status': status.wire,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };

    final json = await _client.get(
      '/employers/$id/jobs',
      authenticated: true,
      query: query,
    );

    final items = (json['items'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(EmployerJob.fromJson)
        .toList(growable: false);

    return EmployerJobsPage(
      items: items,
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
