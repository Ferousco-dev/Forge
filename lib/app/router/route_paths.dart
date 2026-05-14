/// Centralized route path constants. Every route name lives here so:
/// - Typos are caught at compile time, not at runtime navigation.
/// - The walks-every-route test can iterate the full set without
///   hard-coding strings.
/// - Backend deep-link handling has a single source of truth.
class RoutePaths {
  const RoutePaths._();

  // Boot
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';

  // Auth
  static const String login = '/auth/login';
  static const String signup = '/auth/signup';
  static const String otp = '/auth/otp';
  static const String livenessCapture = '/auth/liveness';
  static const String profileSetup = '/auth/profile-setup';
  static const String permissionsLocation = '/auth/permissions/location';
  static const String permissionsNotifications =
      '/auth/permissions/notifications';

  // Home shell tabs (each is a top-level entry on the bottom nav)
  static const String jobs = '/jobs';
  static const String earnings = '/earnings';
  static const String loans = '/loans';
  static const String profile = '/profile';

  // Jobs sub-routes
  static const String jobsSearch = '/jobs/search';
  /// Active-jobs hub — every in-flight [WorkSession] grouped by phase,
  /// each row taps through to its resume route. Sits on the Profile
  /// branch so opening it from the Jobs tab leaves the jobs feed
  /// untouched in the background.
  static const String activeJobs = '/profile/active-jobs';
  static String jobDetail(String id) => '/jobs/$id';
  static String jobApply(String id) => '/jobs/$id/apply';
  static String jobStatus(String id) => '/jobs/$id/status';
  static String jobClockIn(String id) => '/jobs/$id/clock-in';
  static String jobInProgress(String id) => '/jobs/$id/in-progress';
  static String jobClockOutCamera(String id) => '/jobs/$id/clock-out/camera';
  static String jobClockOutReview(String id) => '/jobs/$id/clock-out/review';
  static String jobClockOutSubmitting(String id) =>
      '/jobs/$id/clock-out/submitting';
  static String jobClockOutPending(String id) =>
      '/jobs/$id/clock-out/pending';
  static String jobClockOutComplete(String id) =>
      '/jobs/$id/clock-out/complete';

  // Earnings sub-routes
  static const String transactions = '/earnings/transactions';
  static String transactionDetail(String id) => '/earnings/transactions/$id';
  static const String withdraw = '/earnings/withdraw';
  /// Confirmation receipt — pushed after a successful withdrawal so the
  /// worker has a visible record of where the money went (bank, last-4,
  /// reference, ETA) instead of a 4-second snackbar. Receives the
  /// [WithdrawalResult] + [WithdrawalPreview] via `state.extra`.
  static const String withdrawReceipt = '/earnings/withdraw/receipt';
  static const String linkBank = '/earnings/link-bank';

  // Loans sub-routes
  static const String loanApply = '/loans/apply';
  static const String loanPending = '/loans/pending';
  static const String loanApproved = '/loans/approved';
  static const String loanRejected = '/loans/rejected';
  static String loanDetail(String id) => '/loans/$id';

  // Employer profile (reached from "About the employer" on a job
  // detail). Lives at the top level so it can be linked from any
  // surface that surfaces an employer in the future.
  static String employerDetail(String id) => '/employers/$id';

  // Profile sub-routes
  static const String profileEdit = '/profile/edit';
  static const String profileApplications = '/profile/applications';
  static const String profileBookmarks = '/profile/bookmarks';
  static const String profileWorkHistory = '/profile/work-history';
  /// Receipt for a completed job, keyed by application id. Pulled from
  /// the cached `applicationHistoryProvider` first, then falls back to
  /// `GET /applications/:id` when the row isn't in cache (e.g. when
  /// the worker deep-links into a receipt from a notification).
  static String completedJobReceipt(String applicationId) =>
      '/profile/work-history/$applicationId';
  static const String profileNotifications = '/profile/notifications';
  static const String profileSettings = '/profile/settings';
  /// "Download my data / Request deletion" — GDPR-style data hub. Built
  /// on top of [DataExportService]; renders preview + share for the
  /// generated PDF.
  static const String profileManageData = '/profile/settings/manage-data';
  static const String profileHelp = '/profile/help';
  static const String profileTerms = '/profile/terms';
  static const String profilePrivacy = '/profile/privacy';

  /// Static paths used by the walks-every-route test. Parameterized
  /// routes are tested separately with sample IDs.
  static const List<String> allStaticPaths = <String>[
    splash,
    onboarding,
    login,
    signup,
    otp,
    livenessCapture,
    profileSetup,
    permissionsLocation,
    permissionsNotifications,
    jobs,
    earnings,
    loans,
    profile,
    jobsSearch,
    transactions,
    withdraw,
    withdrawReceipt,
    linkBank,
    loanApply,
    loanPending,
    loanApproved,
    loanRejected,
    profileEdit,
    profileApplications,
    profileBookmarks,
    profileWorkHistory,
    profileNotifications,
    activeJobs,
    profileSettings,
    profileManageData,
    profileHelp,
    profileTerms,
    profilePrivacy,
  ];

  /// Sample parameterized paths for the walks-every-route test.
  static List<String> sampleParameterizedPaths() => <String>[
        employerDetail('emp_001'),
        completedJobReceipt('app_001'),
        jobDetail('job_001'),
        jobApply('job_001'),
        jobStatus('job_001'),
        jobClockIn('job_001'),
        jobInProgress('job_001'),
        jobClockOutCamera('job_001'),
        jobClockOutReview('job_001'),
        jobClockOutSubmitting('job_001'),
        jobClockOutComplete('job_001'),
        transactionDetail('txn_001'),
        loanDetail('loan_001'),
      ];
}
