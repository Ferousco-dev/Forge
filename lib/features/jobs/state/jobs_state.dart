import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/current_location.dart';
import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/jobs_repository.dart';

/// Single-job lookup. Used by `job_detail_screen.dart`. Includes the
/// embedded `viewer_application` (so the screen can branch into "Apply"
/// vs. "View status" without a second round trip) and `applicants_count`
/// for the "7 others applied" social-proof line.
final FutureProviderFamily<JobDetail, String> jobDetailProvider =
    FutureProvider.family<JobDetail, String>((Ref ref, String id) async {
      // Cache job details for the session — re-entering a detail screen
      // shouldn't re-hit the network. Pull-to-refresh on the screen
      // should call `ref.invalidate(jobDetailProvider(id))`.
      ref.keepAlive();
      final location = await ref.watch(currentLocationProvider.future);
      return ref
          .watch(jobsRepositoryProvider)
          .fetchById(id: id, lat: location.lat, lng: location.lng);
    });

/// Backwards-compat wrapper for the older `jobByIdProvider` symbol —
/// returns just the [Job] portion of [jobDetailProvider]. Existing
/// `mock_providers.dart` consumers keep compiling.
final FutureProviderFamily<Job, String> jobByIdProvider =
    FutureProvider.family<Job, String>((Ref ref, String id) async {
      final detail = await ref.watch(jobDetailProvider(id).future);
      return detail.job;
    });

/// Singleton repository — wraps the shared authenticated API client.
final Provider<JobsRepository> jobsRepositoryProvider =
    Provider<JobsRepository>((Ref ref) {
      return JobsRepository(client: ref.watch(apiClientProvider));
    });

/// First page of the nearby-jobs feed for the current location.
///
/// Same name the rest of the codebase already imports from
/// `core/mock/mock_providers.dart` — that file re-exports this symbol
/// so call sites don't have to change as features migrate.
///
/// Pagination is intentionally not exposed yet: the home sheet renders
/// a single list. When infinite-scroll lands, layer a separate
/// notifier on top of [JobsRepository.fetchNearby] without changing
/// this provider's contract.
/// Maximum radius the `/v1/jobs` endpoint accepts, per the OpenAPI
/// spec (`radius_km` clamped to `[1, 25]`). We send the max so the
/// home feed isn't capped by the worker's `preferred_radius_km`
/// (defaults to 5km from the slider) — that smaller radius caused
/// workers to silently miss jobs posted just past their default
/// commute distance.
const double _nearbyRadiusKm = 25;

final FutureProvider<List<Job>> nearbyJobsProvider = FutureProvider<List<Job>>((
  Ref ref,
) async {
  // Keep the nearby feed in memory across tab switches. The home
  // screen's pull-to-refresh invalidates this explicitly.
  ref.keepAlive();
  final location = await ref.watch(currentLocationProvider.future);
  if (kDebugMode) {
    debugPrint('[nearbyJobsProvider] requesting /jobs at '
        'lat=${location.lat}, lng=${location.lng}, '
        'radius_km=$_nearbyRadiusKm (server max)');
  }
  final page = await ref.watch(jobsRepositoryProvider).fetchNearby(
        lat: location.lat,
        lng: location.lng,
        radiusKm: _nearbyRadiusKm,
      );
  return page.items;
});

/// Unbounded jobs feed — calls `/jobs` without lat/lng so the backend
/// returns the entire catalog instead of just the worker's nearby
/// radius (capped at 25 km server-side). Used by the search screen so
/// workers can find postings anywhere in the country.
///
/// Distance on each card is still rendered against the worker's GPS
/// (the Job model carries `locationLat`/`locationLng`, so the UI
/// computes "180 km away" client-side).
///
/// When the backend grows a dedicated `/jobs/search?q=...` endpoint
/// we can replace this without changing the search screen.
final FutureProvider<List<Job>> allJobsProvider = FutureProvider<List<Job>>((
  Ref ref,
) async {
  // Cache the unbounded jobs catalogue across tab switches and re-entry
  // into the search screen. Invalidate on pull-to-refresh.
  ref.keepAlive();
  final location = await ref.watch(currentLocationProvider.future);
  if (kDebugMode) {
    debugPrint('[allJobsProvider] requesting /jobs at '
        'lat=${location.lat}, lng=${location.lng}, '
        'radius_km=25 (server max)');
  }
  final page = await ref.watch(jobsRepositoryProvider).fetchAll(
        lat: location.lat,
        lng: location.lng,
        limit: 50,
      );
  return page.items;
});
