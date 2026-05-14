import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/models.dart';
import '../../../core/uploads/uploads_repository.dart';
import '../../../core/uploads/uploads_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../earnings/state/earnings_state.dart';
import '../../loans/state/loans_state.dart';
import '../../profile/state/profile_state.dart';
import '../state/applications_state.dart';
import '../state/sessions_state.dart';
import '../state/work_session_controller.dart';

/// Submitting work — real upload + clock-out.
///
/// Flow:
///   1. Read the captured photo file at `session.photoPath`.
///   2. `POST /v1/uploads` with `purpose=clock_out_proof` → `upload_id`.
///   3. `POST /v1/sessions/:id/clock-out` with the upload id + the GPS
///      coords captured at photo-snap time (NOT a fresh fix — sending
///      stale-but-verified coords is the spec'd behaviour, and a fresh
///      fix might fail the 100 m geofence if the worker walked off-site
///      while uploading).
///
/// Status progression is driven off real milestones (upload start →
/// upload done → clock-out done) rather than a hardcoded timer, so the
/// progress bar stays honest on slow networks.
///
/// On any failure we stop the progress, surface the server's `message`,
/// and offer Retry / Back. The user keeps their photo and timer — no
/// state is reset until clock-out actually succeeds.
class SubmittingScreen extends ConsumerStatefulWidget {
  const SubmittingScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<SubmittingScreen> createState() => _SubmittingScreenState();
}

enum _SubmitPhase { uploading, clockingOut, done, error }

class _SubmittingScreenState extends ConsumerState<SubmittingScreen> {
  _SubmitPhase _phase = _SubmitPhase.uploading;

  /// 0..1, driven by real milestones (not an animation timer).
  ///  - 0.05 while we open the file.
  ///  - up to 0.60 once upload completes.
  ///  - 1.00 after clock-out succeeds.
  double _progress = 0.05;

  /// User-facing failure copy. Sourced from `ApiException.message` for
  /// known backend codes, generic fallback otherwise.
  String? _error;

