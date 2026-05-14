import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Encrypted on-device persistence for everything that survives a cold
/// start: the **refresh token**, the cached worker, and the
/// onboarding-seen flag.
///
/// **Access tokens are NOT persisted.** Per the auth contract they
/// live in memory only — see `ApiClient`. On cold start the app has
/// no access token; the first protected call drives a refresh
/// round-trip via the persisted refresh token.
///
/// Backed by `flutter_secure_storage` — Keychain on iOS, AES-encrypted
/// SharedPreferences on Android. The async surface looks heavy but each
/// call is microseconds; we wait on it once at boot inside the splash
/// gate so the rest of the app reads from in-memory state.
class SessionStorage {
  SessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  // ---- keys ---------------------------------------------------------
  static const String _refreshTokenKey = 'auth.refresh_token';
  static const String _refreshExpiresAtKey = 'auth.refresh_expires_at';
  static const String _workerKey = 'auth.worker';
  static const String _needsProfileSetupKey = 'auth.needs_profile_setup';
  static const String _onboardingSeenKey = 'app.onboarding_seen';
  static const String _deviceIdKey = 'push.device_id';
  static const String _lastPushTokenKey = 'push.last_registered_token';
  static const String _bookmarksKey = 'bookmarks.v1';
  /// Pre-multi-session key. Read-only — migration path for users who
  /// last opened the app on a single-session build. Drained into the
  /// v2 list once on resume, then deleted.
  static const String _workSessionLegacyKey = 'work.active_session.v1';

  /// Multi-session list. Each entry is a [PersistedWorkSession] blob;
  /// the array is keyed positionally (one slot per in-flight job).
  static const String _workSessionsKey = 'work.active_sessions.v2';

  // ---- active work sessions ----------------------------------------
  //
  // We persist only the minimum needed to RESUME each session on app
  // relaunch: which job, which application, when they clocked in,
  // what phase the flow was in. The full Job/Application/Employer
  // gets refetched from the server when the worker returns so a stale
  // local copy can't override authoritative server state.
  //
  // Stored as a JSON array of objects (one per in-flight job):
  //   [{"job_id": "...", "application_id": "...",
  //     "phase": "working", "clocked_in_at": "..."}, ...]

  /// Persists the full set of active sessions, overwriting the prior
  /// blob. Call after every controller mutation so an app kill at any
  /// moment leaves the worker resumable.
  Future<void> writeActiveSessions(
    List<PersistedWorkSession> sessions,
  ) async {
    if (sessions.isEmpty) {
      await _storage.delete(key: _workSessionsKey);
      return;
    }
    final payload = sessions
        .map((PersistedWorkSession s) => <String, dynamic>{
              'job_id': s.jobId,
              'application_id': s.applicationId,
              'phase': s.phase,
              if (s.clockedInAt != null)
                'clocked_in_at': s.clockedInAt!.toUtc().toIso8601String(),
              if (s.serverSessionId != null)
                'server_session_id': s.serverSessionId,
              if (s.proofUploadId != null)
                'proof_upload_id': s.proofUploadId,
              if (s.proofUploadExpiresAt != null)
                'proof_upload_expires_at':
                    s.proofUploadExpiresAt!.toUtc().toIso8601String(),
            })
        .toList(growable: false);
    await _storage.write(
      key: _workSessionsKey,
      value: jsonEncode(payload),
    );
  }

