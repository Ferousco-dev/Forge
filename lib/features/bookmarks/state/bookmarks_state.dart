import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../auth/state/auth_state.dart';
import '../data/bookmarks_repository.dart';

/// Singleton repository — bookmarks are storage-only, no API client
/// needed. Swap for an authenticated variant when the backend grows
/// `/me/bookmarks`.
final Provider<BookmarksRepository> bookmarksRepositoryProvider =
    Provider<BookmarksRepository>((Ref ref) {
  return BookmarksRepository(storage: ref.watch(sessionStorageProvider));
});

/// All bookmarked jobs (newest-first) for the bookmarks screen.
final FutureProvider<List<Job>> bookmarkedJobsProvider =
    FutureProvider<List<Job>>((Ref ref) async {
  ref.keepAlive();
  return ref.watch(bookmarksRepositoryProvider).readAll();
});

/// Set of bookmarked job ids — cheap lookup for the bookmark icon's
/// filled/outline state on the job detail screen. Watch this from the
/// icon widget so it flips instantly when the user toggles.
final FutureProvider<Set<String>> bookmarkedJobIdsProvider =
    FutureProvider<Set<String>>((Ref ref) async {
  ref.keepAlive();
  return ref.watch(bookmarksRepositoryProvider).readIds();
});

/// Toggle helper — call from any widget. Invalidates both bookmark
/// providers so the icon flips and the bookmarks screen refreshes
/// without any manual re-read.
Future<bool> toggleBookmark(WidgetRef ref, Job job) async {
  final isBookmarked =
      await ref.read(bookmarksRepositoryProvider).toggle(job);
  ref
    ..invalidate(bookmarkedJobsProvider)
    ..invalidate(bookmarkedJobIdsProvider);
  return isBookmarked;
}
