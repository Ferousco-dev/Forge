import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// `07_work_session.md` — server-authoritative work lifecycle.
class SessionsRepository {
  SessionsRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<WorkSessionRecord> clockIn({
    required String applicationId,
    required double lat,
    required double lng,
    required double accuracyMeters,
  }) async {
    final json = await _client.post(
      '/sessions',
      authenticated: true,
      idempotent: true,
      // One clock-in per application — the action key stays stable
      // across retries (network failure, app restart) so the server
      // returns the existing session instead of trying to create a
      // duplicate.
      idempotencyAction: 'clock-in:$applicationId',
      body: <String, dynamic>{
        'application_id': applicationId,
        'lat': lat,
        'lng': lng,
        'accuracy_meters': accuracyMeters,
      },
    );
    return WorkSessionRecord.fromJson(
      json['session'] as Map<String, dynamic>,
    );
  }

  /// Heartbeat / poll. Mobile calls every 60s while in_progress is
  /// foregrounded.
  Future<WorkSessionRecord> fetch(String id) async {
    final json = await _client.get(
      '/sessions/$id',
      authenticated: true,
    );
    return WorkSessionRecord.fromJson(
      json['session'] as Map<String, dynamic>,
    );
  }

  Future<WorkSessionRecord> clockOut({
    required String sessionId,
    required String proofUploadId,
    required double lat,
    required double lng,
    required double accuracyMeters,
    String? workerNote,
  }) async {
    final json = await _client.post(
      '/sessions/$sessionId/clock-out',
      authenticated: true,
      idempotent: true,
      // The clock-out is the payment trigger — retries during a Squad
      // outage MUST reuse the same key so the server returns the
      // already-completed session instead of double-disbursing.
      idempotencyAction: 'clock-out:$sessionId',
      body: <String, dynamic>{
        'proof_upload_id': proofUploadId,
        'lat': lat,
        'lng': lng,
        'accuracy_meters': accuracyMeters,
        if (workerNote != null && workerNote.isNotEmpty)
          'worker_note': workerNote,
      },
    );
    return WorkSessionRecord.fromJson(
      json['session'] as Map<String, dynamic>,
    );
  }
}
