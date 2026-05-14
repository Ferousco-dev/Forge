import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../work/state/work_session_controller.dart';
import '../widgets/job_card.dart';

/// "My applications" — Active + History tabs.
///
/// Reuses [JobCard] with the `application` slot populated, which adds
/// the prominent [StatusBadge] in the top-right of the card.
class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: palette.surface,
        appBar: AppBar(
          title: const Text('My applications'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 2.5,
                indicatorColor: palette.primary,
                labelColor: palette.onSurface,
                unselectedLabelColor: palette.onSurfaceVariant,
                labelStyle: AppTextStyles.titleSmall,
                unselectedLabelStyle: AppTextStyles.titleSmall,
                splashFactory: NoSplash.splashFactory,
                tabs: const <Widget>[
                  Tab(text: 'Active'),
                  Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _ApplicationsList(active: true),
            _ApplicationsList(active: false),
          ],
        ),
      ),
    );
  }
}

class _ApplicationsList extends ConsumerWidget {
  const _ApplicationsList({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = active
        ? ref.watch(activeApplicationsProvider)
        : ref.watch(applicationHistoryProvider);
    final palette = context.palette;
    // HomeShell injects the bottom-nav height + gesture inset into
    // MediaQuery.padding. Stash it once and add to every list-padding
    // bottom so the last card clears the floating nav bar.
    final navInset = MediaQuery.paddingOf(context).bottom;
    final listBottomPad = AppSpacing.lg + navInset;

    return asyncList.when(
      loading: () => ListView.separated(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          listBottomPad,
        ),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, _) => const JobCardSkeleton(),
      ),
      error: (Object err, StackTrace st) {
        // Log to console so the real failure shows up next to the
        // banner. Without this the user only sees "try again" and the
        // exception silently vanishes — masking JSON-parse errors
        // (e.g. backend returns a slim DTO that the local model can't
        // parse) for hours of debugging.
        debugPrint('[my_applications] $err\n$st');
        return ErrorStateView(
          title: "Couldn't load your applications",
          message: 'Try again — your records are safe.',
          onRetry: () {
            if (active) {
              ref.invalidate(activeApplicationsProvider);
            } else {
              ref.invalidate(applicationHistoryProvider);
            }
          },
        );
      },
      data: (List<JobApplication> apps) {
        if (apps.isEmpty) {
          return EmptyStateView(
            title: active
                ? 'No active applications'
                : 'No completed applications yet',
            subtitle: active
                ? "You haven't applied to any jobs yet. "
                    'Browse jobs to get started.'
                : 'Once you complete jobs, they show up here.',
            illustration: Icon(
              active
                  ? Icons.task_alt_rounded
                  : Icons.history_rounded,
              size: 64,
              color: palette.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            action: active
                ? SizedBox(
                    width: 180,
                    child: PrimaryButton(
                      label: 'Browse jobs',
                      onPressed: () => context.go(RoutePaths.jobs),
                    ),
                  )
                : null,
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            listBottomPad,
          ),
          itemCount: apps.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (BuildContext context, int i) {
            final app = apps[i];
            // Prefer the LOCAL work-session phase over the server-side
            // application status when picking a destination. The server
            // may still report `accepted` while the worker has already
            // clocked in locally — routing off the server status alone
            // bounces the worker back to "I've arrived" (where tapping
            // the CTA regressed elapsed time). The local phase, when
            // present, is the authoritative resume point.
            String destination() {
              final session = ref.read(
                workSessionForJobProvider(app.job.id),
              );
              if (session != null) {
                switch (session.phase) {
                  case WorkPhase.accepted:
                    return RoutePaths.jobStatus(app.job.id);
                  case WorkPhase.arriving:
                    return RoutePaths.jobClockIn(app.job.id);
                  case WorkPhase.working:
                    return RoutePaths.jobInProgress(app.job.id);
                  case WorkPhase.reviewing:
                    return session.photoCaptured
                        ? RoutePaths.jobClockOutReview(app.job.id)
                        : RoutePaths.jobClockOutCamera(app.job.id);
                  case WorkPhase.submitting:
                    return RoutePaths.jobClockOutSubmitting(app.job.id);
                  case WorkPhase.pendingReview:
                    return RoutePaths.jobClockOutPending(app.job.id);
                  case WorkPhase.done:
                    return RoutePaths.jobClockOutComplete(app.job.id);
                }
              }
              switch (app.status) {
                case ApplicationStatus.accepted:
                  return RoutePaths.jobStatus(app.job.id);
                case ApplicationStatus.inProgress:
                  return RoutePaths.jobInProgress(app.job.id);
                case ApplicationStatus.completed:
                  // Completed jobs read from /applications/:id — the
                  // live /jobs/:id 404s once a listing fills, which is
                  // why the History tab was rendering "Couldn't load
                  // this job". The receipt screen is keyed off the
                  // application id and stays valid forever.
                  return RoutePaths.completedJobReceipt(app.id);
                case ApplicationStatus.applied:
                case ApplicationStatus.rejected:
                case ApplicationStatus.withdrawn:
                  return RoutePaths.jobDetail(app.job.id);
              }
            }

            return JobCard(
              job: app.job,
              application: app,
              onTap: () => context.push(destination()),
            );
          },
        );
      },
    );
  }
}
