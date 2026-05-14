import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/dialer/launch_call.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../state/work_session_controller.dart';

/// Live work timer + clock-out gate.
///
/// Brief calls for a 5-minute minimum work duration. The CTA is
/// disabled with a countdown until [WorkSession.minimumDuration] has
/// elapsed since `clockedInAt`.
///
/// We render with a long-running periodic [Timer] (1 Hz) so the timer
/// updates every second without rebuilding the whole tree. Stops on
/// dispose.
class WorkInProgressScreen extends ConsumerStatefulWidget {
  const WorkInProgressScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<WorkInProgressScreen> createState() =>
      _WorkInProgressScreenState();
}

class _WorkInProgressScreenState extends ConsumerState<WorkInProgressScreen> {
  Timer? _ticker;
  bool _detailsExpanded = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final palette = context.palette;
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: palette.surface,
          title: Text(
            'Cancel this session?',
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
            ),
          ),
          content: Text(
            "You'll lose the elapsed time on this job and won't be paid for it. "
            'This cannot be undone.',
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Keep working',
                style: TextStyle(color: palette.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Cancel session',
                style: TextStyle(color: palette.error),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    ref.read(workSessionProvider.notifier).remove(widget.jobId);
    router.go(RoutePaths.jobs);
  }

  String _format(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}'
        ':${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = ref.watch(workSessionForJobProvider(widget.jobId));

    if (session == null || session.clockedInAt == null) {
      return Scaffold(
        backgroundColor: palette.surface,
        body: const SafeArea(
          child: EmptyStateView(
            title: 'No active session',
            subtitle: "You haven't clocked in to this job.",
          ),
        ),
      );
    }

    final elapsed = DateTime.now().difference(session.clockedInAt!);
    final minimum = WorkSession.minimumDuration;
    final canClockOut = elapsed >= minimum;
    final remaining = minimum - elapsed;

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // Top bar.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      session.job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: palette.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: palette.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'On the clock',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: palette.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    _TimerHero(time: _format(elapsed)),
                    const SizedBox(height: AppSpacing.xl),
                    _PayCard(amount: session.job.payAmount),
                    const SizedBox(height: AppSpacing.lg),
                    _DetailsCard(
                      session: session,
                      expanded: _detailsExpanded,
                      onToggle: () => setState(
                        () => _detailsExpanded = !_detailsExpanded,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _HelpCard(
                      employerPhoneNumber:
                          session.job.employer.phoneNumber,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),

            // Sticky CTA.
            Container(
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
                      if (!canClockOut)
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm),
                          child: Text(
                            'Clock out in ${_format(remaining)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ),
                      PrimaryButton(
                        label: 'Clock out',
                        onPressed: canClockOut
                            ? () => context.push(
                                  RoutePaths.jobClockOutCamera(
                                      session.job.id),
                                )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryButton(
                        label: 'Cancel session',
                        color: palette.error,
                        onPressed: () => _confirmCancel(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerHero extends StatelessWidget {
  const _TimerHero({required this.time});
  final String time;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Text(
          'Time on the job',
          style: AppTextStyles.labelMedium.copyWith(
            color: palette.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          time,
          style: AppTextStyles.displayLarge.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
            fontFeatures: const <FontFeature>[
              FontFeature.tabularFigures(),
            ],
          ),
        ),
      ],
    );
  }
}

class _PayCard extends StatelessWidget {
  const _PayCard({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: <Widget>[
          Icon(Icons.payments_rounded, size: 28, color: palette.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Pay on completion',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                CurrencyText(amount: amount, size: CurrencySize.medium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.session,
    required this.expanded,
    required this.onToggle,
  });
  final WorkSession session;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Job details',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                0,
                AppSpacing.base,
                AppSpacing.base,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Divider(height: 1, color: palette.outlineVariant),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    session.job.locationAddress,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    session.job.description,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(height: 0, width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.employerPhoneNumber});

  /// Number to launch into the platform dialer when the worker taps
  /// "Call employer". May be null when the employer hasn't published
  /// a contact number — we surface a snackbar in that case.
  final String? employerPhoneNumber;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Need help?',
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _HelpAction(
                  icon: Icons.call_rounded,
                  label: 'Call employer',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await launchPhoneCall(employerPhoneNumber);
                    if (!ok) {
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              "No phone number on file for this employer.",
                            ),
                          ),
                        );
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HelpAction(
                  icon: Icons.flag_outlined,
                  label: 'Report issue',
                  onTap: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpAction extends StatelessWidget {
  const _HelpAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
