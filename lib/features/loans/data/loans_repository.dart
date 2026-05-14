import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// Loans + credit feature client. Specs:
///
/// - `13_loans_home.md` — `GET /me/credit`, `GET /me/loans/active`
/// - `14_loan_apply.md` — `POST /loans`
/// - `15_loan_detail.md` — `GET /loans/:id`
///
/// **Credit scoring is AI-driven and strict, server-side.** The
/// mobile sends nothing to compute; it just reads what the server's
/// model has emitted. Behavioural inputs (jobs completed, on-time
/// rate, completion rate, ratings, tenure, wallet health, prior
/// repayment history) all live in [CreditProfile.signals] for
/// display, but the score, tier, and ceilings are server outputs the
/// mobile must trust.
///
/// Strict-tier cutoffs (per the v2 scoring regime documented in
/// `13_loans_home.md`):
///
///   - `building`  — score < 60     (not eligible)
///   - `fair`      — 60–69          (not eligible)
///   - `good`      — 70–84          (eligible — ₦20k → ₦50k)
///   - `excellent` — 85+            (eligible — up to ₦100k+)
///
/// The eligibility floor moved from 60 (rule-based v1) to 70
/// (AI-scored v2) — drop a worker below 70 and the model takes the
/// loan affordance away. Server enforces; mobile renders the new
/// `is_eligible` flag without re-checking the cutoff.
class LoansRepository {
  LoansRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  /// `GET /me/credit` — AI-evaluated score + signals + risk factors
  /// + improvement actions. Re-fetched on pull-to-refresh and after
  /// every clock-out (the model rescores every successful job).
  Future<CreditProfile> fetchCredit() async {
    final json = await _client.get('/me/credit', authenticated: true);
    return CreditProfile.fromJson(json);
  }

  /// `GET /me/loans/active`. Null when the worker has no
  /// pending/active/approved loan.
  Future<Loan?> fetchActive() async {
    final json = await _client.get(
      '/me/loans/active',
      authenticated: true,
    );
    final loanJson = json['loan'];
    return loanJson is Map<String, dynamic>
        ? Loan.fromJson(loanJson)
        : null;
  }

  Future<Loan> fetchById(String id) async {
    final json = await _client.get('/loans/$id', authenticated: true);
    return Loan.fromJson(json);
  }

  /// `POST /loans` — submit a loan application. The server **re-runs
  /// the AI scorer at submit time** (per `14_loan_apply.md` notes),
  /// so a credit profile that was eligible 2 minutes ago can come
  /// back as `NOT_ELIGIBLE` if e.g. the worker no-showed in between.
  /// The mobile catches that 422 and routes back to the loans home.
  Future<Loan> apply({
    required int principal,
    required double repaymentPercentPerJob,
    required String clientLoanId,
    String? purpose,
  }) async {
    final json = await _client.post(
      '/loans',
      authenticated: true,
      idempotent: true,
      // Worker can have at most one pending/active loan at a time, so
      // the client-side id is a per-attempt UUID minted when the user
      // first taps "Apply for loan". 409 ACTIVE_LOAN_EXISTS comes
      // through `details.loan` and the screen routes there.
      idempotencyAction: 'loan-apply:$clientLoanId',
      body: <String, dynamic>{
        'principal': principal,
        'repayment_percent_per_job': repaymentPercentPerJob,
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
      },
    );
    return Loan.fromJson(json['loan'] as Map<String, dynamic>);
  }
}
