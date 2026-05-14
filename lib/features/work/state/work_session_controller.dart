import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock/models.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/state/auth_state.dart';

/// Phase of an active work session — drives which screen renders and
/// which transitions are valid. Mirrors the brief's flow:
///
///     accepted → arriving → working → reviewing → submitting → done
enum WorkPhase {
  /// Application was accepted; worker is still off-site.
  accepted('accepted'),

  /// Worker is en route, on the clock-in screen.
  arriving('arriving'),

  /// Worker has clocked in; live timer is running.
  working('working'),

  /// Worker captured a clock-out photo and is reviewing it.
  reviewing('reviewing'),

  /// Submission in flight (upload → verify → payout).
  submitting('submitting'),

  /// Clock-out was accepted by the server but the payment is held in
  /// the employer-signed payout window. Worker waits on either an
  /// employer confirm/dispute or the auto-release timer.
  /// See `endpoint_resources/26_employer_signed_payouts.md`.
  pendingReview('pending_review'),

  /// All done; work complete screen.
  done('done');

  const WorkPhase(this.wire);

  /// Stable string used when persisting the phase to disk.
  final String wire;

  static WorkPhase fromWire(String wire) {
    for (final p in WorkPhase.values) {
      if (p.wire == wire) return p;
    }
    return WorkPhase.accepted;
  }
}

/// Snapshot of a single work session for one job.
@immutable
class WorkSession {
  const WorkSession({
    required this.application,
    required this.phase,
    this.clockedInAt,
    this.atSite = false,
    this.photoCaptured = false,
    this.photoPath,
    this.submissionProgress = 0,
    this.serverSessionId,
    this.clockOutLat,
    this.clockOutLng,
    this.clockOutAccuracy,
    this.holdReleaseAt,
    this.pendingAmount,
    this.proofUploadId,
    this.proofUploadExpiresAt,
  });

  final JobApplication application;
  final WorkPhase phase;
  final DateTime? clockedInAt;
  final bool atSite;
  final bool photoCaptured;
  final String? photoPath;
  final double submissionProgress;
  final String? serverSessionId;
  final double? clockOutLat;
  final double? clockOutLng;
  final double? clockOutAccuracy;
  final DateTime? holdReleaseAt;
  final int? pendingAmount;
  final String? proofUploadId;
  final DateTime? proofUploadExpiresAt;

  Job get job => application.job;

  /// Minimum work duration before the worker can clock out — per the
  /// brief, 5 minutes.
  static const Duration minimumDuration = Duration(minutes: 5);

  /// Sort key for picking the "primary" session when more than one is
  /// in flight. Lower number = more attention-worthy. Arriving sits at
  /// the top because the worker is physically en route; pendingReview
  /// is parked at the bottom because the wait is server-side.
  int get priority {
    switch (phase) {
      case WorkPhase.arriving:
        return 0;
      case WorkPhase.working:
        return 1;
      case WorkPhase.reviewing:
        return 2;
      case WorkPhase.submitting:
        return 3;
      case WorkPhase.accepted:
        return 4;
      case WorkPhase.pendingReview:
        return 5;
      case WorkPhase.done:
        return 6;
    }
  }

  WorkSession copyWith({
    JobApplication? application,
    WorkPhase? phase,
    DateTime? clockedInAt,
    bool? atSite,
    bool? photoCaptured,
    String? photoPath,
    double? submissionProgress,
    String? serverSessionId,
    double? clockOutLat,
    double? clockOutLng,
    double? clockOutAccuracy,
    DateTime? holdReleaseAt,
    int? pendingAmount,
    String? proofUploadId,
    DateTime? proofUploadExpiresAt,
    bool clearProofUpload = false,
  }) {
    return WorkSession(
      application: application ?? this.application,
      phase: phase ?? this.phase,
      clockedInAt: clockedInAt ?? this.clockedInAt,
      atSite: atSite ?? this.atSite,
      photoCaptured: photoCaptured ?? this.photoCaptured,
      photoPath: photoPath ?? this.photoPath,
      submissionProgress: submissionProgress ?? this.submissionProgress,
      serverSessionId: serverSessionId ?? this.serverSessionId,
      clockOutLat: clockOutLat ?? this.clockOutLat,
      clockOutLng: clockOutLng ?? this.clockOutLng,
      clockOutAccuracy: clockOutAccuracy ?? this.clockOutAccuracy,
      holdReleaseAt: holdReleaseAt ?? this.holdReleaseAt,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      proofUploadId: clearProofUpload
          ? null
          : (proofUploadId ?? this.proofUploadId),
      proofUploadExpiresAt: clearProofUpload
          ? null
          : (proofUploadExpiresAt ?? this.proofUploadExpiresAt),
    );
  }
}

