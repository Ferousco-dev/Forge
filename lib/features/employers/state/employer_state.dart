import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/current_location.dart';
import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/employer_repository.dart';

/// Singleton repository — shares the authenticated API client.
final Provider<EmployerRepository> employerRepositoryProvider =
    Provider<EmployerRepository>((Ref ref) {
      return EmployerRepository(client: ref.watch(apiClientProvider));
    });

/// Full profile + stats for the dedicated employer screen.
/// Family-keyed by employer id.
final FutureProviderFamily<EmployerProfile, String> employerProfileProvider =
    FutureProvider.family<EmployerProfile, String>((Ref ref, String id) async {
      ref.keepAlive();
      return ref.watch(employerRepositoryProvider).fetchProfile(id: id);
    });

/// First page of jobs (active + history) for an employer. Distance
/// fields are computed against the worker's current location, same
/// pattern as `nearbyJobsProvider`. Pagination beyond the first page
/// can be layered on later via a separate notifier.
final FutureProviderFamily<EmployerJobsPage, String> employerJobsProvider =
    FutureProvider.family<EmployerJobsPage, String>((Ref ref, String id) async {
      ref.keepAlive();
      final location = await ref.watch(currentLocationProvider.future);
      return ref
          .watch(employerRepositoryProvider)
          .fetchJobs(id: id, lat: location.lat, lng: location.lng);
    });
