import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/location/current_location.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../jobs/widgets/live_map.dart';
import '../state/sessions_state.dart';
import '../state/work_session_controller.dart';

/// Clock-in confirmation. Brief: map showing user location vs. job
/// site, a 100m verification zone, status text, and a primary "Clock
/// In" CTA that's only enabled inside the zone.
///
/// Real builds wire this to the device GPS and a server-side geofence.
/// For static UI a "Simulate arrival" affordance flips the at-site
/// flag so judges can see both the disabled-outside and enabled-inside
/// states without leaving the room.
class ClockInScreen extends ConsumerStatefulWidget {
  const ClockInScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<ClockInScreen> createState() => _ClockInScreenState();
}

class _ClockInScreenState extends ConsumerState<ClockInScreen> {
  static const int _verificationRadius = 100;

  /// How early the worker is allowed to clock in relative to
  /// `job.startTime`. Anything earlier than this and the screen swaps
  /// the geofence flow for a "Starts in X minutes" countdown — there's
  /// no value in walking up to the site 40 minutes ahead and the
  /// employer-side state machine treats a too-early clock-in as a
  /// no-show risk anyway.
  static const Duration _earlyClockInWindow = Duration(minutes: 10);

  /// Re-poll `currentLocationProvider` every 5s so the worker doesn't
  /// have to pull-to-refresh as they walk into the geofence. Riverpod
  /// invalidate triggers the GeolocatorPlugin `getCurrentPosition`
  /// again — cheap on Android, ~1 s on iOS.
  Timer? _gpsTicker;

