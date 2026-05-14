import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/location/current_location.dart';
import '../state/work_session_controller.dart';

/// Maximum allowed distance between the worker's GPS and the job site
/// at the moment they capture the clock-out photo. Beyond this radius
/// the capture button is disabled — payment requires on-site proof.
const double _kGeofenceMeters = 100.0;

/// Camera-only clock-out capture.
///
/// Why no gallery option:
///   The brief requires the worker to PROVE the job is done on-site.
///   Allowing gallery uploads would let a worker submit a photo taken
///   earlier (or someone else's photo). [ImageSource.camera] forces
///   the OS to spin up the live camera UI, and we additionally
///   verify the worker's GPS against the job site at capture time.
///
/// Geofence verification:
///   1. On mount, we resolve the worker's current GPS in parallel
///      with rendering the UI.
///   2. The distance to the job site is computed via haversine and
///      shown live in a status pill. Refreshes when GPS updates.
///   3. The capture button is disabled while distance > 100m.
///   4. After the camera returns, we re-read GPS and re-check the
///      distance. If the worker walked away during capture, we
///      discard the photo and surface an error.
///
/// AI verification of the photo content (e.g. "this looks like a
/// loaded truck", "no faces detected") is a future enhancement —
/// [_aiVerifyPhoto] is a stub returning `true`, swap it for a model
/// call when that work lands.
class ClockOutCameraScreen extends ConsumerStatefulWidget {
  const ClockOutCameraScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<ClockOutCameraScreen> createState() =>
      _ClockOutCameraScreenState();
}

class _ClockOutCameraScreenState
    extends ConsumerState<ClockOutCameraScreen> {
  final ImagePicker _picker = ImagePicker();

  // Live distance to the job site, in metres. `null` until first GPS
  // fix lands.
  double? _distanceM;

  // True while we're actively reading GPS or launching the camera.
  bool _busy = false;

  // Last user-facing error (permission denied, off-site, etc.).
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshDistance();
  }

  /// Read the worker's current GPS and recompute distance to the
  /// job site. Surfaces a permission error if the OS denies us.
  Future<void> _refreshDistance() async {
    final session = ref.read(workSessionForJobProvider(widget.jobId));
    if (session == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _error = 'Location permission is required to verify you are '
              'on-site. Enable it in Settings.';
          _busy = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );

      final job = session.job;
      final d = distanceMeters(
        pos.latitude,
        pos.longitude,
        job.locationLat,
        job.locationLng,
      );

      if (!mounted) return;
      setState(() {
        _distanceM = d;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't read your location. Try again.";
        _busy = false;
      });
    }
  }

  bool get _onSite =>
      _distanceM != null && _distanceM! <= _kGeofenceMeters;

  /// Open the system camera, verify the post-capture GPS is still
  /// on-site, then commit the photo to the work session.
  Future<void> _capture() async {
    if (_busy) return;
    if (!_onSite) {
      _showSnack('You must be within ${_kGeofenceMeters.toInt()}m of '
          'the job site to take the photo.');
      return;
    }

    setState(() => _busy = true);

    try {
      // Camera ONLY — no gallery fallback. The plugin spins up the
      // native camera UI; gallery is not reachable from this entry
      // point.
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        // Cap at 1600 px on the long edge. The server's photo proof
        // verifier doesn't need full sensor resolution, and the review
        // screen has to decode this on the UI thread — anything bigger
        // (e.g. 2048+) blocks long enough to trip Android's ANR
        // watchdog on mid-range devices.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );

      if (shot == null) {
        // User cancelled the camera UI.
        if (mounted) setState(() => _busy = false);
        return;
      }

      // Re-verify after capture — the worker may have walked away
      // while the camera was open.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
      final session = ref.read(workSessionForJobProvider(widget.jobId));
      if (session == null || !mounted) return;
      final job = session.job;
      final dPost = distanceMeters(
        pos.latitude,
        pos.longitude,
        job.locationLat,
        job.locationLng,
      );
      if (dPost > _kGeofenceMeters) {
        setState(() {
          _distanceM = dPost;
          _busy = false;
        });
        _showSnack('Photo discarded — you walked outside the site '
            '(${dPost.toStringAsFixed(0)}m). Move back and try again.');
        return;
      }

      // Future: real AI verification (object detection, blur check,
      // duplicate detection). Stubbed to true for now.
      final aiOk = await _aiVerifyPhoto(shot.path);
      if (!aiOk) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack("Photo couldn't be verified. Take another.");
        return;
      }

      ref.read(workSessionProvider.notifier).markPhotoCaptured(
            widget.jobId,
            photoPath: shot.path,
            lat: pos.latitude,
            lng: pos.longitude,
            accuracyMeters: pos.accuracy,
          );

      if (!mounted) return;
      context.push(RoutePaths.jobClockOutReview(widget.jobId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't open the camera. Try again.";
      });
    }
  }

  /// Placeholder for the future AI check. Returns `true` so the flow
  /// works end-to-end today; swap this for a model call when the
  /// verification model is wired up.
  Future<bool> _aiVerifyPhoto(String path) async {
    if (kDebugMode) debugPrint('[ClockOutCamera] AI stub: $path');
    return true;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.lg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(workSessionForJobProvider(widget.jobId));
    final job = session?.job;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0B0F14),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F14),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _TopBar(jobAddress: job?.locationAddress),
              const SizedBox(height: AppSpacing.md),
              _GeofencePill(
                distanceM: _distanceM,
                onSite: _onSite,
                busy: _busy && _distanceM == null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: _Instruction(error: _error),
                ),
              ),
              _CaptureControls(
                enabled: _onSite && !_busy,
                busy: _busy,
                onCapture: _capture,
                onRefreshLocation: _refreshDistance,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.jobAddress});
  final String? jobAddress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Proof of work',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: const Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (jobAddress != null && jobAddress!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    jobAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Geofence status pill
