import 'package:flutter/foundation.dart';

import '../mock/models.dart' show JobType;

/// Wire models for the AI endpoints documented in
/// `endpoint_resources/ai.md`.
///
/// Every endpoint returns the same `{ data, meta }` envelope. The
/// `meta` block is observability-only — we capture it in debug builds
/// but never branch UI on it.
@immutable
class AiMeta {
  const AiMeta({
    required this.model,
    required this.provider,
    required this.elapsedMs,
    required this.cached,
  });

  final String model;
  final String provider;
  final int elapsedMs;
  final bool cached;

  factory AiMeta.fromJson(Map<String, dynamic> json) => AiMeta(
        model: (json['model'] as String?) ?? 'unknown',
        provider: (json['provider'] as String?) ?? 'unknown',
        elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
        cached: (json['cached'] as bool?) ?? false,
      );
}

// ---------------------------------------------------------------------
// /ai/jobs/:id/summarize
// ---------------------------------------------------------------------

@immutable
class JobSummary {
  const JobSummary({required this.summary, required this.highlights});

  /// Max 140 chars, one or two sentences. Naija-English register.
  final String summary;

  /// 0–4 inline chips (label + value). May be empty.
  final List<JobSummaryHighlight> highlights;

  bool get isEmpty => summary.isEmpty && highlights.isEmpty;

  factory JobSummary.fromJson(Map<String, dynamic> data) {
    final list = (data['highlights'] as List?) ?? const <dynamic>[];
    return JobSummary(
      summary: (data['summary'] as String?) ?? '',
      highlights: list
          .whereType<Map<String, dynamic>>()
          .map(JobSummaryHighlight.fromJson)
          .toList(growable: false),
    );
  }
}

@immutable
class JobSummaryHighlight {
  const JobSummaryHighlight({required this.label, required this.value});

  final String label;
  final String value;

