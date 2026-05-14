import '../../../core/mock/models.dart';
import '../../../core/storage/session_storage.dart';

/// Local-only bookmarks store.
///
/// Persists the **full [Job] snapshot** at bookmark time (not just the
/// id), so the bookmarks screen renders even when the live job has
/// since been filled, expired, or removed from the feed. The trade-off
/// is a few extra KB per bookmark, which is fine for the volumes a
/// single worker actually saves.
///
/// Pure-local for v1. If the backend later grows `/me/bookmarks`,
/// swap this layer for an `ApiClient` call without touching the state
/// provider or the screen.
class BookmarksRepository {
  BookmarksRepository({required SessionStorage storage}) : _storage = storage;

  final SessionStorage _storage;

  /// Read all bookmarks, newest-first.
  Future<List<Job>> readAll() async {
    final raw = await _storage.readBookmarks();
    final jobs = <Job>[];
    for (final entry in raw) {
      try {
        jobs.add(Job.fromJson(entry));
      } catch (_) {
        // Skip malformed entries — should never happen since we write
        // them ourselves, but be defensive across schema changes.
      }
    }
    return jobs;
  }

  /// Returns the set of bookmarked job ids — cheap lookup for the
  /// detail screen's filled/outline icon state.
  Future<Set<String>> readIds() async {
    final raw = await _storage.readBookmarks();
    return raw
        .map((Map<String, dynamic> j) => j['id'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Save [job] to the top of the bookmarks list. If it's already
  /// bookmarked, move it to the top (re-bookmarking refreshes order).
  Future<void> add(Job job) async {
    final raw = await _storage.readBookmarks();
    final without =
        raw.where((Map<String, dynamic> j) => j['id'] != job.id).toList();
    final next = <Map<String, dynamic>>[_toJson(job), ...without];
    await _storage.writeBookmarks(next);
  }

  /// Remove a single bookmark by job id. No-op if not present.
  Future<void> remove(String jobId) async {
    final raw = await _storage.readBookmarks();
    final next =
        raw.where((Map<String, dynamic> j) => j['id'] != jobId).toList();
    await _storage.writeBookmarks(next);
  }

  /// Toggle convenience — returns the resulting bookmarked state so
  /// the caller can drive an instant UI update.
  Future<bool> toggle(Job job) async {
    final ids = await readIds();
    if (ids.contains(job.id)) {
      await remove(job.id);
      return false;
    }
    await add(job);
    return true;
  }

  /// Mirrors the wire shape from `02_jobs_feed.md` so the round-trip
  /// through storage is symmetric with `Job.fromJson`.
  Map<String, dynamic> _toJson(Job job) => <String, dynamic>{
        'id': job.id,
        'type': job.type.wire,
        'title': job.title,
        'description': job.description,
        'pay_amount': job.payAmount,
        'duration_hours': job.durationHours,
        'location': <String, dynamic>{
          'lat': job.locationLat,
          'lng': job.locationLng,
          'address': job.locationAddress,
        },
        'distance_meters': job.distanceMeters,
        'travel_time_walking_minutes': job.travelTimeWalkingMinutes,
        'travel_time_driving_minutes': job.travelTimeDrivingMinutes,
        'start_time': job.startTime.toUtc().toIso8601String(),
        'required_equipment': job.requiredEquipment,
        'employer': <String, dynamic>{
          'id': job.employer.id,
          'name': job.employer.name,
          'photo_url': job.employer.photoUrl,
          'rating': job.employer.rating,
          'jobs_posted': job.employer.jobsPosted,
          'member_since':
              job.employer.memberSince.toUtc().toIso8601String(),
          'phone_number': job.employer.phoneNumber,
        },
      };
}
