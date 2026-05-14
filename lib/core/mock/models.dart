/// Domain models used by mock data and stub providers.
///
/// These are intentionally plain Dart classes — no `freezed`, no codegen.
/// When the real backend lands, these can be regenerated as freezed
/// classes from OpenAPI without changing call-site code.
library;

import 'package:flutter/foundation.dart';

@immutable
class Worker {
  const Worker({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.primarySkill,
    required this.reliabilityScore,
    required this.jobsCompleted,
    required this.totalEarned,
    required this.averageRating,
    required this.creditScore,
    required this.joinedAt,
    required this.preferredRadiusKm,
    this.photoUrl,
    this.walletBalance = 0,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final String? photoUrl;
  final String primarySkill;
  final int reliabilityScore;
  final int jobsCompleted;
  final int totalEarned;
  final double averageRating;
  final int creditScore;
  final DateTime joinedAt;
  final double preferredRadiusKm;
  final int walletBalance;

  /// Maps the wire shape from `endpoint_resources/16_profile.md`.
  /// Server JSON uses snake_case; we translate at the boundary.
  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phone_number'] as String,
      photoUrl: json['photo_url'] as String?,
      primarySkill: json['primary_skill'] as String,
      reliabilityScore: (json['reliability_score'] as num?)?.toInt() ?? 0,
      jobsCompleted: (json['jobs_completed'] as num?)?.toInt() ?? 0,
      totalEarned: (json['total_earned'] as num?)?.toInt() ?? 0,
      averageRating:
          (json['average_rating'] as num?)?.toDouble() ?? 0.0,
      creditScore: (json['credit_score'] as num?)?.toInt() ?? 0,
      joinedAt: DateTime.parse(json['joined_at'] as String).toUtc(),
      preferredRadiusKm:
          (json['preferred_radius_km'] as num?)?.toDouble() ?? 5.0,
      walletBalance: (json['wallet_balance'] as num?)?.toInt() ?? 0,
    );
  }

  /// Mirror of [Worker.fromJson] for round-tripping through secure
  /// storage. Only the fields the backend would accept on a write —
  /// stats are server-computed.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'phone_number': phoneNumber,
        'photo_url': photoUrl,
        'primary_skill': primarySkill,
        'reliability_score': reliabilityScore,
        'jobs_completed': jobsCompleted,
        'total_earned': totalEarned,
        'average_rating': averageRating,
        'credit_score': creditScore,
        'joined_at': joinedAt.toUtc().toIso8601String(),
        'preferred_radius_km': preferredRadiusKm,
        'wallet_balance': walletBalance,
      };
}

