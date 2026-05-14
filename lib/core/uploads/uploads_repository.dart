import 'dart:convert';

import '../api/api_client.dart';
import '../mock/models.dart';

/// Uploads — generic file pipeline (`22_uploads.md`) plus the
/// AI-verified liveness selfie used in the signup flow
/// (`23_liveness.md`).
class UploadsRepository {
  UploadsRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  /// `POST /uploads` — generic upload. Used by clock-out proof
  /// photos and the (trusted) edit-profile avatar flow. The signup
  /// avatar uses [uploadLiveness] instead so the AI verification
  /// runs synchronously.
  Future<UploadHandle> upload({
    required UploadPurpose purpose,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final json = await _client.upload(
      '/uploads',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: <String, String>{'purpose': purpose.wire},
    );
    return UploadHandle.fromJson(json);
  }

  /// `POST /uploads/liveness` — AI-verified selfie capture for the
  /// signup flow.
  ///
  /// Server runs face-count + anti-spoof + quality checks
  /// synchronously. On success we get an [UploadHandle] whose id
  /// flows into `POST /auth/profile-setup` as `photo_upload_id`. On
  /// rejection the caller sees a typed `ApiException` (`LIVENESS_*`
  /// codes) with a user-ready `message` — render directly + offer
  /// "retake".
  ///
  /// v2 (see `endpoint_resources/ai.md` §4) layers a GPT-4 Vision
  /// sidecar on top of Smile Identity. Rejection bodies may include
  /// `details.reviewer` (`"smile"` or `"vision"`) plus new
  /// `details.reason` values (`screen_replay`, `printed_photo`,
  /// `mask`, `obscured_face`, `eyes_closed`). The mobile contract
  /// is unchanged — we still render `error.message` verbatim —
  /// these fields are observability-only.
  ///
  /// [deviceMetadata] is free-form context (`platform`, `model`,
  /// `camera`) attached to the request for fraud analytics. Pass
  /// null to skip — the endpoint will still verify normally.
  Future<UploadHandle> uploadLiveness({
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String>? deviceMetadata,
  }) async {
    // `/uploads/liveness` is a dedicated endpoint — it does NOT take
    // a `purpose` field (the server returns 400 "property purpose
    // should not exist" if one is sent). Only `file` and
    // `device_metadata` are accepted; the verification verdict comes
    // back inline in the response's `liveness` block.
    final json = await _client.upload(
      '/uploads/liveness',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: <String, String>{
        if (deviceMetadata != null && deviceMetadata.isNotEmpty)
          'device_metadata': jsonEncode(deviceMetadata),
      },
    );
    return UploadHandle.fromJson(json);
  }
}

/// Wire values for the `purpose` field on the generic
/// `POST /v1/uploads` endpoint. NOT for `/uploads/liveness` — that
/// endpoint rejects any `purpose` field; pass none.
enum UploadPurpose {
  /// Avatar swap from the in-app edit-profile screen (worker is
  /// already signed up). Consumed by `PATCH /v1/me`.
  workerAvatar('worker_avatar'),

  clockOutProof('clock_out_proof');

  const UploadPurpose(this.wire);
  final String wire;
}
