import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../api/api_client.dart';
import 'ai_models.dart';

/// Backend-facing surface for the five AI endpoints in
/// `endpoint_resources/ai.md`.
///
/// Every method is **soft-fail**: catch the `ApiException` at the call
/// site and treat it as "feature disabled for now". The mobile contract
/// is built so every AI call has a non-AI fallback (raw description,
/// substring search, manual form). The repository itself does not
/// swallow errors — the caller decides how to degrade.
class AiRepository {
  AiRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  // ---------------------------------------------------------------------
  // Summarize concurrency gate.
  //
  // Every JobCard fires its own `jobSummaryProvider(jobId)` on first
  // paint. A feed of ~30 cards would otherwise spawn 30 simultaneous
  // POSTs to `/ai/jobs/:id/summarize`, which (a) hammers the backend
  // (b) bursts the worker's mobile data and (c) causes a wave of
  // card relayouts as each request settles back at the same time —
  // visible as scroll jank.
  //
  // We let at most `_maxInFlight` summarize calls run concurrently;
  // the rest queue and start as slots free up. The first paint still
  // resolves in a smooth cascade rather than a single dropped frame.
  static const int _maxInFlight = 4;
  int _inFlight = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> _acquireSlot() {
    if (_inFlight < _maxInFlight) {
      _inFlight++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _releaseSlot() {
    if (_waiters.isNotEmpty) {
      // Hand the slot directly to the next waiter — don't decrement
      // and re-increment, which would briefly let a third concurrent
      // call slip through.
      _waiters.removeFirst().complete();
      return;
    }
    _inFlight--;
  }

  /// `POST /ai/jobs/:id/summarize` — one-line digest + chips for the
  /// job card. Server-cached per `job_id`; safe to call on every card
  /// view (the first worker pays Anthropic; the rest hit the cache).
  ///
  /// Gated to at most [_maxInFlight] concurrent requests across the
  /// app so a fresh feed paint doesn't spawn 30 parallel POSTs.
  Future<JobSummary> summarizeJob(String jobId) async {
    await _acquireSlot();
    try {
      final json = await _client.post(
        '/ai/jobs/$jobId/summarize',
        authenticated: true,
        body: const <String, dynamic>{},
        idempotent: true,
        idempotencyAction: 'ai_summarize:$jobId',
      );
      final data = (json['data'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      return JobSummary.fromJson(data);
    } finally {
      _releaseSlot();
    }
  }

  /// `POST /ai/search/parse` — text mode. Returns a structured filter
  /// envelope the mobile applies to the cached jobs list.
  Future<SearchParseResult> parseSearchText({
    required String text,
    double? workerLat,
    double? workerLng,
    DateTime? now,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      'context': <String, dynamic>{
        'worker_lat': ?workerLat,
        'worker_lng': ?workerLng,
        'now': ?now?.toUtc().toIso8601String(),
      },
    };
    final json = await _client.post(
      '/ai/search/parse',
      authenticated: true,
      body: body,
    );
    final data = (json['data'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return SearchParseResult.fromJson(data);
  }

  /// `POST /ai/search/parse` — voice mode. The mobile records a short
  /// m4a clip; the server transcribes via Whisper, then parses the
  /// transcript into the same envelope as text mode.
  ///
  /// [contentType] is the audio MIME (`audio/m4a`, `audio/aac`, etc).
  Future<SearchParseResult> parseSearchVoice({
    required List<int> audioBytes,
    required String filename,
    required String contentType,
    double? workerLat,
    double? workerLng,
    DateTime? now,
  }) async {
    final context = <String, dynamic>{
      'worker_lat': ?workerLat,
      'worker_lng': ?workerLng,
      'now': ?now?.toUtc().toIso8601String(),
    };
    final json = await _client.upload(
      '/ai/search/parse',
      bytes: audioBytes,
      filename: filename,
      contentType: contentType,
      fields: <String, String>{
        if (context.isNotEmpty) 'context': jsonEncode(context),
      },
    );
    final data = (json['data'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return SearchParseResult.fromJson(data);
  }

  /// `POST /ai/profile/extract` — natural-language description →
  /// pre-filled `PATCH /me` draft. The mobile shows the draft for
  /// review; the save itself still goes through the existing
  /// profile-edit pipeline.
  Future<ProfileDraft> extractProfile(String text) async {
    final json = await _client.post(
      '/ai/profile/extract',
      authenticated: true,
      body: <String, dynamic>{'text': text},
      idempotent: true,
      idempotencyAction: 'ai_profile_extract',
    );
    final data = (json['data'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return ProfileDraft.fromJson(data);
  }

  /// `POST /ai/disputes/:id/mediate` — ops-only. Returns a suggested
  /// resolution + drafted messages for both parties. The worker mobile
  /// never calls this in production; included here so a future ops
  /// surface can reuse the repository wiring.
  Future<DisputeMediation> mediateDispute({
    required String disputeId,
    String? additionalContext,
  }) async {
    final json = await _client.post(
      '/ai/disputes/$disputeId/mediate',
      authenticated: true,
      body: <String, dynamic>{
        if (additionalContext != null && additionalContext.isNotEmpty)
          'additional_context': additionalContext,
      },
      idempotent: true,
      idempotencyAction: 'ai_mediate:$disputeId',
    );
    final data = (json['data'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return DisputeMediation.fromJson(data);
  }
}