// ---------------------------------------------------------------------

class _GeofencePill extends StatelessWidget {
  const _GeofencePill({
    required this.distanceM,
    required this.onSite,
    required this.busy,
  });

  final double? distanceM;
  final bool onSite;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;

    if (busy) {
      bg = const Color(0xFFFFFFFF).withValues(alpha: 0.08);
      fg = const Color(0xFFFFFFFF).withValues(alpha: 0.75);
      icon = Icons.gps_not_fixed_rounded;
      label = 'Reading location…';
    } else if (distanceM == null) {
      bg = const Color(0xFFFFFFFF).withValues(alpha: 0.08);
      fg = const Color(0xFFFFFFFF).withValues(alpha: 0.75);
      icon = Icons.gps_off_rounded;
      label = 'Location unavailable';
    } else if (onSite) {
      bg = const Color(0xFF10B981).withValues(alpha: 0.18);
      fg = const Color(0xFF34D399);
      icon = Icons.verified_rounded;
      label = 'On site · ${distanceM!.toStringAsFixed(0)}m away';
    } else {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.18);
      fg = const Color(0xFFFCA5A5);
      icon = Icons.location_off_rounded;
      label = 'Too far · ${distanceM!.toStringAsFixed(0)}m from site';
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Instructional copy + error display
// ---------------------------------------------------------------------

class _Instruction extends StatelessWidget {
  const _Instruction({required this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.photo_camera_rounded,
            color: Color(0xFFFFFFFF),
            size: 36,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Snap the finished work',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall.copyWith(
            color: const Color(0xFFFFFFFF),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'Take a clear photo of the completed job from where you '
            'stand. Payment is released once your location matches '
            'the job site.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.70),
              height: 1.4,
            ),
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color(0xFFFCA5A5),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Capture controls
// ---------------------------------------------------------------------

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.enabled,
    required this.busy,
    required this.onCapture,
    required this.onRefreshLocation,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onRefreshLocation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          _CircleIconButton(
            icon: Icons.my_location_rounded,
            onTap: busy ? null : onRefreshLocation,
            tooltip: 'Refresh location',
          ),
          Expanded(
            child: Center(
              child: Semantics(
                button: true,
                enabled: enabled,
                label: 'Take photo',
                child: GestureDetector(
                  onTap: enabled ? onCapture : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: enabled
                          ? const Color(0xFFFFFFFF).withValues(alpha: 0.10)
                          : const Color(0xFFFFFFFF).withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: enabled
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFFFFFFFF)
                                .withValues(alpha: 0.35),
                        width: 4,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: enabled
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFFFFFFFF)
                                  .withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: busy
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<
                                        Color>(Color(0xFF0B0F14)),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Symmetry spacer — gallery deliberately omitted so the
          // worker cannot upload a saved photo.
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF).withValues(alpha: 0.10),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              color: onTap == null
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.35)
                  : const Color(0xFFFFFFFF),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