@immutable
class Employer {
  const Employer({
    required this.id,
    required this.name,
    required this.rating,
    required this.jobsPosted,
    required this.memberSince,
    this.photoUrl,
    this.phoneNumber,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final double rating;
  final int jobsPosted;
  final DateTime memberSince;
  final String? phoneNumber;

  factory Employer.fromJson(Map<String, dynamic> json) {
    // `member_since` is on the full EmployerDto but NOT on the slim
    // shape (`EmployerSlimDto`) embedded inside JobSlimDto rows from
    // `/applications`. Fall back to epoch when absent so the slim
    // shape parses cleanly — screens that need a real join date
    // fetch the full employer record separately anyway.
    //
    // Also tolerant of camelCase keys (`photoUrl`, `jobsPosted`,
    // `memberSince`, `phoneNumber`) — the production backend ships
    // camelCase even though the spec is snake_case.
    final memberSinceRaw = json['member_since'] ?? json['memberSince'];
    final memberSince = memberSinceRaw is String
        ? DateTime.parse(memberSinceRaw).toUtc()
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return Employer(
      id: json['id'] as String,
      name: json['name'] as String,
      photoUrl: (json['photo_url'] ?? json['photoUrl']) as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      jobsPosted:
          ((json['jobs_posted'] ?? json['jobsPosted']) as num?)?.toInt() ?? 0,
      memberSince: memberSince,
      phoneNumber:
          (json['phone_number'] ?? json['phoneNumber']) as String?,
    );
  }
}

/// Server-computed stats nested under `GET /employers/:id`'s `stats`.
/// See `endpoint_resources/25_employer_profile.md` for full field rules
/// (especially: `completionRate` is meaningless when `completedJobs < 10`
/// — the screen renders "New employer" copy in that case).
@immutable
class EmployerStats {
  const EmployerStats({
    required this.openJobs,
    required this.completedJobs,
    required this.completionRate,
    required this.averagePay,
    required this.averageResponseTimeMinutes,
    required this.ratingsBreakdown,
  });

  final int openJobs;
  final int completedJobs;
  final double completionRate;
  final int averagePay;
  final int averageResponseTimeMinutes;

  /// Histogram keyed by star count (1..5). Values are the number of
  /// ratings received at that star level. Sum can be lower than
  /// `Employer.jobsPosted` since not every session is rated.
  final Map<int, int> ratingsBreakdown;

  factory EmployerStats.fromJson(Map<String, dynamic> json) {
    final raw = json['ratings_breakdown'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final breakdown = <int, int>{
      for (final entry in raw.entries)
        if (int.tryParse(entry.key) != null)
          int.parse(entry.key): (entry.value as num?)?.toInt() ?? 0,
    };
    return EmployerStats(
      openJobs: (json['open_jobs'] as num?)?.toInt() ?? 0,
      completedJobs: (json['completed_jobs'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0.0,
      averagePay: (json['average_pay'] as num?)?.toInt() ?? 0,
      averageResponseTimeMinutes:
          (json['average_response_time_minutes'] as num?)?.toInt() ?? 0,
      ratingsBreakdown: breakdown,
    );
  }
}

/// Full employer profile from `GET /employers/:id`. Composes the slim
/// [Employer] with the richer fields the dedicated profile screen
/// needs (verified, business type, bio, location, stats).
@immutable
class EmployerProfile {
  const EmployerProfile({
    required this.employer,
    required this.verified,
    required this.businessType,
    required this.stats,
    this.bio,
    this.primaryLocationLat,
    this.primaryLocationLng,
    this.primaryLocationAddress,
  });

  final Employer employer;
  final bool verified;
  final String businessType;
  final String? bio;
  final double? primaryLocationLat;
  final double? primaryLocationLng;
  final String? primaryLocationAddress;
  final EmployerStats stats;

  factory EmployerProfile.fromJson(Map<String, dynamic> json) {
    final loc = json['primary_location'] as Map<String, dynamic>?;
    return EmployerProfile(
      employer: Employer.fromJson(json),
      verified: json['verified'] as bool? ?? false,
      businessType: json['business_type'] as String? ?? '',
      bio: json['bio'] as String?,
      primaryLocationLat: (loc?['lat'] as num?)?.toDouble(),
      primaryLocationLng: (loc?['lng'] as num?)?.toDouble(),
      primaryLocationAddress: loc?['address'] as String?,
      stats: EmployerStats.fromJson(
        json['stats'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

enum EmployerJobStatus {
  open('Open', 'open'),
  closed('Closed', 'closed');

  const EmployerJobStatus(this.label, this.wire);
  final String label;
  final String wire;

  static EmployerJobStatus fromWire(String wire) {
    for (final s in EmployerJobStatus.values) {
      if (s.wire == wire) return s;
    }
    return EmployerJobStatus.closed;
  }
}

/// One row of `GET /employers/:id/jobs`. Wraps a [Job] (same shape as
/// `/jobs` per `02_jobs_feed.md`) with the employer-scoped `status`
/// field that the public feed doesn't carry. The detail screen splits
/// the rendered list at the first `closed` row to label "Active" vs.
/// "History".
@immutable
class EmployerJob {
  const EmployerJob({required this.job, required this.status});

  final Job job;
  final EmployerJobStatus status;

  factory EmployerJob.fromJson(Map<String, dynamic> json) {
    return EmployerJob(
      job: Job.fromJson(json),
      status: EmployerJobStatus.fromWire(
        json['status'] as String? ?? 'closed',
      ),
    );
  }
}

/// Cursor-paginated envelope around [EmployerJob]. Matches the
/// `items` / `next_cursor` / `has_more` shape from `00_README.md`.
@immutable
class EmployerJobsPage {
  const EmployerJobsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<EmployerJob> items;
  final String? nextCursor;
  final bool hasMore;
}

enum JobType {
  loader('Loader', '🏗️', 'loader'),
  driver('Driver', '🚛', 'driver'),
  unloader('Unloader', '📦', 'unloader'),
  generalLabor('General Labor', '👷', 'general_labor'),
  welder('Welder', '🔧', 'welder');

  const JobType(this.label, this.emoji, this.wire);
  final String label;
  final String emoji;

  /// snake_case wire format used by `GET /jobs` and `POST /jobs/:id/apply`.
  /// Mirrors the table in `endpoint_resources/02_jobs_feed.md`.
  final String wire;

  static JobType fromWire(String wire) {
    for (final t in JobType.values) {
      if (t.wire == wire) return t;
    }
    // Defensive fallback — server should never send something else, but
    // we'd rather render a job as "General Labor" than crash the feed.
    return JobType.generalLabor;
  }
}

@immutable
class Job {
  const Job({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.payAmount,
    required this.durationHours,
    required this.locationLat,
    required this.locationLng,
    required this.locationAddress,
    required this.distanceMeters,
    required this.travelTimeWalkingMinutes,
    required this.travelTimeDrivingMinutes,
    required this.employer,
    required this.startTime,
    this.requiredEquipment = const <String>[],
    this.locationNeighborhood,
  });

  final String id;
  final JobType type;
  final String title;
  final String description;
  final int payAmount;
  final int durationHours;
  final double locationLat;
  final double locationLng;
  final String locationAddress;
  final int distanceMeters;
  final int travelTimeWalkingMinutes;
  final int travelTimeDrivingMinutes;
  final Employer employer;
  final DateTime startTime;
  final List<String> requiredEquipment;

  /// Free-form neighborhood string from the employer's location pick
  /// (Places Autocomplete) — anything from "Apapa" to
  /// "Plot 1234 Sango Ota" or null. Use [areaLabel] to render —
  /// never pattern-match against an old preset list.
  final String? locationNeighborhood;

  /// Short, scannable area label for list cells. Prefers
  /// [locationNeighborhood] when present; otherwise falls back to the
  /// first comma-delimited segment of [locationAddress] (Google's
  /// `formatted_address` puts the most-specific part first); finally
  /// `'—'` so the cell never renders blank.
  String get areaLabel {
    final n = locationNeighborhood?.trim();
    if (n != null && n.isNotEmpty) return n;
    final firstSegment = locationAddress.split(',').first.trim();
    if (firstSegment.isNotEmpty) return firstSegment;
    return '—';
  }

  /// Wire shape per `endpoint_resources/02_jobs_feed.md` — `location` is
  /// a nested object on the wire; we flatten into top-level fields.
  ///
  /// Tolerant of TWO key styles:
  ///   - snake_case per the spec (`pay_amount`, `duration_hours`, ...).
  ///   - camelCase as the production backend currently ships
  ///     (`payNaira`, `durationHours`, `scheduledStartAt`, ...).
  /// Also tolerates the slim shape used in `/applications` responses
  /// (no description, travel times, employer object, or required
  /// equipment). When the embedded `employer` object is absent we
  /// synthesize a minimal record from `employerId` + the optional
  /// `assignedWorker` block (used for the employer-side hero cards).
  factory Job.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>;

    int pickInt(String snake, String camel, {int fallback = 0}) {
      final v = json[snake] ?? json[camel];
      return v is num ? v.toInt() : fallback;
    }

    String? pickString(String snake, String camel) {
      final v = json[snake] ?? json[camel];
      return v is String ? v : null;
    }

    List<String> pickStringList(String snake, String camel) {
      final v = json[snake] ?? json[camel];
      if (v is! List) return const <String>[];
      return v.whereType<String>().toList(growable: false);
    }

    DateTime parseStart() {
      final raw = pickString('start_time', 'scheduledStartAt') ??
          // last resort — keep the parse from crashing on a draft row
          // that omits the field entirely.
          DateTime.now().toUtc().toIso8601String();
      return DateTime.parse(raw).toUtc();
    }

    // Employer object can come embedded (spec), or as just `employerId`
    // (current backend). Fall back to a minimal Employer so the rest of
    // the UI keeps rendering instead of crashing on a missing key.
    final Map<String, dynamic>? embeddedEmployer =
        json['employer'] as Map<String, dynamic>?;
    final Employer employer = embeddedEmployer != null
        ? Employer.fromJson(embeddedEmployer)
        : Employer(
            id: (json['employerId'] ?? json['employer_id']) as String? ??
                'emp_unknown',
            name: pickString('employer_name', 'employerName') ?? 'Employer',
            rating: 0.0,
            jobsPosted: 0,
            memberSince:
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );

    return Job(
      id: json['id'] as String,
      type: JobType.fromWire(json['type'] as String),
      title: json['title'] as String,
      description: pickString('description', 'description') ?? '',
      // `pay_amount` (spec) ↔ `payNaira` (backend). Whole Naira either way.
      payAmount: pickInt('pay_amount', 'payNaira'),
      durationHours: pickInt('duration_hours', 'durationHours'),
      locationLat: (location['lat'] as num).toDouble(),
      locationLng: (location['lng'] as num).toDouble(),
      locationAddress: location['address'] as String,
      // Free-form per the location-freeform handoff. May be missing on
      // older or legacy rows; consumers use `areaLabel` instead of
      // reading this directly.
      locationNeighborhood: (location['neighborhood'] as String?)?.trim(),
      distanceMeters: pickInt('distance_meters', 'distanceMeters'),
      travelTimeWalkingMinutes: pickInt(
          'travel_time_walking_minutes', 'travelTimeWalkingMinutes'),
      travelTimeDrivingMinutes: pickInt(
          'travel_time_driving_minutes', 'travelTimeDrivingMinutes'),
      employer: employer,
      startTime: parseStart(),
      requiredEquipment:
          pickStringList('required_equipment', 'requiredEquipment'),
    );
  }
}

enum ApplicationStatus {
  applied('Applied', 'applied'),
  accepted('Accepted', 'accepted'),
  rejected('Rejected', 'rejected'),
  inProgress('In progress', 'in_progress'),
  completed('Completed', 'completed'),
  withdrawn('Withdrawn', 'withdrawn');

  const ApplicationStatus(this.label, this.wire);
  final String label;
  final String wire;

  static ApplicationStatus fromWire(String wire) {
    for (final s in ApplicationStatus.values) {
      if (s.wire == wire) return s;
    }
    return ApplicationStatus.applied;
  }
}

/// Slim result of `POST /jobs/:id/apply` (`ApplicationSummaryDto`).
/// Carries `job_id` instead of an embedded job — the mobile already
/// has the [Job] from the calling screen, so we don't need a second
/// copy.
@immutable
class ApplicationSummary {
  const ApplicationSummary({
    required this.id,
    required this.jobId,
    required this.status,
    required this.appliedAt,
    this.decidedAt,
    this.completedAt,
    this.withdrawnAt,
    this.note,
  });

  final String id;
  final String jobId;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final DateTime? decidedAt;
  final DateTime? completedAt;
  final DateTime? withdrawnAt;
  final String? note;

  factory ApplicationSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final raw = json[key];
      return raw is String ? DateTime.parse(raw).toUtc() : null;
    }
    return ApplicationSummary(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      status: ApplicationStatus.fromWire(json['status'] as String),
      appliedAt: DateTime.parse(json['applied_at'] as String).toUtc(),
      decidedAt: parse('decided_at'),
      completedAt: parse('completed_at'),
      withdrawnAt: parse('withdrawn_at'),
      note: json['note'] as String?,
    );
  }
}

@immutable
class JobApplication {
  const JobApplication({
    required this.id,
    required this.job,
    required this.status,
    required this.appliedAt,
    this.decidedAt,
    this.completedAt,
    this.note,
  });

  final String id;
  final Job job;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final DateTime? decidedAt;
  final DateTime? completedAt;
  final String? note;

  /// Wire shape covers both the apply/status responses and the slim
  /// list shape from `/applications` — `job` is required by the
  /// detail endpoints and embedded in list rows.
  factory JobApplication.fromJson(Map<String, dynamic> json) {
    final jobJson = json['job'];
    return JobApplication(
      id: json['id'] as String,
      status: ApplicationStatus.fromWire(json['status'] as String),
      appliedAt:
          DateTime.parse(json['applied_at'] as String).toUtc(),
      decidedAt: json['decided_at'] is String
          ? DateTime.parse(json['decided_at'] as String).toUtc()
          : null,
      completedAt: json['completed_at'] is String
          ? DateTime.parse(json['completed_at'] as String).toUtc()
          : null,
      note: json['note'] as String?,
      job: jobJson is Map<String, dynamic>
          ? Job.fromJson(jobJson)
          : throw StateError('JobApplication.fromJson: missing job'),
    );
  }
}

enum TransactionKind {
  jobPayment('Job payment', 'job_payment'),
  loanDisbursement('Loan disbursed', 'loan_disbursement'),
  loanRepayment('Loan repayment', 'loan_repayment'),
  withdrawal('Withdrawal', 'withdrawal');

  const TransactionKind(this.label, this.wire);
  final String label;
  final String wire;

  static TransactionKind fromWire(String wire) {
    for (final k in TransactionKind.values) {
      if (k.wire == wire) return k;
    }
    return TransactionKind.jobPayment;
  }
}

@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    this.squadReference,
    this.relatedJobId,
    this.relatedJobSummary,
    this.bankAccountSummary,
  });

  final String id;
  final TransactionKind kind;

  /// Positive for credits (job payment, loan disbursement),
  /// negative for debits (loan repayment, withdrawal).
  final int amount;
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final String? squadReference;
  final String? relatedJobId;

  /// Only present in transaction-detail responses (10).
  final RelatedJobSummary? relatedJobSummary;
  final BankAccountSummary? bankAccountSummary;

  bool get isCredit => amount > 0;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      kind: TransactionKind.fromWire(json['kind'] as String),
      amount: (json['amount'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      squadReference: json['squad_reference'] as String?,
      relatedJobId: json['related_job_id'] as String?,
      relatedJobSummary: json['related_job_summary'] is Map<String, dynamic>
          ? RelatedJobSummary.fromJson(
              json['related_job_summary'] as Map<String, dynamic>)
          : null,
      bankAccountSummary: json['bank_account_summary']
              is Map<String, dynamic>
          ? BankAccountSummary.fromJson(
              json['bank_account_summary'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Slim job block used by transaction-detail receipt.
@immutable
class RelatedJobSummary {
  const RelatedJobSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.locationAddress,
    required this.durationHours,
    this.completedAt,
  });

  final String id;
  final JobType type;
  final String title;
  final String locationAddress;
  final int durationHours;
  final DateTime? completedAt;

  factory RelatedJobSummary.fromJson(Map<String, dynamic> json) {
    return RelatedJobSummary(
      id: json['id'] as String,
      type: JobType.fromWire(json['type'] as String),
      title: json['title'] as String,
      locationAddress: json['location_address'] as String,
      durationHours: (json['duration_hours'] as num?)?.toInt() ?? 0,
      completedAt: json['completed_at'] is String
          ? DateTime.parse(json['completed_at'] as String).toUtc()
          : null,
    );
  }
}

@immutable
class BankAccountSummary {
  const BankAccountSummary({required this.bankName, required this.last4});
  final String bankName;
  final String last4;

  factory BankAccountSummary.fromJson(Map<String, dynamic> json) {
    return BankAccountSummary(
      bankName: json['bank_name'] as String,
      last4: json['account_number_last4'] as String,
    );
  }
}

enum NotificationKind {
  newJob('New job', 'new_job'),
  applicationUpdate('Application', 'application_update'),
  payment('Payment', 'payment'),
  loan('Loan', 'loan'),
  system('System', 'system');

  const NotificationKind(this.label, this.wire);
  final String label;
  final String wire;

  static NotificationKind fromWire(String wire) {
    for (final k in NotificationKind.values) {
      if (k.wire == wire) return k;
    }
    return NotificationKind.system;
  }
}

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.unread,
    this.deeplink,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool unread;
  final String? deeplink;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      kind: NotificationKind.fromWire(json['kind'] as String),
      title: json['title'] as String,
      body: json['body'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      unread: json['unread'] as bool? ?? false,
      deeplink: json['deeplink'] as String?,
    );
  }

  AppNotification copyWith({bool? unread}) {
    return AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: body,
      timestamp: timestamp,
      unread: unread ?? this.unread,
      deeplink: deeplink,
    );
  }
}

@immutable
class BankAccount {
  const BankAccount({
    required this.id,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.isDefault,
    this.bankCode,
    this.createdAt,
  });

  final String id;
  final String bankName;
  final String? bankCode;
  final String accountNumber;
  final String accountName;
  final bool isDefault;
  final DateTime? createdAt;

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] as String,
      bankName: json['bank_name'] as String,
      bankCode: json['bank_code'] as String?,
      accountNumber: json['account_number'] as String,
      accountName: json['account_name'] as String,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String).toUtc()
          : null,
    );
  }
}