  factory JobSummaryHighlight.fromJson(Map<String, dynamic> json) =>
      JobSummaryHighlight(
        label: (json['label'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------------
// /ai/search/parse
// ---------------------------------------------------------------------

/// Spatial anchor returned by the parser. Resolved server-side via the
/// gazetteer, never trusted from the LLM directly.
@immutable
class SearchNear {
  const SearchNear({
    required this.lat,
    required this.lng,
    required this.label,
    required this.radiusKm,
  });

  final double lat;
  final double lng;
  final String label;
  final double radiusKm;

  factory SearchNear.fromJson(Map<String, dynamic> json) => SearchNear(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        label: (json['label'] as String?) ?? '',
        radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 5.0,
      );
}

@immutable
class SearchFilters {
  const SearchFilters({
    this.types = const <JobType>[],
    this.near,
    this.startAfter,
    this.startBefore,
    this.minPay,
    this.maxPay,
    this.keywords = const <String>[],
  });

  final List<JobType> types;
  final SearchNear? near;
  final DateTime? startAfter;
  final DateTime? startBefore;
  final int? minPay;
  final int? maxPay;

  /// Free-text tokens that didn't map to a structured filter. Mobile
  /// substring-matches these on the cached jobs list in addition to
  /// the structured filters.
  final List<String> keywords;

  bool get isEmpty =>
      types.isEmpty &&
      near == null &&
      startAfter == null &&
      startBefore == null &&
      minPay == null &&
      maxPay == null &&
      keywords.isEmpty;

  factory SearchFilters.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

    final typesList = (json['types'] as List?) ?? const <dynamic>[];
    final keywordsList = (json['keywords'] as List?) ?? const <dynamic>[];

    return SearchFilters(
      types: typesList
          .whereType<String>()
          .map(JobType.fromWire)
          .toList(growable: false),
      near: json['near'] is Map<String, dynamic>
          ? SearchNear.fromJson(json['near'] as Map<String, dynamic>)
          : null,
      startAfter: parseTs(json['start_after']),
      startBefore: parseTs(json['start_before']),
      minPay: (json['min_pay'] as num?)?.toInt(),
      maxPay: (json['max_pay'] as num?)?.toInt(),
      keywords: keywordsList.whereType<String>().toList(growable: false),
    );
  }
}

@immutable
class SearchParseResult {
  const SearchParseResult({
    required this.transcript,
    required this.filters,
    required this.confidence,
    required this.unresolved,
  });

  final String transcript;
  final SearchFilters filters;
  final double confidence;
  final List<String> unresolved;

  factory SearchParseResult.fromJson(Map<String, dynamic> data) {
    final unresolvedList =
        (data['unresolved'] as List?) ?? const <dynamic>[];
    return SearchParseResult(
      transcript: (data['transcript'] as String?) ?? '',
      filters: data['filters'] is Map<String, dynamic>
          ? SearchFilters.fromJson(data['filters'] as Map<String, dynamic>)
          : const SearchFilters(),
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
      unresolved:
          unresolvedList.whereType<String>().toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------
// /ai/profile/extract
// ---------------------------------------------------------------------

@immutable
class ProfileDraft {
  const ProfileDraft({
    this.name,
    this.primarySkill,
    this.preferredRadiusKm,
    this.neighborhood,
    this.confidence = const <String, double>{},
    this.unresolved = const <String>[],
  });

  final String? name;
  final JobType? primarySkill;
  final int? preferredRadiusKm;

  /// Free-form. Not yet persisted server-side (see ai.md). Mobile uses
  /// it as a UI hint for the confirm step.
  final String? neighborhood;

  /// Per-field confidence 0–1. Mobile shows a small warning next to
  /// any field with confidence < 0.7.
  final Map<String, double> confidence;

  final List<String> unresolved;

  bool get isEmpty =>
      name == null &&
      primarySkill == null &&
      preferredRadiusKm == null &&
      neighborhood == null;

  double confidenceFor(String field) =>
      confidence[field] ?? 1.0; // fields not returned default to "trust it"

  factory ProfileDraft.fromJson(Map<String, dynamic> data) {
    final draft = (data['draft'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final conf = (data['confidence'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final unresolvedList =
        (data['unresolved'] as List?) ?? const <dynamic>[];

    final String? skillWire = draft['primary_skill'] as String?;
    return ProfileDraft(
      name: (draft['name'] as String?)?.trim(),
      primarySkill:
          (skillWire != null && skillWire.isNotEmpty)
              ? JobType.fromWire(skillWire)
              : null,
      preferredRadiusKm: (draft['preferred_radius_km'] as num?)?.toInt(),
      neighborhood: (draft['neighborhood'] as String?)?.trim(),
      confidence: <String, double>{
        for (final e in conf.entries)
          if (e.value is num) e.key: (e.value as num).toDouble(),
      },
      unresolved:
          unresolvedList.whereType<String>().toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------
// /ai/disputes/:id/mediate (ops-only, not used by worker mobile but
// modelled here for completeness — saves duplicating the JSON envelope
// when an ops surface lands)
// ---------------------------------------------------------------------

enum DisputeVerdict {
  favorWorker('favor_worker'),
  favorEmployer('favor_employer'),
  partial('partial'),
  insufficientEvidence('insufficient_evidence');

  const DisputeVerdict(this.wire);
  final String wire;

  static DisputeVerdict fromWire(String wire) {
    for (final v in DisputeVerdict.values) {
      if (v.wire == wire) return v;
    }
    return DisputeVerdict.insufficientEvidence;
  }
}

@immutable
class DisputeMediation {
  const DisputeMediation({
    required this.verdict,
    required this.verdictConfidence,
    required this.rationale,
    required this.recommendedActionType,
    this.amountToWorker,
    this.amountFromEmployer,
    this.actionNotes,
    this.draftMessageToWorker,
    this.draftMessageToEmployer,
    this.policyReferences = const <String>[],
  });

  final DisputeVerdict verdict;
  final double verdictConfidence;
  final String rationale;
  final String recommendedActionType;
  final int? amountToWorker;
  final int? amountFromEmployer;
  final String? actionNotes;
  final String? draftMessageToWorker;
  final String? draftMessageToEmployer;
  final List<String> policyReferences;

  factory DisputeMediation.fromJson(Map<String, dynamic> data) {
    final action = (data['recommended_action'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final refs =
        (data['policy_references'] as List?) ?? const <dynamic>[];
    return DisputeMediation(
      verdict: DisputeVerdict.fromWire((data['verdict'] as String?) ?? ''),
      verdictConfidence:
          (data['verdict_confidence'] as num?)?.toDouble() ?? 0.0,
      rationale: (data['rationale'] as String?) ?? '',
      recommendedActionType:
          (action['type'] as String?) ?? 'escalate_to_human',
      amountToWorker: (action['amount_to_worker'] as num?)?.toInt(),
      amountFromEmployer: (action['amount_from_employer'] as num?)?.toInt(),
      actionNotes: action['notes'] as String?,
      draftMessageToWorker: data['draft_message_to_worker'] as String?,
      draftMessageToEmployer: data['draft_message_to_employer'] as String?,
      policyReferences: refs.whereType<String>().toList(growable: false),
    );
  }
}