  /// Server `error.code` for the latest failure — drives Retake vs.
  /// Retry copy on the action buttons.
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    // Kick off submit AFTER the first frame so we don't mutate
    // session state during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(workSessionProvider.notifier).enterSubmitting(widget.jobId);
      _submit();
    });
  }

  Future<void> _submit() async {
    final session = ref.read(workSessionForJobProvider(widget.jobId));
    if (session == null) {
      _fail('No active session.', code: 'NO_SESSION');
      return;
    }
    final path = session.photoPath;
    if (path == null) {
      _fail('Photo missing — retake.', code: 'NO_PHOTO');
      return;
    }
    final serverSessionId = session.serverSessionId;
    if (serverSessionId == null) {
      _fail(
        "We can't find your clock-in on the server. "
        'Pull to refresh on the timer screen and try again.',
        code: 'NO_SERVER_SESSION',
      );
      return;
    }
    final lat = session.clockOutLat;
    final lng = session.clockOutLng;
    final acc = session.clockOutAccuracy;
    if (lat == null || lng == null || acc == null) {
      _fail('Location reading missing — retake the photo.',
          code: 'NO_LOCATION');
      return;
    }

    // ---- 1. Upload the photo (skip if we have an unexpired cached id) ----
    //
    // The spec asks us to persist `upload_id` so an app kill between
    // the upload and the clock-out call doesn't force a re-upload.
    // The cached id lives on `WorkSession.proofUploadId` (mirrored
    // into SessionStorage) along with its `expires_at`. If the id is
    // still in date we ship it straight into Step 2.
    setState(() {
      _phase = _SubmitPhase.uploading;
      _progress = 0.10;
      _error = null;
      _errorCode = null;
    });
    ref
        .read(workSessionProvider.notifier)
        .setSubmissionProgress(widget.jobId, _progress);

    final String uploadId;
    final cachedId = session.proofUploadId;
    final cachedExpiresAt = session.proofUploadExpiresAt;
    final cachedStillValid = cachedId != null &&
        cachedExpiresAt != null &&
        cachedExpiresAt.isAfter(
          // 60s safety margin — if the id expires while the clock-out
          // request is in flight, the server will 422 UPLOAD_NOT_FOUND.
          DateTime.now().toUtc().add(const Duration(seconds: 60)),
        );

    if (cachedStillValid) {
      uploadId = cachedId;
      setState(() => _progress = 0.55);
      ref
          .read(workSessionProvider.notifier)
          .setSubmissionProgress(widget.jobId, _progress);
    } else {
      // No cached id (first attempt) OR cached id is past expiry.
      // Either way, run the upload fresh.
      try {
        final bytes = await File(path).readAsBytes();
        setState(() => _progress = 0.25);
        ref
            .read(workSessionProvider.notifier)
            .setSubmissionProgress(widget.jobId, _progress);
        final handle =
            await ref.read(uploadsRepositoryProvider).upload(
                  purpose: UploadPurpose.clockOutProof,
                  bytes: bytes,
                  filename: 'clock_out_${session.application.id}.jpg',
                  contentType: 'image/jpeg',
                );
        uploadId = handle.id;
        // Persist so the next retry / cold-start can skip Step 1.
        ref.read(workSessionProvider.notifier).markProofUploaded(
              widget.jobId,
              uploadId: handle.id,
              expiresAt: handle.expiresAt,
            );
      } on ApiException catch (e) {
        _fail(e.message, code: e.code);
        return;
      } on FileSystemException catch (e) {
        _fail("Couldn't read the photo: ${e.message}", code: 'FILE_IO');
        return;
      } catch (_) {
        _fail("Couldn't upload the photo. Try again.",
            code: 'UPLOAD_FAILED');
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _phase = _SubmitPhase.clockingOut;
      _progress = 0.60;
    });
    ref
        .read(workSessionProvider.notifier)
        .setSubmissionProgress(widget.jobId, _progress);

    // ---- 2. Clock out ----
    final WorkSessionRecord record;
    try {
      record = await ref.read(sessionsRepositoryProvider).clockOut(
            sessionId: serverSessionId,
            proofUploadId: uploadId,
            lat: lat,
            lng: lng,
            accuracyMeters: acc,
          );
    } on ApiException catch (e) {
      _fail(e.message, code: e.code);
      return;
    } catch (_) {
      _fail("Couldn't finalise clock-out. Try again.",
          code: 'CLOCK_OUT_FAILED');
      return;
    }

    if (!mounted) return;
    setState(() {
      _phase = _SubmitPhase.done;
      _progress = 1.0;
    });

    // Branch on the server's payout decision. If the server already
    // disbursed (`pay_amount_disbursed > 0`), this is the happy
    // synchronous path — straight to the work-complete celebration.
    //
    // Otherwise the server is holding the payment in the employer-
    // signed review window. Route to the pending-review screen, which
    // shows the countdown and polls for the eventual release.
    //
    // `hold_release_at` is read straight from the server response. If
    // the server hasn't shipped the field yet (pre-spec build), we
    // fall back to `now + 2h` so the UI still has something concrete
    // to count down to. See endpoint_resources/26_employer_signed_payouts.md.
    if (record.payAmountDisbursed > 0) {
      ref.read(workSessionProvider.notifier).complete(widget.jobId);
      // Job count just incremented server-side. Drop the cached
      // `/me` and `/credit` snapshots so the loans screen's unlock
      // gauge (`worker.jobsCompleted >= _minJobsForScore`) and the
      // AI credit score both reflect the new completion the moment
      // the worker opens the Loans tab. Without this, the cards still
      // read the stale `jobsCompleted` value from app launch and the
      // "Building your credit score" placeholder stays put even after
      // the threshold is met. We also nudge the earnings feed since
      // a fresh transaction just landed.
      _refreshCrossFeatureCaches();
      context.pushReplacement(
        RoutePaths.jobClockOutComplete(widget.jobId),
      );
    } else {
      final releaseAt = record.holdReleaseAt ??
          DateTime.now().toUtc().add(const Duration(hours: 2));
      ref.read(workSessionProvider.notifier).enterPendingReview(
            widget.jobId,
            holdReleaseAt: releaseAt,
            pendingAmount: record.payAmountPending,
          );
      context.pushReplacement(
        RoutePaths.jobClockOutPending(widget.jobId),
      );
    }
  }

  /// Invalidate every cached read whose value depends on this job's
  /// completion landing. Called from the two terminal transitions
  /// (synchronous payout here, and the auto-release path in
  /// [PendingReviewScreen]). Centralised so the list stays consistent
  /// between the two call sites — if one drifts it bites the unlock
  /// flow, the credit score, OR the earnings feed.
  void _refreshCrossFeatureCaches() {
    ref.invalidate(currentWorkerProvider);
    ref.invalidate(creditProfileProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(activeApplicationsProvider);
  }

  void _fail(String message, {required String code}) {
    if (!mounted) return;

    // `UPLOAD_NOT_FOUND` (server emits it from the clock-out call
    // when the cached upload has aged out past its 24h TTL OR was
    // never registered) means the stashed `proofUploadId` is dead.
    // Clear it immediately so any subsequent submit attempt — Retake
    // OR a "Back to review → Submit again" path — re-uploads the
    // photo cleanly. Without this clear, Try Again would skip Step 1
    // and re-hit the same 422 forever.
    if (code == 'UPLOAD_NOT_FOUND') {
      ref
          .read(workSessionProvider.notifier)
          .clearProofUpload(widget.jobId);
    }

    setState(() {
      _phase = _SubmitPhase.error;
      _error = message;
      _errorCode = code;
    });
  }

  String _stageLabel() {
    switch (_phase) {
      case _SubmitPhase.uploading:
        return 'Uploading photo';
      case _SubmitPhase.clockingOut:
        return 'Finalising clock-out';
      case _SubmitPhase.done:
        return 'Done';
      case _SubmitPhase.error:
        return 'Submit failed';
    }
  }

  /// When true, the Retry / Back row is shown instead of the spinner.
  bool get _hasError => _phase == _SubmitPhase.error;

  /// Errors where retrying with the same photo cannot succeed (the
  /// server has rejected the proof or the worker is off-site). Drives
  /// the Retake button.
  bool get _requiresRetake {
    switch (_errorCode) {
      case 'OUTSIDE_GEOFENCE':
      case 'PROOF_REJECTED':
      case 'UPLOAD_NOT_FOUND':
      case 'NO_PHOTO':
      case 'NO_LOCATION':
      case 'FILE_IO':
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stage = _stageLabel();
    return PopScope(
      // Don't allow back-nav while a network call is in flight — a
      // back during clock-out could leave the server in `pending_
      // verification` while the worker thinks the flow is dead.
      canPop: _hasError,
      child: Scaffold(
        backgroundColor: palette.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _UploadIllustration(
                  progress: _progress,
                  isError: _hasError,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  _hasError ? stage : '$stage...',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleLarge.copyWith(
                    color: _hasError
                        ? palette.error
                        : palette.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _hasError
                      ? (_error ?? 'Try again.')
                      : "Please don't close the app.",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!_hasError) ...<Widget>[
                  _ProgressBar(value: _progress),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${(_progress * 100).round()}%',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
                if (_hasError) ...<Widget>[
                  if (_requiresRetake)
                    PrimaryButton(
                      label: 'Retake photo',
                      onPressed: () {
                        ref
                            .read(workSessionProvider.notifier)
                            .retakePhoto(widget.jobId);
                        // Pop the submitting + review screens back to
                        // the camera.
                        context.pushReplacement(
                          RoutePaths.jobClockOutCamera(widget.jobId),
                        );
                      },
                    )
                  else
                    PrimaryButton(
                      label: 'Try again',
                      onPressed: _submit,
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  SecondaryButton(
                    label: 'Back to review',
                    onPressed: () => context.pop(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadIllustration extends StatelessWidget {
  const _UploadIllustration({
    required this.progress,
    required this.isError,
  });
  final double progress;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ringColor = isError ? palette.error : palette.primary;
    return SizedBox.square(
      dimension: 160,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: isError
                  ? palette.error.withValues(alpha: 0.10)
                  : palette.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(
            width: 168,
            height: 168,
            child: CircularProgressIndicator(
              value: isError ? 1.0 : progress.clamp(0.05, 1.0),
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
              backgroundColor: palette.outlineVariant,
            ),
          ),
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.cloud_upload_rounded,
            size: 64,
            color: ringColor,
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8,
        valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
        backgroundColor: palette.surfaceContainerHigh,
      ),
    );
  }
}