/// Static NIBSS bank entry (`GET /banks`).
@immutable
class Bank {
  const Bank({required this.code, required this.name});
  final String code;
  final String name;

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }
}

enum LoanStatus {
  none('None', 'none'),
  pending('Pending review', 'pending'),
  approved('Approved', 'approved'),
  rejected('Rejected', 'rejected'),
  active('Active', 'active'),
  repaid('Repaid', 'repaid');

  const LoanStatus(this.label, this.wire);
  final String label;
  final String wire;

  static LoanStatus fromWire(String wire) {
    for (final s in LoanStatus.values) {
      if (s.wire == wire) return s;
    }
    return LoanStatus.none;
  }
}

@immutable
class Loan {
  const Loan({
    required this.id,
    required this.principal,
    required this.outstandingBalance,
    required this.interestRatePercent,
    required this.repaymentPercentPerJob,
    required this.disbursedAt,
    required this.status,
    required this.repayments,
    this.purpose,
    this.expectedFullRepaymentAt,
    this.nextRepaymentEstimate,
    this.nextRepaymentWhen,
    this.repaymentsCount,
    this.repaymentsTotal,
    this.rejectionReason,
    this.estimatedDecisionAt,
  });

  final String id;
  final int principal;
  final int outstandingBalance;
  final double interestRatePercent;
  final double repaymentPercentPerJob;
  final DateTime disbursedAt;
  final LoanStatus status;
  final List<LoanRepayment> repayments;