  /// Ticks once per second while the start-time countdown is showing,
  /// so the "Starts in 4:58" line updates live. Owned by this state
  /// (not the countdown widget) so it can be cancelled the moment the
  /// gate flips from "scheduled" to "ready".
  Timer? _countdownTicker;
  final ValueNotifier<int> _countdownTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _gpsTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(currentLocationProvider);
    });
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _countdownTick.value++;
    });
  }

  @override
  void dispose() {
    _gpsTicker?.cancel();
    _countdownTicker?.cancel();
    _countdownTick.dispose();
    super.dispose();
  }

  /// True when `job.startTime` is still further out than
  /// [_earlyClockInWindow]. In that case the entire geofence flow is
  /// hidden behind a countdown card — the worker shouldn't be told
  /// "you're too far" for a job that doesn't start for an hour.
  bool _isScheduledTooEarly(Job job) {
    return job.startTime.toLocal().difference(DateTime.now()) >
        _earlyClockInWindow;
  }

  bool _clockingIn = false;
  String? _clockInError;

  Future<void> _clockIn() async {
    if (_clockingIn) return;
    final session = ref.read(workSessionForJobProvider(widget.jobId));
    if (session == null) return;
    setState(() {
      _clockingIn = true;
      _clockInError = null;
    });
    try {
      // Re-read the GPS at submit time so we send the *current* fix to
      // the backend geofence check, not a stale one from when the
      // verification banner last flipped. accuracy_meters is mandatory
      // — the server rejects clock-ins where accuracy > 30 m.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
      final record =
          await ref.read(sessionsRepositoryProvider).clockIn(
                applicationId: session.application.id,
                lat: pos.latitude,
                lng: pos.longitude,
                accuracyMeters: pos.accuracy,
              );
      if (!mounted) return;
      final ctrl = ref.read(workSessionProvider.notifier);
      ctrl.setAtSite(widget.jobId, true);
      ctrl.clockIn(
        widget.jobId,
        serverSessionId: record.id,
        clockedInAt: record.clockInAt.toLocal(),
      );
      context.pushReplacement(RoutePaths.jobInProgress(widget.jobId));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _clockingIn = false;
        // Backend codes we expect here:
        //  OUTSIDE_GEOFENCE / LOCATION_ACCURACY_TOO_LOW → 422
        //  INVALID_STATE (already in_progress, application not accepted) → 409
        //  Other 4xx/5xx → render the server message
        _clockInError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clockingIn = false;
        _clockInError = "Couldn't clock in. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = ref.watch(workSessionForJobProvider(widget.jobId));

    if (session == null) {
      return Scaffold(
        backgroundColor: palette.surface,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const BackButtonHeader(),
              const Expanded(
                child: EmptyStateView(
                  title: 'No active session',
                  subtitle:
                      "Start from your accepted application to clock in.",
                ),
              ),
            ],
          ),
        ),
      );
    }

    final job = session.job;
    final scheduledTooEarly = _isScheduledTooEarly(job);

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // Top bar.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const BackButtonHeader(),
                  Expanded(
                    child: Text(
                      scheduledTooEarly ? 'Scheduled' : 'Clock in',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  // Symmetry spacer to balance the back button on the left.
                  const SizedBox(width: 44),
                ],
              ),
            ),

            if (scheduledTooEarly) ...<Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: _ScheduledGate(
                    job: job,
                    tick: _countdownTick,
                  ),
                ),
              ),
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
                    child: PrimaryButton(
                      label: 'Got it',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
            ] else ...<Widget>[
            // Live map + geofence banner.
            Expanded(
              child: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  final geoAsync = ref.watch(currentLocationProvider);
                  // Compute real distance from worker → job using
                  // haversine. While GPS is still resolving (or denied)
                  // we treat the worker as "not at site" — the map
                  // still renders the job pin so the user gets context.
                  final int? distanceM = geoAsync.maybeWhen(
                    data: (GeoPoint p) => distanceMeters(
                      p.lat, p.lng, job.locationLat, job.locationLng,
                    ).round(),
                    orElse: () => null,
                  );
                  final bool atSite = distanceM != null &&
                      distanceM <= _verificationRadius;
                  // Keep the controller in sync so downstream logic
                  // (e.g. clock-in API) can rely on `session.atSite`.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    final current = ref
                        .read(workSessionForJobProvider(widget.jobId));
                    if (current?.atSite != atSite) {
                      ref
                          .read(workSessionProvider.notifier)
                          .setAtSite(widget.jobId, atSite);
                    }
                  });
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppRadius.xl),
                            child: LiveMap(
                              jobs: <Job>[job],
                              focusedJobId: job.id,
                              interactive: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _StatusBanner(
                          status: geoAsync.hasError
                              ? _GeoStatus.unavailable
                              : distanceM == null
                                  ? _GeoStatus.locating
                                  : atSite
                                      ? _GeoStatus.atSite
                                      : _GeoStatus.tooFar,
                          distanceMeters: distanceM,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  );
                },
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
                  child: Consumer(
                    builder: (BuildContext context, WidgetRef ref, _) {
                      final session = ref
                          .watch(workSessionForJobProvider(widget.jobId));
                      final atSite = session?.atSite ?? false;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_clockInError != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm),
                              child: Text(
                                _clockInError!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: palette.error,
                                ),
                              ),
                            ),
                          PrimaryButton(
                            label: _clockingIn
                                ? 'Clocking in…'
                                : 'Clock In',
                            onPressed: (!atSite || _clockingIn)
                                ? null
                                : _clockIn,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pre-start gate. Renders when the worker reaches the clock-in route
/// before `job.startTime` is close enough to actually begin (further
/// out than [_ClockInScreenState._earlyClockInWindow]). The geofence
/// flow stays hidden until the gate clears — no point telling the
/// worker they're "too far away" for a job that doesn't start yet.
class _ScheduledGate extends StatelessWidget {
  const _ScheduledGate({required this.job, required this.tick});
  final Job job;
  final ValueListenable<int> tick;

  String _formatRemaining(Duration d) {
    if (d.isNegative) return '00:00';
    String two(int v) => v.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final s = d.inSeconds.remainder(60);
      return '${h}h ${two(m)}m ${two(s)}s';
    }
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
  }

  String _formatHuman(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inHours < 1) {
      final m = d.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'}';
    }
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (m == 0) return '$h ${h == 1 ? 'hour' : 'hours'}';
    return '$h ${h == 1 ? 'hr' : 'hrs'} $m min';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final timeFormat = DateFormat('EEE, MMM d · h:mm a');
    final startLocal = job.startTime.toLocal();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: palette.info.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.schedule_rounded,
                size: 48,
                color: palette.info,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ValueListenableBuilder<int>(
              valueListenable: tick,
              builder: (BuildContext _, int _, Widget? _) {
                final remaining =
                    startLocal.difference(DateTime.now());
                return Column(
                  children: <Widget>[
                    Text(
                      'Come back in ${_formatHuman(remaining)}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _formatRemaining(remaining),
                      style: AppTextStyles.displaySmall.copyWith(
                        color: palette.info,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.event_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Starts ${timeFormat.format(startLocal)}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.place_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          job.locationAddress,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "You'll be able to clock in once the start time is close.\n"
              "We'll send you a reminder.",
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Geofence state surfaced in the status banner. Drives icon, tint, and
/// copy in one place — every combination of (real GPS, denied GPS, near,
/// far) maps to exactly one of these.
enum _GeoStatus { locating, unavailable, tooFar, atSite }

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.status,
    required this.distanceMeters,
  });
  final _GeoStatus status;

  /// Null while GPS is still resolving or unavailable. Only read when
  /// [status] is `tooFar`.
  final int? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Color tint;
    final String text;
    final IconData icon;
    switch (status) {
      case _GeoStatus.atSite:
        tint = palette.success;
        text = "You're at the job site";
        icon = Icons.check_circle_rounded;
        break;
      case _GeoStatus.tooFar:
        tint = palette.error;
        text = "You're ${distanceMeters ?? 0}m away. "
            "Move within 100m to clock in.";
        icon = Icons.error_outline_rounded;
        break;
      case _GeoStatus.locating:
        tint = palette.onSurfaceVariant;
        text = 'Locating you…';
        icon = Icons.gps_not_fixed_rounded;
        break;
      case _GeoStatus.unavailable:
        tint = palette.error;
        text = 'Location unavailable. Turn on GPS to clock in.';
        icon = Icons.location_disabled_rounded;
        break;
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      borderColor: tint.withValues(alpha: 0.30),
      background: tint.withValues(alpha: 0.06),
      child: Row(
        children: <Widget>[
          Icon(icon, color: tint, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