  /// Returns every persisted session pointer. Also drains the v1
  /// single-session key so workers upgrading from an earlier build
  /// don't lose their in-flight job.
  Future<List<PersistedWorkSession>> readActiveSessions() async {
    final sessions = <PersistedWorkSession>[];
    try {
      final raw = await _storage.read(key: _workSessionsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map<String, dynamic>) continue;
            final parsed = _decodeSession(entry);
            if (parsed != null) sessions.add(parsed);
          }
        }
      }
    } catch (_) {
      await _storage.delete(key: _workSessionsKey);
    }

    // One-shot migration from the v1 single-session blob. Once drained
    // we delete the legacy key so we don't repeat this on every boot.
    try {
      final legacyRaw = await _storage.read(key: _workSessionLegacyKey);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        final decoded = jsonDecode(legacyRaw);
        if (decoded is Map<String, dynamic>) {
          final parsed = _decodeSession(decoded);
          if (parsed != null && !sessions.any((PersistedWorkSession s) =>
              s.jobId == parsed.jobId)) {
            sessions.add(parsed);
          }
        }
        await _storage.delete(key: _workSessionLegacyKey);
      }
    } catch (_) {
      await _storage.delete(key: _workSessionLegacyKey);
    }

    return sessions;
  }

  PersistedWorkSession? _decodeSession(Map<String, dynamic> json) {
    try {
      return PersistedWorkSession(
        jobId: json['job_id'] as String,
        applicationId: json['application_id'] as String,
        phase: json['phase'] as String,
        clockedInAt: json['clocked_in_at'] is String
            ? DateTime.parse(json['clocked_in_at'] as String).toUtc()
            : null,
        serverSessionId: json['server_session_id'] as String?,
        proofUploadId: json['proof_upload_id'] as String?,
        proofUploadExpiresAt: json['proof_upload_expires_at'] is String
            ? DateTime.parse(json['proof_upload_expires_at'] as String).toUtc()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Clear every active session — called on logout.
  Future<void> clearActiveSessions() => Future.wait(<Future<void>>[
        _storage.delete(key: _workSessionsKey),
        _storage.delete(key: _workSessionLegacyKey),
      ]);

  // ---- tokens -------------------------------------------------------
  /// Persists the refresh token + its expiry. Access tokens are never
  /// written here — they live only in `ApiClient`'s in-memory cache.
  /// Single-use rotation: the previous refresh token is invalidated
  /// server-side as soon as a refresh response is received, so the
  /// new token must be persisted immediately, before any other call
  /// runs.
  Future<void> writeRefreshToken({
    required String refreshToken,
    required DateTime refreshExpiresAt,
  }) async {
    await Future.wait<void>(<Future<void>>[
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(
        key: _refreshExpiresAtKey,
        value: refreshExpiresAt.toUtc().toIso8601String(),
      ),
    ]);
  }

  /// Safe read — swallows platform-channel failures (e.g. widget tests
  /// without a mocked channel) and returns null. Writes intentionally
  /// don't get the same treatment: a write failure is a real bug.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readRefreshToken() => _safeRead(_refreshTokenKey);

  Future<DateTime?> readRefreshExpiresAt() async {
    final raw = await _safeRead(_refreshExpiresAtKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  // ---- worker -------------------------------------------------------
  Future<void> writeWorker(Map<String, dynamic>? worker) async {
    if (worker == null) {
      await _storage.delete(key: _workerKey);
      return;
    }
    await _storage.write(key: _workerKey, value: jsonEncode(worker));
  }

  Future<Map<String, dynamic>?> readWorker() async {
    final raw = await _safeRead(_workerKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // ---- needs-profile-setup flag ------------------------------------
  Future<void> writeNeedsProfileSetup(bool value) async {
    await _storage.write(
      key: _needsProfileSetupKey,
      value: value ? '1' : '0',
    );
  }

  Future<bool> readNeedsProfileSetup() async {
    final raw = await _safeRead(_needsProfileSetupKey);
    return raw == '1';
  }

  // ---- onboarding ---------------------------------------------------
  Future<void> writeOnboardingSeen(bool seen) async {
    await _storage.write(
      key: _onboardingSeenKey,
      value: seen ? '1' : '0',
    );
  }

  Future<bool> readOnboardingSeen() async {
    final raw = await _safeRead(_onboardingSeenKey);
    return raw == '1';
  }

  // ---- push / device ------------------------------------------------
  //
  // The `device_id` is a stable per-install identifier the backend uses
  // as the primary key on `/me/devices`. It must survive sign-out (so a
  // worker who signs back in lands on the same device row) but it does
  // *not* survive uninstall. Generated lazily on first call.
  //
  // The `last_registered_push_token` is a debouncer: FCM rotates tokens
  // and we re-register every cold start, so we cache the last successful
  // token to avoid hammering `/me/devices` when nothing changed.

  Future<String?> readDeviceId() => _safeRead(_deviceIdKey);

  /// Reads the persisted device id, generating + persisting one if
  /// this is the first call. UUID v4 with a `dvc_` prefix to match
  /// the wire shape in `endpoint_resources/24_push_notifications.md`.
  Future<String> readOrCreateDeviceId() async {
    final existing = await readDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = 'dvc_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
    await _storage.write(key: _deviceIdKey, value: fresh);
    return fresh;
  }

  Future<String?> readLastRegisteredPushToken() =>
      _safeRead(_lastPushTokenKey);

  Future<void> writeLastRegisteredPushToken(String token) async {
    await _storage.write(key: _lastPushTokenKey, value: token);
  }

  Future<void> clearLastRegisteredPushToken() async {
    await _storage.delete(key: _lastPushTokenKey);
  }

  // ---- bookmarks ---------------------------------------------------
  //
  // Stored as a JSON array of full Job objects (not just ids). Storing
  // the snapshot means the bookmarks screen renders even if the live
  // job has since been filled / removed from the feed. Trade-off is a
  // few extra KB per bookmark, which is fine for the volumes a single
  // worker bookmarks. Order is newest-first.
  //
  // Pure-local for now. If the backend later grows a `/me/bookmarks`
  // endpoint, swap this layer for an `ApiClient` call without touching
  // the repository or screens.

  Future<List<Map<String, dynamic>>> readBookmarks() async {
    final raw = await _safeRead(_bookmarksKey);
    if (raw == null || raw.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> writeBookmarks(List<Map<String, dynamic>> items) async {
    await _storage.write(key: _bookmarksKey, value: jsonEncode(items));
  }

  // ---- bulk clear ---------------------------------------------------
  /// Wipes everything auth-scoped. Used on logout and on a hard
  /// `TOKEN_INVALID` from the backend. The onboarding-seen flag is
  /// preserved — the user has still seen onboarding.
  ///
  /// `device_id` is also preserved: it's tied to the install, not the
  /// session. The push token cache is cleared so the next sign-in
  /// triggers a fresh `/me/devices` POST.
  Future<void> clearSession() async {
    await Future.wait<void>(<Future<void>>[
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _refreshExpiresAtKey),
      _storage.delete(key: _workerKey),
      _storage.delete(key: _needsProfileSetupKey),
      _storage.delete(key: _lastPushTokenKey),
      // Bookmarks are per-worker, not per-install — clear them so a
      // device handoff (worker A signs out, worker B signs in) starts
      // with an empty list.
      _storage.delete(key: _bookmarksKey),
      // Active work sessions are per-worker — sign-out wipes them so
      // the next user doesn't inherit a stranger's clock-in pointers.
      _storage.delete(key: _workSessionsKey),
      _storage.delete(key: _workSessionLegacyKey),
    ]);
  }
}

/// Minimal pointer to an active work session, persisted across app
/// kills via [SessionStorage.writeActiveSessions].
///
/// Deliberately small: we only persist the **identifiers** plus the
/// clock-in timestamp + phase, then refetch the full Job /
/// JobApplication via `applicationDetailProvider` on resume. That way
/// server-authoritative data (cancellation, payout already credited)
/// is never overridden by a stale local copy.
class PersistedWorkSession {
  const PersistedWorkSession({
    required this.jobId,
    required this.applicationId,
    required this.phase,
    this.clockedInAt,
    this.serverSessionId,
    this.proofUploadId,
    this.proofUploadExpiresAt,
  });

  final String jobId;
  final String applicationId;
  final String phase;
  final DateTime? clockedInAt;

  /// Server-side `WorkSession.id` from `POST /v1/sessions`. Persisted so
  /// a clock-out can still target the right session after a cold start.
  final String? serverSessionId;

  /// Server-issued `upload_id` from `POST /v1/uploads` for the clock-out
  /// proof photo. Persisted so an app kill between the upload and the
  /// clock-out call doesn't force a re-upload on relaunch — the
  /// submitting screen reads this and skips Step 1 of the submit flow.
  final String? proofUploadId;

  /// When the cached [proofUploadId] expires (server returns ~24h out).
  /// The submitting screen treats an expired id the same as a missing
  /// one — re-uploads from `photoPath`.
  final DateTime? proofUploadExpiresAt;
}