/// Multi-session controller. State is a map keyed by `Job.id` so each
/// in-flight job has its own [WorkSession]. Workers can have any number
/// of jobs in flight at once — one in `pendingReview` awaiting employer
/// confirmation, another freshly accepted, another on the clock.
///
/// All mutators take a `jobId` to disambiguate. Screens look up their
/// session via [workSessionForJobProvider] (a family keyed by jobId)
/// rather than reading the entire map.
///
/// **Persistence:** every mutation mirrors the full session list to
/// [SessionStorage]. Writes are fire-and-forget; flutter_secure_storage
/// atomically writes per-key so a crash mid-mutation can't corrupt the
/// blob.
class WorkSessionController extends Notifier<Map<String, WorkSession>> {
  @override
  Map<String, WorkSession> build() => const <String, WorkSession>{};

  SessionStorage get _storage => ref.read(sessionStorageProvider);

  // ---- Persistence -------------------------------------------------

  void _persist() {
    final sessions = state.values
        .map((WorkSession s) => PersistedWorkSession(
              jobId: s.job.id,
              applicationId: s.application.id,
              phase: s.phase.wire,
              clockedInAt: s.clockedInAt,
              serverSessionId: s.serverSessionId,
              proofUploadId: s.proofUploadId,
              proofUploadExpiresAt: s.proofUploadExpiresAt,
            ))
        .toList(growable: false);
    unawaited(_storage.writeActiveSessions(sessions));
  }

  /// Resume sessions from disk. Called from the splash gate after auth
  /// resolves. Re-fetches each [JobApplication] from the server so a
  /// stale local copy can't override authoritative server state.
  ///
  /// Sessions that are already terminal — `done`, or `pendingReview`
  /// past their hold-release timestamp — are dropped here rather than
  /// rehydrated. They've already paid out; keeping them in the active
  /// list shows ghost "Heading to site" / "On the clock" cards for
  /// jobs the worker has already collected on.
  Future<void> restoreFromStorage(
    Future<JobApplication?> Function(String applicationId) fetchApplication,
  ) async {
    final pointers = await _storage.readActiveSessions();
    if (pointers.isEmpty) return;

    final next = <String, WorkSession>{};
    for (final p in pointers) {
      final phase = WorkPhase.fromWire(p.phase);
      // Drop any terminal session — `done` is unambiguous; we don't
      // persist holdReleaseAt today so a stale pendingReview gets a
      // fresh fetch a few lines down rather than a synthetic skip here.
      if (phase == WorkPhase.done) continue;
      final application = await fetchApplication(p.applicationId);
      if (application == null) continue;
      // Server-side terminal status wins. If the application is already
      // marked `completed` (employer/auto-released), the worker has
      // been paid — don't rebuild a session card for it.
      if (application.status == ApplicationStatus.completed) continue;
      next[application.job.id] = WorkSession(
        application: application,
        phase: phase,
        clockedInAt: p.clockedInAt,
        serverSessionId: p.serverSessionId,
        proofUploadId: p.proofUploadId,
        proofUploadExpiresAt: p.proofUploadExpiresAt,
      );
    }

    state = next;
    // If the server dropped any of the persisted applications, rewrite
    // the cache so we don't keep retrying them on every cold start.
    if (next.length != pointers.length) _persist();
  }

  // ---- Mutators ----------------------------------------------------

