import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../jobs/widgets/job_card.dart';
import '../state/bookmarks_state.dart';

/// Saved-jobs screen. Reached from Profile → "Saved jobs".
///
/// Lists every job the worker has bookmarked from a job detail, newest
/// first. Each row reuses the same [JobCard] used in the home feed so
/// the visual language stays consistent. Tapping a card pushes to the
/// job detail (where the bookmark icon — now filled — toggles back to
/// remove it).
///
/// State is fully local for v1 (see `BookmarksRepository`), so this
/// screen works offline.
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final bookmarksAsync = ref.watch(bookmarkedJobsProvider);

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        backgroundColor: palette.surface,
        surfaceTintColor: palette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Saved jobs',
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
      ),
      body: bookmarksAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (Object _, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              "Couldn't load your saved jobs.",
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
        ),
        data: (List<Job> jobs) {
          if (jobs.isEmpty) {
            return EmptyStateView(
              title: 'No saved jobs yet',
              subtitle:
                  'Tap the bookmark on any job to save it here for '
                  'later. Saved jobs work offline too.',
              illustration: Icon(
                Icons.bookmark_outline_rounded,
                size: 56,
                color: palette.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(bookmarkedJobsProvider);
              await ref.read(bookmarkedJobsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: jobs.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (BuildContext context, int i) {
                final job = jobs[i];
                return JobCard(
                  job: job,
                  onTap: () => context.push(RoutePaths.jobDetail(job.id)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
