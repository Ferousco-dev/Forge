import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/directions/launch_directions.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/sharing/share_job.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/distance_text.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/network_image_with_fallback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../bookmarks/state/bookmarks_state.dart';
import '../../work/state/applications_state.dart';
import '../data/jobs_repository.dart';
import '../state/jobs_state.dart';
import '../widgets/map_view.dart';
import 'apply_confirmation_modal.dart';

/// Job detail. Loads via [jobDetailProvider] — same shape as
/// [jobByIdProvider] but exposes the embedded `viewer_application` so
/// the sticky CTA can flip between Apply / Pending+Withdraw / Clock-in
/// without a second round trip. All five `AsyncValue` states handled
/// inline.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final asyncDetail = ref.watch(jobDetailProvider(jobId));

    return Scaffold(
      backgroundColor: palette.surface,
      body: asyncDetail.when(
        loading: () => const _DetailSkeleton(),
        error: (Object _, StackTrace _) => SafeArea(
          child: Column(
            children: <Widget>[
              const _BackBar(),
              Expanded(
                child: ErrorStateView(
                  title: "Couldn't load this job",
                  message: 'Try again — the listing may still be available.',
                  onRetry: () => ref.invalidate(jobDetailProvider(jobId)),
                ),
              ),
            ],
          ),
        ),
        data: (JobDetail detail) {
          return _DetailContent(
            job: detail.job,
            viewerApplication: detail.viewerApplication,
            // Pull-to-refresh handler. Invalidating the provider drops
            // the cached response and triggers a fresh `GET /jobs/:id`,
            // which is how workers pick up an employer-side acceptance
            // (or a withdrawal, status flip, etc.) without restarting
            // the app. `read(...future)` waits for the refetch so the
            // RefreshIndicator spinner stays visible until the new data
            // lands — feels honest, not flickery.
            onRefresh: () async {
              ref.invalidate(jobDetailProvider(jobId));
              await ref.read(jobDetailProvider(jobId).future);
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.job,
    required this.viewerApplication,
    required this.onRefresh,
  });
  final Job job;
  final JobApplication? viewerApplication;

  /// Triggered by pull-to-refresh on the scroll view. The screen
  /// passes a closure that invalidates `jobDetailProvider(jobId)` —
  /// so workers can pick up status changes (employer accepted /
  /// rejected / withdrew the listing) without restarting the app.
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              // `edgeOffset` keeps the spinner clear of the floating
              // _BackBar pinned over the hero map — otherwise the
              // spinner draws underneath those buttons and looks broken.
              edgeOffset: 12,
              child: ListView(
                // Always-scrollable so the refresh gesture works even
                // when the content is shorter than the viewport
                // (otherwise short listings — no description, no
                // equipment list — couldn't be refreshed).
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.zero,
                children: <Widget>[
                _Hero(job: job),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        job.title,
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      CurrencyText(
                        amount: job.payAmount,
                        size: CurrencySize.large,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _QuickStatsRow(job: job),
                      const SizedBox(height: AppSpacing.xl),
                      _Section(
                        title: 'About this job',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              job.description,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: palette.onSurfaceVariant,
                                height: 1.55,
                              ),
                            ),
                            if (job.requiredEquipment.isNotEmpty) ...<Widget>[
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'Required equipment',
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: palette.onSurface,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: <Widget>[
                                  for (final String item in job.requiredEquipment)
                                    AppChip(label: item),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _LocationSection(job: job),
                      const SizedBox(height: AppSpacing.xl),
                      _EmployerSection(employer: job.employer),
                      const SizedBox(height: AppSpacing.xl),
                      _ImportantDetailsSection(job: job),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
          _StickyApply(job: job, application: viewerApplication),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Hero — map snippet behind a top bar
// ---------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        children: <Widget>[
          // Map fills the whole hero — `Positioned.fill` is the
          // semantically-correct way (replaces the previous
          // `StackFit.expand` which inadvertently expanded the bar
          // alongside the map and floated the buttons mid-air).
          Positioned.fill(
            child: MapView(
              jobs: <Job>[job],
              focusedJobId: job.id,
              interactive: false,
            ),
          ),
          // Back / save / share buttons pinned to the *top* of the
          // hero, full width.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _BackBar(showShare: true, bookmarkableJob: job),
          ),
        ],
      ),
    );
  }
}

class _BackBar extends ConsumerWidget {
  const _BackBar({this.showShare = false, this.bookmarkableJob});

  final bool showShare;

  /// When non-null, the bookmark icon toggles save/unsave for this
  /// job. When null (e.g. on a loading skeleton), the icon is hidden.
  /// Lives here rather than in a separate "BookmarkButton" widget so
  /// the existing trio of back/save/share spacing stays in one place.
  final Job? bookmarkableJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final job = bookmarkableJob;
    final bookmarkedIds = ref.watch(bookmarkedJobIdsProvider).valueOrNull;
    final isBookmarked =
        job != null && (bookmarkedIds?.contains(job.id) ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          _CircleIcon(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.maybePop(context),
          ),
          const Spacer(),
          if (showShare && job != null) ...<Widget>[
            _CircleIcon(
              icon: isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              tooltip: isBookmarked ? 'Saved' : 'Save',
              onTap: () async {
                final nowBookmarked = await toggleBookmark(ref, job);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(AppSpacing.base),
                    backgroundColor: palette.surfaceContainerHigh,
                    content: Text(
                      nowBookmarked
                          ? 'Saved to your jobs.'
                          : 'Removed from saved jobs.',
                      style: TextStyle(color: palette.onSurface),
                    ),
                  ));
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            _CircleIcon(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share',
              onTap: () => shareJob(job),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 20, color: palette.onSurface),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatTile(
            icon: Icons.schedule_rounded,
            label: 'Duration',
            value: '${job.durationHours}h',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            icon: Icons.straighten_rounded,
            label: 'Distance',
            value: job.distanceMeters < 1000
                ? '${job.distanceMeters}m'
                : '${(job.distanceMeters / 1000).toStringAsFixed(1)} km',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            icon: Icons.directions_walk_rounded,
            label: 'Travel',
            value: '${job.travelTimeWalkingMinutes} min',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: palette.primary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

class _LocationSection extends StatelessWidget {
  const _LocationSection({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Section(
      title: 'Location',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(Icons.location_on_rounded, color: palette.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    job.locationAddress,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy address',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: job.locationAddress));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(AppSpacing.base),
                        backgroundColor: palette.surfaceContainerHigh,
                        content: Text(
                          'Address copied.',
                          style: TextStyle(color: palette.onSurface),
                        ),
                      ));
                  },
                  icon: Icon(Icons.copy_rounded,
                      size: 18, color: palette.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextButton(
            label: 'Get directions',
            icon: const Icon(Icons.directions_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await launchDirections(
                destLat: job.locationLat,
                destLng: job.locationLng,
                destLabel: job.locationAddress,
              );
              if (!ok) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(AppSpacing.base),
                    backgroundColor: palette.surfaceContainerHigh,
                    content: Text(
                      "Couldn't open maps app.",
                      style: TextStyle(color: palette.onSurface),
                    ),
                  ));
              }
            },
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: SizedBox(
              height: 140,
              child: MapView(
                jobs: <Job>[job],
                focusedJobId: job.id,
                interactive: false,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DistanceText.travel(
            meters: job.distanceMeters,
            travelMinutes: job.travelTimeDrivingMinutes,
            mode: TravelMode.driving,
          ),
        ],
      ),
    );
  }
}

class _EmployerSection extends StatelessWidget {
  const _EmployerSection({required this.employer});
  final Employer employer;

  void _openProfile(BuildContext context) {
    context.push(RoutePaths.employerDetail(employer.id));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Section(
      title: 'About the employer',
      // Whole card is tappable — the InkWell sits inside the card so
      // the ripple respects the rounded corners. The "View profile"
      // button below is a redundant affordance for users who don't
      // realize the card itself is interactive.
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => _openProfile(context),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      NetworkImageWithFallback(
                        imageUrl: employer.photoUrl,
                        size: 48,
                        fallbackInitial: employer.name,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              employer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMedium.copyWith(
                                color: palette.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: <Widget>[
                                Icon(Icons.star_rounded,
                                    size: 14, color: palette.secondary),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    '${employer.rating.toStringAsFixed(1)} · '
                                    '${employer.jobsPosted} jobs posted',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: palette.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: palette.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          'Member since '
                          '${DateFormat.yMMM().format(employer.memberSince)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ),
                      AppTextButton(
                        label: 'View profile',
                        onPressed: () => _openProfile(context),
                        dense: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportantDetailsSection extends StatelessWidget {
  const _ImportantDetailsSection({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final timeFormat = DateFormat('EEE, MMM d · h:mm a');
    return _Section(
      title: 'Important details',
      child: AppCard(
        child: Column(
          children: <Widget>[
            _DetailRow(
              label: 'Start time',
              value: timeFormat.format(job.startTime.toLocal()),
              icon: Icons.event_rounded,
            ),
            Divider(height: 24, color: palette.outlineVariant),
            _DetailRow(
              label: 'Estimated duration',
              value: '${job.durationHours} hours',
              icon: Icons.timelapse_rounded,
            ),
            Divider(height: 24, color: palette.outlineVariant),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.bolt_rounded,
                        size: 18, color: palette.primary),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      'Payment method',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                AppChip(
                  label: 'Instant via Squad',
                  variant: AppChipVariant.tonal,
                  leading: Icon(
                    Icons.flash_on_rounded,
                    size: 12,
                    color: palette.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: palette.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Sticky bottom Apply
// ---------------------------------------------------------------------

/// Bottom-pinned CTA. Branches on the worker's [JobApplication] for
/// this job (carried in the job detail response via `viewer_application`
/// — see `endpoint_resources/03_job_detail.md`):
///
///   - `null` (never applied) → "Apply now"
///   - `applied`              → Pending banner + "Withdraw application"
///   - `accepted`             → "Clock in" (routes to the work flow)
///   - `inProgress`           → "Resume work" (also routes to work flow)
///   - `rejected`             → disabled "Application not accepted" state
///   - `completed`            → disabled "Job completed" state
///   - `withdrawn`            → "Apply again" (re-opens the apply sheet)
class _StickyApply extends ConsumerStatefulWidget {
  const _StickyApply({required this.job, required this.application});
  final Job job;
  final JobApplication? application;

  @override
  ConsumerState<_StickyApply> createState() => _StickyApplyState();
}

class _StickyApplyState extends ConsumerState<_StickyApply> {
  bool _withdrawing = false;

  Future<void> _confirmWithdraw() async {
    final application = widget.application;
    if (application == null) return;
    final palette = context.palette;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: palette.surface,
          title: const Text('Withdraw application?'),
          content: Text(
            "The employer will no longer see your application. You "
            "can apply again later if the job is still open.",
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep application'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: palette.error),
              child: const Text('Withdraw'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _withdrawing = true);
    try {
      await ref
          .read(applicationsRepositoryProvider)
          .withdraw(application.id);
      // Refresh both the job detail (so `viewer_application` flips to
      // withdrawn) and the active applications bucket (so the
      // withdrawn row leaves the active list).
      ref
        ..invalidate(jobDetailProvider(widget.job.id))
        ..invalidate(activeApplicationsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.base),
          backgroundColor: palette.surfaceContainerHigh,
          content: Text(
            'Application withdrawn.',
            style: TextStyle(color: palette.onSurface),
          ),
        ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.base),
          backgroundColor: palette.surfaceContainerHigh,
          content: Text(
            e.message,
            style: TextStyle(color: palette.error),
          ),
        ));
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final app = widget.application;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: _buildCta(palette, app),
        ),
      ),
    );
  }

  Widget _buildCta(AppColors palette, JobApplication? app) {
    // Not applied yet (null) OR previously withdrawn — both end up as
    // a clean "Apply" CTA. Withdrawn shows a one-line subtext so the
    // user knows where they're picking back up from.
    if (app == null || app.status == ApplicationStatus.withdrawn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (app?.status == ApplicationStatus.withdrawn) ...<Widget>[
            _StatusBanner(
              icon: Icons.history_rounded,
              tint: palette.onSurfaceVariant,
              label: 'You withdrew this application',
              detail: 'You can apply again if the job is still open.',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          PrimaryButton(
            label: app?.status == ApplicationStatus.withdrawn
                ? 'Apply again'
                : 'Apply now',
            onPressed: () => showApplyConfirmation(context, widget.job),
          ),
        ],
      );
    }

    switch (app.status) {
      case ApplicationStatus.applied:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StatusBanner(
              icon: Icons.hourglass_top_rounded,
              tint: palette.warning,
              label: 'Application pending',
              detail:
                  "We'll let you know as soon as the employer responds.",
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _withdrawing ? null : _confirmWithdraw,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.error,
                  side: BorderSide(
                    color: palette.error.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                child: _withdrawing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(palette.error),
                        ),
                      )
                    : const Text('Withdraw application'),
              ),
            ),
          ],
        );

      case ApplicationStatus.accepted:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StatusBanner(
              icon: Icons.check_circle_rounded,
              tint: palette.success,
              label: 'Accepted',
              detail: 'Head to the site to clock in.',
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'Clock in',
              onPressed: () =>
                  context.push(RoutePaths.jobClockIn(widget.job.id)),
            ),
          ],
        );

      case ApplicationStatus.inProgress:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StatusBanner(
              icon: Icons.work_history_rounded,
              tint: palette.success,
              label: 'On the clock',
              detail: 'Resume to finish the session.',
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'Resume work',
              onPressed: () =>
                  context.push(RoutePaths.jobInProgress(widget.job.id)),
            ),
          ],
        );

      case ApplicationStatus.rejected:
        return _DisabledCta(
          icon: Icons.cancel_outlined,
          label: 'Application not accepted',
          detail: 'This time around — try another nearby job.',
          tint: palette.error,
        );

      case ApplicationStatus.completed:
        return _DisabledCta(
          icon: Icons.task_alt_rounded,
          label: 'Job completed',
          detail: 'Payment has been processed.',
          tint: palette.success,
        );

      case ApplicationStatus.withdrawn:
        // Handled above by the null/withdrawn branch.
        return const SizedBox.shrink();
    }
  }
}

/// Inline status row that sits above the CTA — icon + label + detail.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.tint,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tint.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Terminal-state CTA placeholder — no action, just communicates
/// finality (rejected, completed).
class _DisabledCta extends StatelessWidget {
  const _DisabledCta({
    required this.icon,
    required this.label,
    required this.detail,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return _StatusBanner(
      icon: icon,
      tint: tint,
      label: label,
      detail: detail,
    );
  }
}

// ---------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _BackBar(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(height: AppSpacing.md),
                LoadingShimmer.box(width: double.infinity, height: 180),
                SizedBox(height: AppSpacing.lg),
                LoadingShimmer.line(width: 280, height: 22),
                SizedBox(height: AppSpacing.sm),
                LoadingShimmer.line(width: 120, height: 36),
                SizedBox(height: AppSpacing.lg),
                Row(
                  children: <Widget>[
                    Expanded(child: LoadingShimmer.box(width: 0, height: 76)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(child: LoadingShimmer.box(width: 0, height: 76)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(child: LoadingShimmer.box(width: 0, height: 76)),
                  ],
                ),
                SizedBox(height: AppSpacing.lg),
                LoadingShimmer.line(width: 160, height: 16),
                SizedBox(height: AppSpacing.sm),
                LoadingShimmer.line(width: double.infinity, height: 14),
                SizedBox(height: AppSpacing.xs),
                LoadingShimmer.line(width: 280, height: 14),
                SizedBox(height: AppSpacing.xs),
                LoadingShimmer.line(width: 220, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
