import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';
import '../../../core/storage/session_storage.dart';

/// Backend-facing surface for the profile feature.
///
/// `GET /me` returns the canonical [Worker] shape — every other endpoint
/// that embeds a worker uses this exact subset (per
/// `endpoint_resources/16_profile.md`). The repository also seeds /me
/// into [SessionStorage] so the splash gate's cached read on the next
/// cold start has fresh stats — wallet balance, jobs completed, etc.
class ProfileRepository {
  ProfileRepository({
    required ApiClient client,
    required SessionStorage storage,
  })  : _client = client,
        _storage = storage;

  final ApiClient _client;
  final SessionStorage _storage;

  /// `GET /me` — the canonical worker shape.
  ///
  /// Returns the freshly-fetched worker. The cache write is best-effort;
  /// a write failure doesn't block the screen from rendering the live
  /// data.
  Future<Worker> fetchMe() async {
    final json = await _client.get('/me', authenticated: true);
    final workerJson = json['worker'] as Map<String, dynamic>;
    final worker = Worker.fromJson(workerJson);
    // Refresh the cached worker so a subsequent cold start reads
    // up-to-date stats from secure storage before /me resolves.
    await _storage.writeWorker(workerJson);
    return worker;
  }

  /// `PATCH /me` — partial update. Per `17_edit_profile.md`, all fields
  /// are optional; only present fields update on the server. Pass
  /// [removePhoto] = true to send an explicit `"photo_upload_id": null`
  /// (revert to initial-fallback avatar).
  Future<Worker> patchMe({
    String? name,
    String? primarySkill,
    double? preferredRadiusKm,
    String? photoUploadId,
    bool removePhoto = false,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (primarySkill != null) 'primary_skill': primarySkill,
      if (preferredRadiusKm != null)
        'preferred_radius_km': preferredRadiusKm,
      if (removePhoto) 'photo_upload_id': null,
      if (!removePhoto && photoUploadId != null && photoUploadId.isNotEmpty)
        'photo_upload_id': photoUploadId,
    };
    final json = await _client.patch(
      '/me',
      authenticated: true,
      body: body,
    );
    final workerJson = json['worker'] as Map<String, dynamic>;
    final worker = Worker.fromJson(workerJson);
    await _storage.writeWorker(workerJson);
    return worker;
  }
}