  // Loans-home extras (13)
  final String? purpose;
  final int? nextRepaymentEstimate;
  final String? nextRepaymentWhen;
  final int? repaymentsCount;
  final int? repaymentsTotal;

  // Detail extras (15)
  final DateTime? expectedFullRepaymentAt;

  // Apply / pending / rejected screens
  final String? rejectionReason;
  final DateTime? estimatedDecisionAt;

  double get progressFraction =>
      principal == 0 ? 0 : (principal - outstandingBalance) / principal;

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as String,
      principal: (json['principal'] as num?)?.toInt() ?? 0,
      outstandingBalance:
          (json['outstanding_balance'] as num?)?.toInt() ?? 0,
      interestRatePercent:
          (json['interest_rate_percent'] as num?)?.toDouble() ?? 0.0,
      repaymentPercentPerJob:
          (json['repayment_percent_per_job'] as num?)?.toDouble() ?? 0.0,
      disbursedAt: json['disbursed_at'] is String
          ? DateTime.parse(json['disbursed_at'] as String).toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      status: LoanStatus.fromWire(json['status'] as String),
      purpose: json['purpose'] as String?,
      nextRepaymentEstimate:
          (json['next_repayment_estimate'] as num?)?.toInt(),
      nextRepaymentWhen: json['next_repayment_when'] as String?,
      repaymentsCount: (json['repayments_count'] as num?)?.toInt(),
      repaymentsTotal: (json['repayments_total'] as num?)?.toInt(),
      expectedFullRepaymentAt: json['expected_full_repayment_at'] is String
          ? DateTime.parse(json['expected_full_repayment_at'] as String)
              .toUtc()
          : null,
      rejectionReason: json['rejection_reason'] as String?,
      estimatedDecisionAt: json['estimated_decision_at'] is String
          ? DateTime.parse(json['estimated_decision_at'] as String).toUtc()
          : null,
      repayments: (json['repayments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(LoanRepayment.fromJson)
              .toList(growable: false) ??
          const <LoanRepayment>[],
    );
  }
}