  /// Begin (or restart) a session for an accepted application. If a
  /// session for this job is already in flight, leaves it untouched.
  ///
  /// This is the guard the old single-session model lacked: applying
  /// to a NEW job no longer wipes the existing session for some OTHER
  /// job. Each job gets its own slot keyed by `Job.id`.
  void start(JobApplication application) {
    final jobId = application.job.id;
    final existing = state[jobId];
    // Same job, already past `accepted`: don't regress. The status
    // screen handles forwarding the worker to the right in-flight
    // screen instead of dropping them back at "I've arrived".
    if (existing != null && existing.phase != WorkPhase.accepted) return;
    state = <String, WorkSession>{
      ...state,
      jobId: WorkSession(
        application: application,
        phase: WorkPhase.accepted,
      ),
    };
    _persist();
  }

  void _update(String jobId, WorkSession Function(WorkSession) f) {
    final s = state[jobId];
    if (s == null) return;
    state = <String, WorkSession>{...state, jobId: f(s)};
    _persist();
  }

  /// Move from accepted → arriving when the user taps "I've arrived".
  /// Guards against phase regression — if the worker is already on the
  /// clock (working / reviewing / submitting / pendingReview), this is
  /// a no-op. Without the guard, tapping "I've arrived" again from the
  /// status screen would reset elapsed time.
  void enterClockIn(String jobId) {
    final s = state[jobId];
    if (s == null) return;
    if (s.phase != WorkPhase.accepted) return;
    _update(jobId, (s) => s.copyWith(phase: WorkPhase.arriving));
  }

  /// Toggle the at-site flag while the user is on the clock-in screen.
  void setAtSite(String jobId, bool atSite) {
    final s = state[jobId];
    if (s == null) return;
    // `atSite` is transient UI state — write to in-memory state but
    // skip persistence. On a cold start the geofence re-resolves.
    state = <String, WorkSession>{
      ...state,
      jobId: s.copyWith(atSite: atSite),
    };
  }

  /// Commit the clock-in. Only valid in the `arriving` phase + at-site.
  void clockIn(
    String jobId, {
    String? serverSessionId,
    DateTime? clockedInAt,
  }) {
    final s = state[jobId];
    if (s == null || s.phase != WorkPhase.arriving || !s.atSite) return;
    _update(
      jobId,
      (s) => s.copyWith(
        phase: WorkPhase.working,
        clockedInAt: clockedInAt ?? DateTime.now(),
        serverSessionId: serverSessionId,
      ),
    );
  }

  void markPhotoCaptured(
    String jobId, {
    String? photoPath,
    double? lat,
    double? lng,
    double? accuracyMeters,
  }) {
    _update(
      jobId,
      (s) => s.copyWith(
        phase: WorkPhase.reviewing,
        photoCaptured: true,
        photoPath: photoPath,
        clockOutLat: lat,
        clockOutLng: lng,
        clockOutAccuracy: accuracyMeters,
      ),
    );
  }

  void retakePhoto(String jobId) {
    _update(
      jobId,
      (s) => s.copyWith(photoCaptured: false, clearProofUpload: true),
    );
  }

  void markProofUploaded(
    String jobId, {
    required String uploadId,
    required DateTime expiresAt,
  }) {
    _update(
      jobId,
      (s) => s.copyWith(
        proofUploadId: uploadId,
        proofUploadExpiresAt: expiresAt,
      ),
    );
  }

  void clearProofUpload(String jobId) {
    _update(jobId, (s) => s.copyWith(clearProofUpload: true));
  }

  void enterSubmitting(String jobId) {
    _update(
      jobId,
      (s) => s.copyWith(phase: WorkPhase.submitting, submissionProgress: 0),
    );
  }

  void setSubmissionProgress(String jobId, double progress) {
    final s = state[jobId];
    if (s == null) return;
    // Animation state — in-memory only.
    state = <String, WorkSession>{
      ...state,
      jobId: s.copyWith(submissionProgress: progress.clamp(0, 1)),
    };
  }

