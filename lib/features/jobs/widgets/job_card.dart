import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/ai/ai_models.dart';
import '../../../core/ai/ai_state.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/distance_text.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/status_badge.dart';

/// The workhorse job-listing card.
///
/// Used in three places:
/// 1. The Jobs **list view** — `dense: false`, no status badge.
/// 2. The Jobs **map bottom sheet** — `dense: true`, no status badge.
/// 3. **My Applications** + **Work history** — full card with a
///    [StatusBadge] driven by the [application] argument.
///
/// One widget, one mental model. The dense variant simply hides the
/// description-style metadata rows (employer line, travel time) so a
/// stack of compact cards still fits inside a half-screen sheet.
class JobCard extends ConsumerWidget {
  const JobCard({
    super.key,
    required this.job,
    this.application,
    this.onTap,
    this.dense = false,
  });

  final Job job;
  final JobApplication? application;
  final VoidCallback? onTap;
  final bool dense;

  /// Whether the AI summary line is worth rendering on this card.
  ///
  /// We hide it only on dense (map-sheet) cards where vertical space
  /// is at a premium. Work-history and My-Applications cards (which
  /// pass [application]) still get the summary — it's a useful
  /// "remember what this job was about" anchor when the worker is
  /// scrolling past jobs from weeks ago.
  bool get _showSummary => !dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(dense ? AppSpacing.md : AppSpacing.base),
      borderRadius: dense ? AppRadius.allLg : AppRadius.allXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Top row: type + distance + (status badge if applicable).
          // Built with [Wrap] so the chips break to a second line on
          // narrow screens (e.g., a 360 dp Android with a long type
          // label like "General Labor" + an Accepted status badge).
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _JobTypePill(type: job.type),
              _DistanceBadge(meters: job.distanceMeters),
              if (application != null)
                StatusBadge(
                  label: application!.status.label,
                  tone: _toneFor(application!.status),
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Title.
          Text(
            job.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),

          // AI summary line — soft-fail (renders nothing on loading,
          // error, or empty response). See endpoint_resources/ai.md
          // section 1.
          if (_showSummary) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _JobSummaryView(jobId: job.id, palette: palette),
          ],

          if (!dense) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // Location.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: palette.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    // Short area label — first segment of the full
                    // address or the neighborhood name. Full address
                    // is rendered on the job-detail screen.
                    job.areaLabel,
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

          const SizedBox(height: AppSpacing.md),

          // Pay row + travel time. Travel text gets `Flexible` so it
          // can shrink/clip on narrow screens instead of overflowing.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              CurrencyText(
                amount: job.payAmount,
                size: dense ? CurrencySize.small : CurrencySize.medium,
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!dense)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: DistanceText.travel(
                      meters: job.distanceMeters,
                      travelMinutes: _bestTravelMinutes(job),
                      mode: _bestTravelMode(job),
                    ),
                  ),
                ),
            ],
          ),

          if (!dense && application == null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: palette.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            // Employer + rating.
            Row(
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: palette.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    // Guard against empty employer names — substring(0, 1)
                    // throws RangeError on '', and one bad row would
                    // crash the whole feed since JobCard is rendered
                    // for every job. `'?'` is the catch-all initial.
                    job.employer.name.isEmpty
                        ? '?'
                        : job.employer.name.characters.first.toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: palette.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    job.employer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.star_rounded, size: 14, color: palette.secondary),
                const SizedBox(width: 2),
                Text(
                  job.employer.rating.toStringAsFixed(1),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static StatusBadgeTone _toneFor(ApplicationStatus s) => switch (s) {
        ApplicationStatus.applied => StatusBadgeTone.info,
        ApplicationStatus.accepted => StatusBadgeTone.success,
        ApplicationStatus.rejected => StatusBadgeTone.error,
        ApplicationStatus.inProgress => StatusBadgeTone.info,
        ApplicationStatus.completed => StatusBadgeTone.neutral,
        ApplicationStatus.withdrawn => StatusBadgeTone.neutral,
      };

  static int _bestTravelMinutes(Job j) =>
      j.distanceMeters > 1500
          ? j.travelTimeDrivingMinutes
          : j.travelTimeWalkingMinutes;

  static TravelMode _bestTravelMode(Job j) =>
      j.distanceMeters > 1500 ? TravelMode.driving : TravelMode.walking;
}

class _JobTypePill extends StatelessWidget {
  const _JobTypePill({required this.type});
  final JobType type;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(type.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            type.label,
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  const _DistanceBadge({required this.meters});
  final int meters;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: DistanceText(
        meters: meters,
        style: AppTextStyles.labelSmall,
        color: palette.onSurfaceVariant,
      ),
    );
  }
}

/// Skeleton loader rendered while [nearbyJobsProvider] resolves.
///
/// Matches the size and rhythm of a real [JobCard] so the layout
/// doesn't shift when data arrives — same outer shape, same internal
/// row count. Used five-up on the Jobs list per the brief.
class JobCardSkeleton extends StatelessWidget {
  const JobCardSkeleton({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(dense ? AppSpacing.md : AppSpacing.base),
      borderRadius: dense ? AppRadius.allLg : AppRadius.allXl,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              LoadingShimmer.box(width: 84, height: 22),
              SizedBox(width: AppSpacing.sm),
              LoadingShimmer.box(width: 56, height: 22),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          LoadingShimmer.line(width: 240, height: 14),
          SizedBox(height: AppSpacing.xs),
          LoadingShimmer.line(width: 180, height: 12),
          SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              LoadingShimmer.box(width: 110, height: 28),
              Spacer(),
              LoadingShimmer.box(width: 88, height: 16),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small line that renders the AI-generated job summary + 0–4 chip
/// highlights when available. Designed to be additive — when the
/// provider is loading, errored, or returns an empty summary the
/// widget collapses to `SizedBox.shrink()` so the card looks
/// identical to the pre-AI version.
class _JobSummaryView extends ConsumerWidget {
  const _JobSummaryView({required this.jobId, required this.palette});

  final String jobId;
  final AppColors palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(jobSummaryProvider(jobId));

    return summaryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (Object _, StackTrace _) => const SizedBox.shrink(),
      data: (JobSummary s) {
        if (s.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (s.summary.isNotEmpty)
              Text(
                s.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            if (s.highlights.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final h in s.highlights)
                    _HighlightChip(label: h.label, value: h.value, palette: palette),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HighlightChip extends StatelessWidget {
  const _HighlightChip({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final AppColors palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label  ',
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