@immutable
class LoanRepayment {
  const LoanRepayment({
    required this.id,
    required this.amount,
    required this.paidAt,
    required this.fromJobId,
    this.fromJobTitle,
    this.transactionId,
  });

  final String id;
  final int amount;
  final DateTime paidAt;
  final String fromJobId;
  final String? fromJobTitle;
  final String? transactionId;

  factory LoanRepayment.fromJson(Map<String, dynamic> json) {
    return LoanRepayment(
      id: json['id'] as String,
      amount: (json['amount'] as num).toInt(),
      paidAt: DateTime.parse(json['paid_at'] as String).toUtc(),
      fromJobId: json['from_job_id'] as String,
      fromJobTitle: json['from_job_title'] as String?,
      transactionId: json['transaction_id'] as String?,
    );
  }
}

/// `GET /me/credit` response, per `13_loans_home.md`.
///
/// Server-side scoring is **AI-driven and strict**: a model fed with
/// the worker's behavioural signals (jobs completed, on-time rate,
/// completion rate, ratings, tenure, repayment history) emits a
/// recalculated score after every clock-out and after every
/// repayment. The mobile never derives the score itself — it just
/// renders.
///
/// Beyond the bare score the response carries:
/// - [signals]: the inputs the model used, so the UI can show
///   "you've completed 47 jobs, 92% on time" etc.
/// - [riskFactors]: what's pulling the score down today, with
///   server-rendered copy. UI lists these as "what to fix".
/// - [improvementActions]: concrete server-recommended next steps,
///   each with the score-lift estimate the AI projects.
/// - [lastEvaluatedAt] / [modelVersion]: trace fields. UI shows
///   "Updated 5 minutes ago"; ops uses [modelVersion] to A/B test
///   scoring tweaks.
@immutable
class CreditProfile {
  const CreditProfile({
    required this.creditScore,
    required this.tier,
    required this.subtitle,
    required this.eligibility,
    this.nextUnlock,
    this.signals,
    this.riskFactors = const <CreditRiskFactor>[],
    this.improvementActions = const <CreditImprovementAction>[],
    this.lastEvaluatedAt,
    this.modelVersion,
  });

