import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/network_image_with_fallback.dart';
import '../../jobs/widgets/job_card.dart';
import '../state/employer_state.dart';

/// Employer profile screen.
///
/// Reached from the "About the employer" section on a job detail. Loads
/// the full profile (`GET /employers/:id`) and the paginated jobs list
/// (`GET /employers/:id/jobs`) in parallel — see
/// `endpoint_resources/25_employer_profile.md`.
///
/// Layout:
/// 1. Compact hero — back, photo, name + verified badge, rating
/// 2. Stats grid — open / completed / completion rate / average pay
/// 3. About — bio + business type + primary location
/// 4. Active jobs — currently-open postings (rendered via [JobCard])
/// 5. History — recent completed postings, muted
class EmployerDetailScreen extends ConsumerWidget {
  const EmployerDetailScreen({super.key, required this.employerId});

  final String employerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final profileAsync = ref.watch(employerProfileProvider(employerId));
    final jobsAsync = ref.watch(employerJobsProvider(employerId));

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const _ProfileSkeleton(),
          error: (Object _, StackTrace _) => Column(
            children: <Widget>[
              const _BackBar(),
              Expanded(
                child: ErrorStateView(
                  title: "Couldn't load this employer",
                  message: 'Try again — the profile may still be available.',
                  onRetry: () =>
                      ref.invalidate(employerProfileProvider(employerId)),
                ),
              ),
            ],
          ),
          data: (EmployerProfile profile) {
            return RefreshIndicator(
              onRefresh: () async {
                ref
                  ..invalidate(employerProfileProvider(employerId))
                  ..invalidate(employerJobsProvider(employerId));
                await ref.read(employerProfileProvider(employerId).future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: <Widget>[
                  const SliverToBoxAdapter(child: _BackBar()),
                  SliverToBoxAdapter(child: _Hero(profile: profile)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _StatsGrid(profile: profile),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _AboutSection(profile: profile),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    sliver: _JobsSliver(
                      jobsAsync: jobsAsync,
                      onRetry: () =>
                          ref.invalidate(employerJobsProvider(employerId)),
                      onJobTap: (Job j) =>
                          context.push(RoutePaths.jobDetail(j.id)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Back bar
// ---------------------------------------------------------------------

class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.maybePop(context),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Tooltip(
                message: 'Back',
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 24,
                  color: palette.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.profile});
  final EmployerProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emp = profile.employer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NetworkImageWithFallback(
            imageUrl: emp.photoUrl,
            size: 72,
            fallbackInitial: emp.name,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        emp.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: palette.onSurface,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (profile.verified) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      Tooltip(
                        message: 'Verified employer',
                        child: Icon(
                          Icons.verified_rounded,
                          size: 20,
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                if (profile.businessType.isNotEmpty)
                  Text(
                    profile.businessType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Icon(Icons.star_rounded,
                        size: 16, color: palette.secondary),
                    const SizedBox(width: 2),
                    Text(
                      emp.rating.toStringAsFixed(1),
                      style: AppTextStyles.labelMedium.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '  ·  Member since '
                      '${DateFormat.yMMM().format(emp.memberSince)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Stats grid
// ---------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.profile});
  final EmployerProfile profile;

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    final showCompletionRate = stats.completedJobs >= 10;
    final naira = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );

    final tiles = <_StatTileData>[
      _StatTileData(
        icon: Icons.bolt_rounded,
        label: 'Open jobs',
        value: stats.openJobs.toString(),
      ),
      _StatTileData(
        icon: Icons.check_circle_rounded,
        label: 'Completed',
        value: stats.completedJobs.toString(),
      ),
      if (showCompletionRate)
        _StatTileData(
          icon: Icons.trending_up_rounded,
          label: 'Completion rate',
          value: '${(stats.completionRate * 100).round()}%',
        )
      else
        const _StatTileData(
          icon: Icons.fiber_new_rounded,
          label: 'New employer',
          value: '— —',
        ),
      _StatTileData(
        icon: Icons.payments_rounded,
        label: 'Average pay',
        value: stats.averagePay > 0
            ? naira.format(stats.averagePay)
            : '— —',
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: <Widget>[for (final t in tiles) _StatTile(data: t)],
    );
  }
}

class _StatTileData {
  const _StatTileData({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.data});
  final _StatTileData data;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(data.icon, size: 16, color: palette.primary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// About
// ---------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.profile});
  final EmployerProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasBio = profile.bio != null && profile.bio!.trim().isNotEmpty;
    final hasLocation = profile.primaryLocationAddress != null &&
        profile.primaryLocationAddress!.isNotEmpty;

    if (!hasBio && !hasLocation) {
      // Nothing meaningful to show — skip the section entirely rather
      // than render an empty header.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'About',
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (hasBio)
          Text(
            profile.bio!,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        if (hasLocation) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(Icons.location_on_rounded,
                    color: palette.primary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    profile.primaryLocationAddress!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Jobs sliver — active + history
// ---------------------------------------------------------------------

class _JobsSliver extends StatelessWidget {
  const _JobsSliver({
    required this.jobsAsync,
    required this.onRetry,
    required this.onJobTap,
  });

  final AsyncValue<EmployerJobsPage> jobsAsync;
  final VoidCallback onRetry;
  final void Function(Job) onJobTap;

  @override
  Widget build(BuildContext context) {
    return jobsAsync.when(
      loading: () => SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(label: 'Jobs'),
            const SizedBox(height: AppSpacing.md),
            for (int i = 0; i < 3; i++) ...<Widget>[
              const LoadingShimmer.box(width: double.infinity, height: 120),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
      error: (Object _, StackTrace _) => SliverToBoxAdapter(
        child: Column(
          children: <Widget>[
            _SectionHeader(label: 'Jobs'),
            const SizedBox(height: AppSpacing.md),
            ErrorStateView(
              title: "Couldn't load jobs",
              message: 'Try again to see this employer\'s history.',
              onRetry: onRetry,
            ),
          ],
        ),
      ),
      data: (EmployerJobsPage page) {
        if (page.items.isEmpty) {
          return const SliverToBoxAdapter(
            child: EmptyStateView(
              title: 'No jobs to show yet',
              subtitle: "This employer hasn't posted any jobs in the "
                  'recent window.',
            ),
          );
        }

        // Server orders open first, then closed (per
        // `25_employer_profile.md`). Split at the first closed row so
        // the screen can label "Active jobs" vs. "History".
        final firstClosedIdx = page.items.indexWhere(
          (EmployerJob ej) => ej.status == EmployerJobStatus.closed,
        );
        final hasOpen = firstClosedIdx != 0;
        final hasClosed =
            firstClosedIdx >= 0 && firstClosedIdx < page.items.length;

        final activeRows = <Widget>[];
        if (hasOpen) {
          final upTo =
              firstClosedIdx == -1 ? page.items.length : firstClosedIdx;
          activeRows
            ..add(_SectionHeader(label: 'Active jobs'))
            ..add(const SizedBox(height: AppSpacing.md));
          for (int i = 0; i < upTo; i++) {
            final ej = page.items[i];
            activeRows
              ..add(JobCard(job: ej.job, onTap: () => onJobTap(ej.job)))
              ..add(const SizedBox(height: AppSpacing.md));
          }
        }

        final historyRows = <Widget>[];
        if (hasClosed) {
          historyRows
            ..add(const SizedBox(height: AppSpacing.sm))
            ..add(_SectionHeader(label: 'History'))
            ..add(const SizedBox(height: AppSpacing.md));
          for (int i = firstClosedIdx; i < page.items.length; i++) {
            final ej = page.items[i];
            historyRows
              ..add(
                Opacity(
                  opacity: 0.7,
                  child: JobCard(job: ej.job, onTap: () => onJobTap(ej.job)),
                ),
              )
              ..add(const SizedBox(height: AppSpacing.md));
          }
        }

        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[...activeRows, ...historyRows],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: palette.onSurfaceVariant,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: 60),
          Row(
            children: <Widget>[
              LoadingShimmer.circle(size: 72),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LoadingShimmer.line(width: 220, height: 22),
                    SizedBox(height: AppSpacing.xs),
                    LoadingShimmer.line(width: 140, height: 14),
                    SizedBox(height: AppSpacing.sm),
                    LoadingShimmer.line(width: 180, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xl),
          LoadingShimmer.box(width: double.infinity, height: 140),
          SizedBox(height: AppSpacing.lg),
          LoadingShimmer.line(width: 120, height: 16),
          SizedBox(height: AppSpacing.md),
          LoadingShimmer.box(width: double.infinity, height: 120),
        ],
      ),
    );
  }
}

