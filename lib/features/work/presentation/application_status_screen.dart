import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/work_session_controller.dart';

/// "You got the job!" hero screen for accepted applications.
///
/// Reached via a tap on an Accepted application from
/// `/profile/applications`, or directly via deep-link to
/// `/jobs/:id/status`. The screen looks up the application by job id
/// and starts a [WorkSession] in the [WorkPhase.accepted] phase. Tapping
/// "I've arrived" advances to clock-in.
class ApplicationStatusScreen extends ConsumerWidget {
  const ApplicationStatusScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final asyncApps = ref.watch(activeApplicationsProvider);

    return Scaffold(
      backgroundColor: palette.surface,
      body: asyncApps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => SafeArea(
          child: Column(
            children: <Widget>[
              const BackButtonHeader(),
              Expanded(
                child: ErrorStateView(
                  title: "Couldn't load this application",
                  message: 'Try again — we\'ll fetch your status.',
                  onRetry: () => ref.invalidate(activeApplicationsProvider),
                ),
              ),
            ],
          ),
        ),
        data: (List<JobApplication> apps) {
          final app = apps
              .where((JobApplication a) => a.job.id == jobId)
              .cast<JobApplication?>()
              .firstWhere(
                (JobApplication? a) => a != null,
                orElse: () => null,
              );

          if (app == null || app.status != ApplicationStatus.accepted) {
            return SafeArea(
              child: Column(
                children: <Widget>[
                  const BackButtonHeader(),
                  const Expanded(
                    child: EmptyStateView(
                      title: 'No accepted application here',
                      subtitle:
                          "Either this job isn't yours or its status has "
                          "changed. Head back to your applications.",
                    ),
                  ),
                ],
              ),
            );
          }

          return _Body(application: app);
        },
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.application});
  final JobApplication application;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  /// Ticks once a minute so the "I've arrived" CTA flips from disabled
  /// to enabled the moment we cross into the 30-min pre-start window.
  /// 1 Hz would be wasteful — the gate is minute-resolution.
  Timer? _gateTicker;

  /// How early before `start_time` the worker is allowed to mark
  /// themselves as arrived. Matches the operations rule: showing up
  /// more than half an hour early is treated as not-yet-arrived and
  /// the button stays locked.
  static const Duration _earlyArrivalWindow = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    // After the first frame, either (a) forward to the right in-flight
    // screen if this job's session has already moved past `accepted`,
    // or (b) start a fresh session in the `accepted` phase. Mutating
    // state in build would break Riverpod's invariants, hence the
    // post-frame callback.
    //
    // The forward-redirect is the fix for the "I've arrived shows again
    // after I already clocked in" bug. Before this guard, returning to
    // the status screen via the applications list would re-render the
    // CTA — and tapping it called `enterClockIn()`, which silently
    // regressed phase and reset elapsed time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final jobId = widget.application.job.id;
      final existing = ref.read(workSessionForJobProvider(jobId));
      if (existing != null && existing.phase != WorkPhase.accepted) {
        final target = _routeForPhase(jobId, existing);
        if (target != null) {
          context.pushReplacement(target);
          return;
        }
      }
      // No in-flight session, or session is in `accepted` — make sure
      // the controller has a fresh `accepted` entry for this job. The
      // controller's `start` method is itself a no-op when a session
      // for this job is already past `accepted`, so this can't trample
      // mid-flow state.
      ref.read(workSessionProvider.notifier).start(widget.application);
    });
    _gateTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Best resume route for a session that's already past `accepted`.
  /// Returns null for phases the status screen should keep rendering
  /// (only `accepted` today).
  String? _routeForPhase(String jobId, WorkSession s) {
    switch (s.phase) {
      case WorkPhase.accepted:
        return null;
      case WorkPhase.arriving:
        return RoutePaths.jobClockIn(jobId);
      case WorkPhase.working:
        return RoutePaths.jobInProgress(jobId);
      case WorkPhase.reviewing:
        return s.photoCaptured
            ? RoutePaths.jobClockOutReview(jobId)
            : RoutePaths.jobClockOutCamera(jobId);
      case WorkPhase.submitting:
        return RoutePaths.jobClockOutSubmitting(jobId);
      case WorkPhase.pendingReview:
        return RoutePaths.jobClockOutPending(jobId);
      case WorkPhase.done:
        return RoutePaths.jobClockOutComplete(jobId);
    }
  }

  @override
  void dispose() {
    _gateTicker?.cancel();
    super.dispose();
  }

  /// True once the current time is within [_earlyArrivalWindow] of the
  /// job's scheduled `start_time` (or past it). Drives the CTA enable
  /// state and the helper line under it.
  bool get _withinArrivalWindow {
    final start = widget.application.job.startTime;
    return DateTime.now().isAfter(start.subtract(_earlyArrivalWindow));
  }

  void _onArrived() {
    final jobId = widget.application.job.id;
    ref.read(workSessionProvider.notifier).enterClockIn(jobId);
    context.push(RoutePaths.jobClockIn(jobId));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final job = widget.application.job;

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          const BackButtonHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _SuccessHero(),
                  const SizedBox(height: AppSpacing.xl),
                  _RecapCard(job: job),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    "What's next?",
                    style: AppTextStyles.titleLarge.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _StepList(),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
          _StickyButton(
            onPressed: _withinArrivalWindow ? _onArrived : null,
            startTime: widget.application.job.startTime,
            unlocksWindow: _earlyArrivalWindow,
          ),
        ],
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: palette.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_circle_rounded,
            size: 56,
            color: palette.success,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'You got the job!',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The employer is expecting you.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final timeFormat = DateFormat('EEE, MMM d · h:mm a');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            job.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Icon(Icons.location_on_outlined,
                  size: 14, color: palette.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  job.locationAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Icon(Icons.event_rounded,
                  size: 14, color: palette.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  timeFormat.format(job.startTime.toLocal()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CurrencyText(amount: job.payAmount, size: CurrencySize.medium),
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList();

  static const List<({String title, String body, IconData icon})> _steps = [
    (
      title: 'Travel to the job site',
      body: 'Tap the directions link from the job detail to navigate.',
      icon: Icons.navigation_rounded,
    ),
    (
      title: "Tap 'I've arrived' when you're at the location",
      body: "We verify you're inside the work site to start the clock.",
      icon: Icons.location_on_outlined,
    ),
    (
      title: 'Complete the work and clock out',
      body:
          "When you're done, snap a quick photo to confirm and get paid.",
      icon: Icons.check_circle_outline_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _StepRow(index: i + 1, step: _steps[i]),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step});

  final int index;
  final ({String title, String body, IconData icon}) step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: AppTextStyles.titleSmall.copyWith(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.title,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(step.icon, size: 18, color: palette.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _StickyButton extends StatelessWidget {
  const _StickyButton({
    required this.onPressed,
    required this.startTime,
    required this.unlocksWindow,
  });
  final VoidCallback? onPressed;
  final DateTime startTime;
  final Duration unlocksWindow;

  /// Compact "Available in 2h 14m" / "Available in 12 min" rendering for
  /// the helper line that explains why the CTA is locked.
  String _untilUnlockLabel() {
    final unlocksAt = startTime.subtract(unlocksWindow);
    final remaining = unlocksAt.difference(DateTime.now());
    if (remaining.isNegative) return '';
    if (remaining.inHours >= 1) {
      final h = remaining.inHours;
      final m = remaining.inMinutes.remainder(60);
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    final mins = remaining.inMinutes;
    // Round up sub-minute residuals so "59s left" reads as "1 min", not "0 min".
    final shown = mins == 0 ? 1 : mins;
    return '$shown min';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final locked = onPressed == null;
    final untilLabel = locked ? _untilUnlockLabel() : '';
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
          child: Column(
            children: <Widget>[
              if (locked && untilLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    "Available in $untilLabel — you can check in 30 min before start.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              PrimaryButton(
                label: "I've arrived",
                onPressed: onPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
