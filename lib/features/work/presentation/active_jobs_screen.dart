import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/work_session_controller.dart';

/// Hub for every in-flight work session.
///
/// Reads [activeWorkSessionsProvider] (sorted by [WorkSession.priority])
/// and renders one row per session. Each row taps through to the right
/// resume route for the session's [WorkPhase]. From here the worker can
/// jump between, e.g., a job awaiting employer confirmation and a
/// freshly-accepted one without losing either's state.
class ActiveJobsScreen extends ConsumerWidget {
  const ActiveJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final sessions = ref.watch(activeWorkSessionsProvider);

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Active jobs'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: sessions.isEmpty
          ? EmptyStateView(
              title: 'No active jobs',
              subtitle:
                  'Apply for a job and it will appear here once the employer '
                  'accepts you.',
              illustration: Icon(
                Icons.work_outline_rounded,
                size: 56,
                color: palette.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              action: SizedBox(
                width: 200,
                child: PrimaryButton(
                  label: 'Browse jobs',
                  onPressed: () => context.go(RoutePaths.jobs),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: sessions.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (BuildContext context, int i) {
                final s = sessions[i];
                return _SessionRow(
                  session: s,
                  onTap: () => context.push(_resumeRouteFor(s)),
                );
              },
            ),
    );
  }
}

/// Human-friendly remaining-time string for scheduled-job rows.
/// Mirrors the helper in `jobs_screen.dart` so both surfaces produce
/// identical copy ("4 mins", "1h 12m").
String _humanRemaining(Duration d) {
  if (d.isNegative || d == Duration.zero) return 'now';
  if (d.inMinutes < 1) return 'less than a minute';
  if (d.inHours < 1) {
    final m = d.inMinutes;
    return '$m ${m == 1 ? 'min' : 'mins'}';
  }
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (m == 0) return '$h ${h == 1 ? 'hour' : 'hours'}';
  return '${h}h ${m}m';
}

String _resumeRouteFor(WorkSession s) {
  final id = s.job.id;
  switch (s.phase) {
    case WorkPhase.accepted:
      return RoutePaths.jobStatus(id);
    case WorkPhase.arriving:
      return RoutePaths.jobClockIn(id);
    case WorkPhase.working:
      return RoutePaths.jobInProgress(id);
    case WorkPhase.reviewing:
      return s.photoCaptured
          ? RoutePaths.jobClockOutReview(id)
          : RoutePaths.jobClockOutCamera(id);
    case WorkPhase.submitting:
      return RoutePaths.jobClockOutSubmitting(id);
    case WorkPhase.pendingReview:
      return RoutePaths.jobClockOutPending(id);
    case WorkPhase.done:
      return RoutePaths.jobClockOutComplete(id);
  }
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({required this.session, required this.onTap});
  final WorkSession session;
  final VoidCallback onTap;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  Timer? _ticker;
  // Drives the per-second secondary line (elapsed timer for `working`,
  // countdown for `pendingReview`) without rebuilding the rest of the
  // card. `tick` mutates but isn't read for value — listeners just
  // notice the change and re-read DateTime.now().
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final phase = widget.session.phase;
    // `working` and `pendingReview` always need the per-second ticker
    // (elapsed / countdown). For `accepted` / `arriving` we also tick
    // when the job's start time is still in the future so the
    // "Starts in 4 mins" line counts down in place.
    final bool scheduledAhead = widget.session.job.startTime
            .toLocal()
            .difference(DateTime.now()) >
        const Duration(minutes: 10);
    final bool needsTicker = phase == WorkPhase.working ||
        phase == WorkPhase.pendingReview ||
        ((phase == WorkPhase.accepted || phase == WorkPhase.arriving) &&
            scheduledAhead);
    if (needsTicker) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) _tick.value++;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = widget.session;
    final job = s.job;
    final (String chip, Color tint, IconData icon) = _chipFor(s.phase, palette);

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: tint.withValues(alpha: 0.25),
      background: tint.withValues(alpha: 0.05),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: tint),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        chip,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: tint,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job.employer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<int>(
                      valueListenable: _tick,
                      builder: (BuildContext _, int _, Widget? _) {
                        return Text(
                          _secondaryLine(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.onSurfaceVariant,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  CurrencyText(
                    amount: s.pendingAmount ?? job.payAmount,
                    size: CurrencySize.small,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: palette.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns chip text, tint colour, and lead icon for a phase. When
  /// the job's start time hasn't arrived yet (further out than
  /// 10 minutes), the chip degrades to "Scheduled" so the worker
  /// doesn't see "Heading to site" for a job that begins in an hour.
  (String, Color, IconData) _chipFor(WorkPhase phase, dynamic palette) {
    final bool scheduledAhead = widget.session.job.startTime
            .toLocal()
            .difference(DateTime.now()) >
        const Duration(minutes: 10);
    switch (phase) {
      case WorkPhase.accepted:
        if (scheduledAhead) {
          return (
            'Scheduled',
            palette.info as Color,
            Icons.schedule_rounded,
          );
        }
        return ('Accepted', palette.info as Color, Icons.event_available_rounded);
      case WorkPhase.arriving:
        if (scheduledAhead) {
          return (
            'Scheduled',
            palette.info as Color,
            Icons.schedule_rounded,
          );
        }
        return (
          'Heading to site',
          palette.info as Color,
          Icons.directions_walk_rounded,
        );
      case WorkPhase.working:
        return (
          'On the clock',
          palette.success as Color,
          Icons.timer_rounded,
        );
      case WorkPhase.reviewing:
        return (
          'Reviewing photo',
          palette.warning as Color,
          Icons.photo_camera_outlined,
        );
      case WorkPhase.submitting:
        return ('Submitting', palette.warning as Color, Icons.cloud_upload_rounded);
      case WorkPhase.pendingReview:
        return (
          'Awaiting confirmation',
          palette.warning as Color,
          Icons.hourglass_top_rounded,
        );
      case WorkPhase.done:
        return ('Complete', palette.success as Color, Icons.check_circle_rounded);
    }
  }

  String _secondaryLine(WorkSession s) {
    String two(int v) => v.toString().padLeft(2, '0');
    switch (s.phase) {
      case WorkPhase.working when s.clockedInAt != null:
        final d = DateTime.now().difference(s.clockedInAt!);
        final h = d.inHours;
        final m = d.inMinutes.remainder(60);
        final sec = d.inSeconds.remainder(60);
        return h > 0
            ? '${h}h ${two(m)}m ${two(sec)}s on the clock'
            : '${two(m)}:${two(sec)} on the clock';
      case WorkPhase.pendingReview when s.holdReleaseAt != null:
        final d = s.holdReleaseAt!.difference(DateTime.now().toUtc());
        if (d.isNegative) return 'Releasing payment…';
        final h = d.inHours;
        final m = d.inMinutes.remainder(60);
        final sec = d.inSeconds.remainder(60);
        return h > 0
            ? '${h}h ${two(m)}m until auto-release'
            : '${two(m)}:${two(sec)} until auto-release';
      case WorkPhase.accepted:
      case WorkPhase.arriving:
        final remaining =
            s.job.startTime.toLocal().difference(DateTime.now());
        if (remaining > const Duration(minutes: 10)) {
          return 'Starts in ${_humanRemaining(remaining)}';
        }
        return s.job.locationAddress;
      case WorkPhase.reviewing:
        return 'Tap to submit your work';
      case WorkPhase.submitting:
        return "Don't close the app — uploading";
      case WorkPhase.done:
        return 'Tap for receipt';
      // Fall-through for `working` / `pendingReview` without their
      // timestamps. Shouldn't happen in practice; keeps the UI honest.
      default:
        return s.job.locationAddress;
    }
  }
}
