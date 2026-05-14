import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_config.dart';

// ---------------------------------------------------------------------
// Backwards-compat re-export hub.
//
// During the static-UI phase this file held mock providers; every
// screen and test imported them from `core/mock/mock_providers.dart`.
// As features migrate to the real backend, the live provider lives in
// `features/<feature>/state/...` and is re-exported here so existing
// imports keep compiling unchanged.
//
// Spec ↔ provider map (see `endpoint_resources/`):
//   01_auth                  → features/auth/state/auth_state.dart
//   02_jobs_feed             → features/jobs/state/jobs_state.dart
//   03_job_detail            → features/jobs/state/jobs_state.dart
//   05/06 my_applications    → features/work/state/applications_state.dart
//   09/10 transactions       → features/earnings/state/earnings_state.dart
//   11 withdraw / 12 banks   → features/earnings/state/earnings_state.dart
//   13/15 loans              → features/loans/state/loans_state.dart
//   16/17 profile            → features/profile/state/profile_state.dart
//   18 settings              → features/profile/state/preferences_state.dart
//   19 notifications         → features/profile/state/notifications_state.dart
//   21 help                  → features/profile/state/help_state.dart
//   22 uploads               → core/uploads/uploads_state.dart
// ---------------------------------------------------------------------

export '../../features/profile/state/profile_state.dart'
    show currentWorkerProvider;
export '../../features/jobs/state/jobs_state.dart'
    show
        nearbyJobsProvider,
        allJobsProvider,
        jobByIdProvider,
        jobDetailProvider;
export '../../features/work/state/applications_state.dart'
    show
        activeApplicationsProvider,
        applicationHistoryProvider,
        applicationDetailProvider;
export '../../features/earnings/state/earnings_state.dart'
    show
        transactionsProvider,
        transactionByIdProvider,
        bankAccountsProvider,
        supportedBanksProvider;
export '../../features/loans/state/loans_state.dart'
    show activeLoanProvider, creditProfileProvider, loanDetailProvider;
export '../../features/profile/state/notifications_state.dart'
    show notificationsProvider, notificationsPageProvider;

// ---------------------------------------------------------------------
// Connectivity (offline mode) — local-only, kept here.
// ---------------------------------------------------------------------
final Provider<bool> isOfflineProvider =
    Provider<bool>((Ref ref) => MockConfig.forceOffline);
