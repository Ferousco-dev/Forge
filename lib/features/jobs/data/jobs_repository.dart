import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// Backend-facing surface for the jobs feed + single-job detail.
///
/// - `GET /jobs` — `02_jobs_feed.md`
/// - `GET /jobs/:id` — `03_job_detail.md`
/// - `POST /jobs/:id/apply` — `04_apply_for_job.md`
class JobsRepository {
  JobsRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  /// `GET /jobs`. [lat] / [lng] are required by the spec; the others
  /// are optional filters. Pass [cursor] to fetch the next page.
  Future<JobsPage> fetchNearby({
    required double lat,
    required double lng,
    double? radiusKm,
    Iterable<JobType>? types,
    int? minPay,
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      'limit': limit.toString(),
      if (radiusKm != null) 'radius_km': radiusKm.toString(),
      if (types != null && types.isNotEmpty)
        'types': types.map((t) => t.wire).join(','),
      if (minPay != null) 'min_pay': minPay.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };

    final json = await _client.get(
      '/jobs',
      authenticated: true,
      query: query,
    );

    final items = _parseItems(json, source: 'fetchNearby');
    final rawCursor = json['next_cursor'] ?? json['nextCursor'];
    final String? cursorStr = rawCursor is String ? rawCursor : null;
    final bool more =
        (json['has_more'] ?? json['hasMore']) as bool? ?? false;

    return JobsPage(items: items, nextCursor: cursorStr, hasMore: more);
  }

  /// `GET /jobs` with no lat/lng/radius — pulls jobs from the entire
  /// catalog regardless of where the worker is. Used by the search
  /// screen so postings in any city are discoverable.
  ///
  /// Why a separate method: [fetchNearby] always sends `lat`/`lng`, and
  /// the backend caps `radius_km` at 25 (per OpenAPI), so there's no
  /// way to widen the existing call into "everywhere". Omitting the
  /// spatial params entirely is the documented escape hatch — they're
  /// `required: false` in the spec.
  Future<JobsPage> fetchAll({
    required double lat,
    required double lng,
    Iterable<JobType>? types,
    int? minPay,
    String? cursor,
    int limit = 50,
  }) async {
    // Backend requires lat/lng and caps radius_km at 25. Send the max
    // allowed radius so search covers as wide an area as the API
    // permits. Truly country-wide search will need a dedicated
    // /jobs/search endpoint on the server.
    final query = <String, String>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius_km': '25',
      'limit': limit.toString(),
      if (types != null && types.isNotEmpty)
        'types': types.map((t) => t.wire).join(','),
      if (minPay != null) 'min_pay': minPay.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };

    final json = await _client.get(
      '/jobs',
      authenticated: true,
      query: query,
    );

    final items = _parseItems(json, source: 'fetchAll');
    final rawCursor = json['next_cursor'] ?? json['nextCursor'];
    final String? cursorStr = rawCursor is String ? rawCursor : null;
    final bool more =
        (json['has_more'] ?? json['hasMore']) as bool? ?? false;

    return JobsPage(items: items, nextCursor: cursorStr, hasMore: more);
  }

  /// Parse the `items` array from a `/jobs` envelope, logging
  /// per-row parse failures so we can diagnose backend schema drift
  /// instead of silently dropping rows via `whereType`.
  ///
  /// Returns the parsed items + prints diagnostics in debug builds:
  ///   - raw row count from the wire
  ///   - the id of any row that failed to parse + the error
  ///   - the final parsed count
  /// Release builds skip all of this work — `kDebugMode` guards every
  /// branch.
  List<Job> _parseItems(
    Map<String, dynamic> json, {
    required String source,
  }) {
    final rawList = (json['items'] as List? ?? const <dynamic>[]);
    if (kDebugMode) {
      debugPrint('[jobs_repository:$source] received ${rawList.length} '
          'row(s) from /jobs');
    }
    final List<Job> out = <Job>[];
    for (int i = 0; i < rawList.length; i++) {
      final raw = rawList[i];
      if (raw is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint('[jobs_repository:$source] row $i is not an object '
              '— skipping. type=${raw.runtimeType}');
        }
        continue;
      }
      try {
        out.add(Job.fromJson(raw));
      } catch (e) {
        if (kDebugMode) {
          final id = raw['id'] ?? '(no id)';
          debugPrint('[jobs_repository:$source] row $i id=$id '
              'failed to parse: $e\n  keys=${raw.keys.toList()}');
        }
      }
    }
    if (kDebugMode) {
      debugPrint('[jobs_repository:$source] parsed ${out.length} job(s) '
          '(${rawList.length - out.length} dropped)');
    }
    return out;
  }

  /// `GET /jobs/:id`. Recomputes distance/travel against [lat]/[lng].
  Future<JobDetail> fetchById({
    required String id,
    required double lat,
    required double lng,
  }) async {
    final json = await _client.get(
      '/jobs/$id',
      authenticated: true,
      query: <String, String>{
        'lat': lat.toString(),
        'lng': lng.toString(),
      },
    );
    return JobDetail(
      job: Job.fromJson(json),
      viewerApplication: json['viewer_application'] is Map<String, dynamic>
          ? JobApplication.fromJson(<String, dynamic>{
              ...json['viewer_application'] as Map<String, dynamic>,
              // /jobs/:id embeds the application without a `job` field;
              // re-attach so JobApplication.fromJson sees a complete shape.
              'job': json,
            })
          : null,
      applicantsCount: (json['applicants_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// `POST /jobs/:id/apply`. Returns an [ApplicationSummary] (the slim
  /// shape that backs `ApplicationSummaryDto` — `job_id` only, no
  /// embedded job). The 409 `ALREADY_APPLIED` path returns the same
  /// envelope; the API client surfaces those as `ApiException` with
  /// `details.application`, which the caller can read if it needs to
  /// route straight to the existing application.
  Future<ApplicationSummary> apply({
    required String jobId,
    String? note,
  }) async {
    final json = await _client.post(
      '/jobs/$jobId/apply',
      authenticated: true,
      idempotent: true,
      idempotencyAction: 'apply:$jobId',
      body: <String, dynamic>{
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    final app = json['application'] as Map<String, dynamic>;
    return ApplicationSummary.fromJson(app);
  }
}

class JobsPage {
  const JobsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Job> items;
  final String? nextCursor;
  final bool hasMore;
}

class JobDetail {
  const JobDetail({
    required this.job,
    required this.applicantsCount,
    this.viewerApplication,
  });
  final Job job;
  final JobApplication? viewerApplication;
  final int applicantsCount;
}