  /// 0–100. Strict tiers — see `13_loans_home.md`. Eligibility kicks
  /// in at 70+ rather than 60+ in the AI-scoring regime.
  final int creditScore;

  /// `building` (<60), `fair` (60–69), `good` (70–84), `excellent`
  /// (85+). Server-emitted; mobile never re-derives.
  final String tier;

  /// Server-rendered status line under the gauge.
  final String subtitle;

  final LoanEligibility eligibility;
  final NextUnlock? nextUnlock;

  /// Inputs the model used. Optional — older backends may not emit
  /// it, in which case the UI suppresses the "your stats" block.
  final CreditSignals? signals;

  /// What's pulling the score down right now. Newest first, capped at
  /// ~3 by the server. UI renders each as a tappable row with copy
  /// the server has tuned for the worker's locale.
  final List<CreditRiskFactor> riskFactors;

  /// Concrete next steps the model recommends, each with an
  /// estimated score lift. UI renders the highest-impact first.
  final List<CreditImprovementAction> improvementActions;

  final DateTime? lastEvaluatedAt;
  final String? modelVersion;

  factory CreditProfile.fromJson(Map<String, dynamic> json) {
    return CreditProfile(
      creditScore: (json['credit_score'] as num?)?.toInt() ?? 0,
      tier: json['tier'] as String? ?? 'building',
      subtitle: json['subtitle'] as String? ?? '',
      eligibility: LoanEligibility.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      nextUnlock: json['next_unlock'] is Map<String, dynamic>
          ? NextUnlock.fromJson(json['next_unlock'] as Map<String, dynamic>)
          : null,
      signals: json['signals'] is Map<String, dynamic>
          ? CreditSignals.fromJson(json['signals'] as Map<String, dynamic>)
          : null,
      riskFactors: (json['risk_factors'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CreditRiskFactor.fromJson)
              .toList(growable: false) ??
          const <CreditRiskFactor>[],
      improvementActions: (json['improvement_actions'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CreditImprovementAction.fromJson)
              .toList(growable: false) ??
          const <CreditImprovementAction>[],
      lastEvaluatedAt: json['last_evaluated_at'] is String
          ? DateTime.parse(json['last_evaluated_at'] as String).toUtc()
          : null,
      modelVersion: json['model_version'] as String?,
    );
  }
}

/// AI input snapshot — the same numbers the model fed on. Display
/// only; never used for client-side recompute.
@immutable
class CreditSignals {
  const CreditSignals({
    this.jobsCompleted = 0,
    this.onTimeRate = 0.0,
    this.completionRate = 0.0,
    this.averageRating = 0.0,
    this.tenureDays = 0,
    this.walletHealth = 0.0,
    this.priorLoansRepaid = 0,
    this.priorLoansDefaulted = 0,
  });

  final int jobsCompleted;
  /// 0.0–1.0. Fraction of accepted jobs the worker clocked-in for
  /// **on time** (within 5 minutes of start_time).
  final double onTimeRate;
  /// 0.0–1.0. Fraction of clock-ins that resulted in a successful
  /// clock-out (no abandonment).
  final double completionRate;
  /// 0.0–5.0.
  final double averageRating;
  /// Days since `joined_at`.
  final int tenureDays;
  /// 0.0–1.0. Composite of withdrawal frequency, wallet age, and
  /// idle-balance variance — picks up workers who immediately drain
  /// wallets vs. those who maintain reserves.
  final double walletHealth;
  final int priorLoansRepaid;
  final int priorLoansDefaulted;

  factory CreditSignals.fromJson(Map<String, dynamic> json) {
    return CreditSignals(
      jobsCompleted: (json['jobs_completed'] as num?)?.toInt() ?? 0,
      onTimeRate: (json['on_time_rate'] as num?)?.toDouble() ?? 0.0,
      completionRate:
          (json['completion_rate'] as num?)?.toDouble() ?? 0.0,
      averageRating:
          (json['average_rating'] as num?)?.toDouble() ?? 0.0,
      tenureDays: (json['tenure_days'] as num?)?.toInt() ?? 0,
      walletHealth: (json['wallet_health'] as num?)?.toDouble() ?? 0.0,
      priorLoansRepaid:
          (json['prior_loans_repaid'] as num?)?.toInt() ?? 0,
      priorLoansDefaulted:
          (json['prior_loans_defaulted'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class CreditRiskFactor {
  const CreditRiskFactor({
    required this.code,
    required this.severity,
    required this.copy,
    this.scoreImpact,
  });

  /// Stable machine-readable handle (`low_on_time_rate`,
  /// `recent_no_show`, `low_completion_rate`, `wallet_drain`,
  /// `prior_default`, ...). UI keys icons / branching off this.
  final String code;

  /// `low` | `medium` | `high`. Drives row tint.
  final String severity;

  /// Server-rendered, locale-aware. Render verbatim.
  final String copy;

  /// Estimated points removed from the score by this factor.
  /// Optional — when present the UI shows "−6" next to the row.
  final int? scoreImpact;

  factory CreditRiskFactor.fromJson(Map<String, dynamic> json) {
    return CreditRiskFactor(
      code: json['code'] as String,
      severity: json['severity'] as String? ?? 'medium',
      copy: json['copy'] as String? ?? '',
      scoreImpact: (json['score_impact'] as num?)?.toInt(),
    );
  }
}

@immutable
class CreditImprovementAction {
  const CreditImprovementAction({
    required this.code,
    required this.copy,
    this.scoreLift,
    this.deeplink,
  });

  /// Stable handle (`complete_one_more_job`, `arrive_on_time`,
  /// `keep_wallet_above_x`, ...). UI maps to icon + tap-target.
  final String code;

  /// Server-rendered call to action. e.g. "Complete one more on-time
  /// job to unlock ₦100k."
  final String copy;

  /// Estimated points gained by completing this action.
  final int? scoreLift;

  /// Optional `forge://...` deeplink when the action maps to a
  /// concrete in-app destination (e.g. the jobs feed).
  final String? deeplink;

  factory CreditImprovementAction.fromJson(Map<String, dynamic> json) {
    return CreditImprovementAction(
      code: json['code'] as String,
      copy: json['copy'] as String? ?? '',
      scoreLift: (json['score_lift'] as num?)?.toInt(),
      deeplink: json['deeplink'] as String?,
    );
  }
}

@immutable
class LoanEligibility {
  const LoanEligibility({
    required this.isEligible,
    required this.maxPrincipal,
    required this.minPrincipal,
    required this.interestRatePercent,
    required this.repaymentPercentPerJobDefault,
  });

  final bool isEligible;
  final int maxPrincipal;
  final int minPrincipal;
  final double interestRatePercent;
  final double repaymentPercentPerJobDefault;

  factory LoanEligibility.fromJson(Map<String, dynamic> json) {
    return LoanEligibility(
      isEligible: json['is_eligible'] as bool? ?? false,
      maxPrincipal: (json['max_principal'] as num?)?.toInt() ?? 0,
      minPrincipal: (json['min_principal'] as num?)?.toInt() ?? 0,
      interestRatePercent:
          (json['interest_rate_percent'] as num?)?.toDouble() ?? 0.0,
      repaymentPercentPerJobDefault:
          (json['repayment_percent_per_job_default'] as num?)?.toDouble() ??
              0.0,
    );
  }
}

@immutable
class NextUnlock {
  const NextUnlock({
    required this.scoreTarget,
    required this.maxPrincipalAtTarget,
    required this.jobsToUnlockEstimate,
  });

  final int scoreTarget;
  final int maxPrincipalAtTarget;
  final int jobsToUnlockEstimate;

  factory NextUnlock.fromJson(Map<String, dynamic> json) {
    return NextUnlock(
      scoreTarget: (json['score_target'] as num?)?.toInt() ?? 0,
      maxPrincipalAtTarget:
          (json['max_principal_at_target'] as num?)?.toInt() ?? 0,
      jobsToUnlockEstimate:
          (json['jobs_to_unlock_estimate'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------
// Work session (07) — server-authoritative shape.
// ---------------------------------------------------------------------

enum WorkSessionStatus {
  inProgress('in_progress'),
  submitting('submitting'),
  completed('completed'),
  paymentPending('payment_pending');

  const WorkSessionStatus(this.wire);
  final String wire;

  static WorkSessionStatus fromWire(String wire) {
    for (final s in WorkSessionStatus.values) {
      if (s.wire == wire) return s;
    }
    return WorkSessionStatus.inProgress;
  }
}

/// Where the session sits in the employer-signed payout flow.
///
/// `auto_review` is the default for a freshly clocked-out session — the
/// AI checks have passed and the employer has been pushed for review,
/// but the hold timer hasn't fired yet. `auto_released` and
/// `employer_confirmed` are the two clean release paths; `disputed`
/// freezes the payment pending ops review.
///
/// See `endpoint_resources/26_employer_signed_payouts.md`.
enum WorkSessionVerificationState {
  autoReview('auto_review'),
  autoReleased('auto_released'),
  employerConfirmed('employer_confirmed'),
  disputed('disputed');

  const WorkSessionVerificationState(this.wire);
  final String wire;

  static WorkSessionVerificationState? fromWire(String? wire) {
    if (wire == null) return null;
    for (final v in WorkSessionVerificationState.values) {
      if (v.wire == wire) return v;
    }
    return null;
  }
}

@immutable
class WorkSessionRecord {
  const WorkSessionRecord({
    required this.id,
    required this.applicationId,
    required this.status,
    required this.clockInAt,
    required this.payAmountPending,
    this.clockInLat,
    this.clockInLng,
    this.clockOutAt,
    this.expectedClockOutAt,
    this.durationHoursWorked = 0.0,
    this.payAmountDisbursed = 0,
    this.transactionId,
    this.proofPhotoUrl,
    this.verificationState,
    this.holdReleaseAt,
  });

  final String id;
  final String applicationId;
  final WorkSessionStatus status;
  final DateTime clockInAt;
  final double? clockInLat;
  final double? clockInLng;
  final DateTime? clockOutAt;
  final DateTime? expectedClockOutAt;
  final double durationHoursWorked;
  final int payAmountPending;
  final int payAmountDisbursed;
  final String? transactionId;
  final String? proofPhotoUrl;

  /// Position in the employer-signed payout flow. Null on older server
  /// builds (pre-`26_employer_signed_payouts.md`).
  final WorkSessionVerificationState? verificationState;

  /// UTC moment when an unreviewed session will auto-release. The
  /// pending-review screen runs the countdown off this and resyncs
  /// after every poll.
  final DateTime? holdReleaseAt;

  factory WorkSessionRecord.fromJson(Map<String, dynamic> json) {
    final loc = json['clock_in_location'];
    return WorkSessionRecord(
      id: json['id'] as String,
      applicationId: json['application_id'] as String? ?? '',
      status: WorkSessionStatus.fromWire(json['status'] as String),
      clockInAt: DateTime.parse(json['clock_in_at'] as String).toUtc(),
      clockInLat: loc is Map<String, dynamic>
          ? (loc['lat'] as num?)?.toDouble()
          : null,
      clockInLng: loc is Map<String, dynamic>
          ? (loc['lng'] as num?)?.toDouble()
          : null,
      clockOutAt: json['clock_out_at'] is String
          ? DateTime.parse(json['clock_out_at'] as String).toUtc()
          : null,
      expectedClockOutAt: json['expected_clock_out_at'] is String
          ? DateTime.parse(json['expected_clock_out_at'] as String).toUtc()
          : null,
      durationHoursWorked:
          (json['duration_hours_worked'] as num?)?.toDouble() ?? 0.0,
      payAmountPending: (json['pay_amount_pending'] as num?)?.toInt() ?? 0,
      payAmountDisbursed:
          (json['pay_amount_disbursed'] as num?)?.toInt() ?? 0,
      transactionId: json['transaction_id'] as String?,
      proofPhotoUrl: json['proof_photo_url'] as String?,
      verificationState: WorkSessionVerificationState.fromWire(
        json['verification_state'] as String?,
      ),
      holdReleaseAt: json['hold_release_at'] is String
          ? DateTime.parse(json['hold_release_at'] as String).toUtc()
          : null,
    );
  }
}

// ---------------------------------------------------------------------
// Preferences (18)
// ---------------------------------------------------------------------

@immutable
class RemotePreferences {
  const RemotePreferences({
    required this.notifications,
    required this.privacy,
  });

  final NotificationToggles notifications;
  final PrivacyToggles privacy;

  factory RemotePreferences.fromJson(Map<String, dynamic> json) {
    return RemotePreferences(
      notifications: NotificationToggles.fromJson(
        (json['notifications'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      privacy: PrivacyToggles.fromJson(
        (json['privacy'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
    );
  }
}

@immutable
class NotificationToggles {
  const NotificationToggles({
    this.newJobAlerts = true,
    this.applicationUpdates = true,
    this.paymentConfirmations = true,
    this.loanReminders = true,
  });

  final bool newJobAlerts;
  final bool applicationUpdates;
  final bool paymentConfirmations;
  final bool loanReminders;

  factory NotificationToggles.fromJson(Map<String, dynamic> json) {
    return NotificationToggles(
      newJobAlerts: json['new_job_alerts'] as bool? ?? true,
      applicationUpdates: json['application_updates'] as bool? ?? true,
      paymentConfirmations:
          json['payment_confirmations'] as bool? ?? true,
      loanReminders: json['loan_reminders'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'new_job_alerts': newJobAlerts,
        'application_updates': applicationUpdates,
        'payment_confirmations': paymentConfirmations,
        'loan_reminders': loanReminders,
      };
}

@immutable
class PrivacyToggles {
  const PrivacyToggles({this.allowLocationTrackingDuringWork = true});

  final bool allowLocationTrackingDuringWork;

  factory PrivacyToggles.fromJson(Map<String, dynamic> json) {
    return PrivacyToggles(
      allowLocationTrackingDuringWork:
          json['allow_location_tracking_during_work'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'allow_location_tracking_during_work':
            allowLocationTrackingDuringWork,
      };
}

// ---------------------------------------------------------------------
// Help (21)
// ---------------------------------------------------------------------

@immutable
class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.category,
    required this.title,
    required this.bodyMarkdown,
    required this.updatedAt,
  });

  final String id;
  final String category;
  final String title;
  final String bodyMarkdown;
  final DateTime updatedAt;

  factory HelpArticle.fromJson(Map<String, dynamic> json) {
    return HelpArticle(
      id: json['id'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      bodyMarkdown: json['body_markdown'] as String? ?? '',
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }
}

// ---------------------------------------------------------------------
// Uploads (22)
// ---------------------------------------------------------------------

@immutable
class UploadHandle {
  const UploadHandle({
    required this.id,
    required this.url,
    required this.expiresAt,
  });

  final String id;
  final String url;
  final DateTime expiresAt;

  factory UploadHandle.fromJson(Map<String, dynamic> json) {
    return UploadHandle(
      id: json['upload_id'] as String,
      url: json['url'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    );
  }
}
