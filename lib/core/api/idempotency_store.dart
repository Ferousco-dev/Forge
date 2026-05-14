import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Persistent cache of `Idempotency-Key` UUIDs, keyed by a logical
/// action name (e.g. `apply:job_a3f81c`, `withdraw:txn_local_42`).
///
/// Per `endpoint_resources/00_README.md`: state-changing endpoints
/// that the user might retry **must** accept an `Idempotency-Key` and
/// the same key must be reused across retries until a terminal
/// response. The server caches the key + response for 24h.
///
/// We persist keys in `flutter_secure_storage` so that:
/// - A network failure mid-request, then an app restart, still uses
///   the same key on retry.
/// - A 5xx that we automatically retry from inside the same session
///   reuses the key as well.
///
/// Call [clear] only after the server has returned a terminal
/// response (any 2xx, or a 4xx that won't be retried). 5xx and
/// network failures must keep the key.
class IdempotencyStore {
  IdempotencyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _uuid = const Uuid();

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  static const String _key = 'idempotency.keys';

  /// In-memory mirror of the persisted map. Loaded lazily on first
  /// read; writes go through here AND through secure storage.
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (_) {
      // Platform channel missing (widget tests) — start with an empty
      // in-memory map. Tests don't hit retry paths anyway.
      raw = null;
    }
    final map = <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((k, v) {
            if (v is String) map[k] = v;
          });
        }
      } catch (_) {
        // Corrupt — discard and start fresh.
      }
    }
    _cache = map;
    return map;
  }

  Future<void> _flush() async {
    final cached = _cache;
    if (cached == null) return;
    try {
      await _storage.write(key: _key, value: jsonEncode(cached));
    } catch (_) {
      // Same tolerance as the read path.
    }
  }

  /// Returns the cached key for [action], or mints + persists a new
  /// UUID v4. The same call from a retry sees the same key.
  Future<String> obtain(String action) async {
    final map = await _load();
    final existing = map[action];
    if (existing != null) return existing;
    final fresh = _uuid.v4();
    map[action] = fresh;
    await _flush();
    return fresh;
  }

  /// Drop the cached key for [action] after a terminal response. The
  /// next call against the same logical action mints a fresh UUID.
  Future<void> clear(String action) async {
    final map = await _load();
    if (map.remove(action) != null) await _flush();
  }

  /// Wipe every cached key. Called from logout / hard session reset.
  Future<void> clearAll() async {
    _cache = <String, String>{};
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