  void enterPendingReview(
    String jobId, {
    required DateTime holdReleaseAt,
    required int pendingAmount,
  }) {
    _update(
      jobId,
      (s) => s.copyWith(
        phase: WorkPhase.pendingReview,
        holdReleaseAt: holdReleaseAt,
        pendingAmount: pendingAmount,
        submissionProgress: 1.0,
      ),
    );
  }

  void complete(String jobId) {
    _update(
      jobId,
      (s) => s.copyWith(phase: WorkPhase.done, submissionProgress: 1),
    );
  }

  /// Drop a session entirely. Called when the worker leaves the
  /// success screen or cancels mid-flow. Other sessions are untouched.
  void remove(String jobId) {
    if (!state.containsKey(jobId)) return;
    final next = <String, WorkSession>{...state}..remove(jobId);
    state = next;
    _persist();
  }

  /// Drop every terminal session — `done`, or `pendingReview` whose
  /// hold window has elapsed. Called opportunistically on screen
  /// resumes so the active-jobs list and the persisted blob stay
  /// honest even if the worker navigated away from the success screen
  /// without tapping "Find more jobs".
  void purgeTerminal() {
    final now = DateTime.now().toUtc();
    final next = <String, WorkSession>{};
    bool changed = false;
    for (final entry in state.entries) {
      final s = entry.value;
      if (s.phase == WorkPhase.done) {
        changed = true;
        continue;
      }
      if (s.phase == WorkPhase.pendingReview &&
          s.holdReleaseAt != null &&
          s.holdReleaseAt!.isBefore(now)) {
        changed = true;
        continue;
      }
      next[entry.key] = s;
    }
    if (!changed) return;
    state = next;
    _persist();
  }

  /// Clear every session. Used on logout or a hard reset.
  void clear() {
    if (state.isEmpty) return;
    state = const <String, WorkSession>{};
    _persist();
  }
}

final NotifierProvider<WorkSessionController, Map<String, WorkSession>>
    workSessionProvider =
    NotifierProvider<WorkSessionController, Map<String, WorkSession>>(
  WorkSessionController.new,
);

/// Look up a single session by `Job.id`. Returns null when no session
/// is in flight for that job.
final ProviderFamily<WorkSession?, String> workSessionForJobProvider =
    Provider.family<WorkSession?, String>((Ref ref, String jobId) {
  final sessions = ref.watch(workSessionProvider);
  return sessions[jobId];
});

/// Every in-flight session, sorted by [WorkSession.priority]. Drives
/// the new Active Jobs screen and the home-screen card picker.
///
/// Terminal sessions are filtered out:
/// - `done` is fully settled (paid + receipt seen); it belongs in
///   earnings, not on the "in flight" list.
/// - `pendingReview` whose `holdReleaseAt` has already passed is treated
///   the same — the auto-release window has elapsed, the worker has
///   been paid, and the card was only ever waiting on that timer.
/// Without this filter, a worker who completes a job and navigates away
/// from the success screen via the bottom nav (rather than tapping
/// "Find more jobs", which calls `remove(jobId)`) keeps seeing a ghost
/// card for the finished job — exactly the "I got paid but it's still
/// showing" bug.
final Provider<List<WorkSession>> activeWorkSessionsProvider =
    Provider<List<WorkSession>>((Ref ref) {
  final map = ref.watch(workSessionProvider);
  final now = DateTime.now().toUtc();
  final list = <WorkSession>[];
  for (final s in map.values) {
    if (s.phase == WorkPhase.done) continue;
    if (s.phase == WorkPhase.pendingReview &&
        s.holdReleaseAt != null &&
        s.holdReleaseAt!.isBefore(now)) {
      continue;
    }
    list.add(s);
  }
  list.sort((WorkSession a, WorkSession b) =>
      a.priority.compareTo(b.priority));
  return list;
});

/// The most attention-worthy in-flight session, or null when none.
/// Used by [JobsScreen] for the active-session card on the home sheet.
final Provider<WorkSession?> primaryWorkSessionProvider =
    Provider<WorkSession?>((Ref ref) {
  final list = ref.watch(activeWorkSessionsProvider);
  return list.isEmpty ? null : list.first;
});
