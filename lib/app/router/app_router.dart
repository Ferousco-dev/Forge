import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/liveness_capture_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding/onboarding_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/permissions/location_permission_screen.dart';
import '../../features/auth/presentation/permissions/notification_permission_screen.dart';
import '../../features/auth/presentation/profile_setup_screen.dart';
import '../../features/bookmarks/presentation/bookmarks_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/state/auth_state.dart';
import '../../features/auth/state/onboarding_state.dart';
import '../../features/earnings/presentation/earnings_screen.dart';
import '../../features/employers/presentation/employer_detail_screen.dart';
import '../../features/earnings/presentation/link_bank_screen.dart';
import '../../features/earnings/presentation/transaction_detail_screen.dart';
import '../../features/earnings/presentation/transactions_screen.dart';
import '../../features/earnings/presentation/withdraw_receipt_screen.dart';
import '../../features/earnings/presentation/withdraw_screen.dart';
import '../../features/jobs/presentation/job_detail_screen.dart';
import '../../features/jobs/presentation/jobs_screen.dart';
import '../../features/jobs/presentation/jobs_search_screen.dart';
import '../../features/jobs/presentation/my_applications_screen.dart';
import '../../features/loans/presentation/loan_application_screen.dart';
import '../../features/loans/presentation/loan_approved_screen.dart';
import '../../features/loans/presentation/loan_detail_screen.dart';
import '../../features/loans/presentation/loan_pending_screen.dart';
import '../../features/loans/presentation/loan_rejected_screen.dart';
import '../../features/loans/presentation/loans_screen.dart';
import '../../features/profile/presentation/completed_job_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/help_support_screen.dart';
import '../../features/profile/presentation/legal_document_screen.dart';
import '../../features/profile/presentation/manage_data_screen.dart';
import '../../features/profile/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/profile/presentation/work_history_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/work/presentation/active_jobs_screen.dart';
import '../../features/work/presentation/application_status_screen.dart';
import '../../features/work/presentation/clock_in_screen.dart';
import '../../features/work/presentation/clock_out_camera_screen.dart';
import '../../features/work/presentation/photo_review_screen.dart';
import '../../features/work/presentation/pending_review_screen.dart';
import '../../features/work/presentation/submitting_screen.dart';
import '../../features/work/presentation/work_complete_screen.dart';
import '../../features/work/presentation/work_in_progress_screen.dart';
import '../../features/work/state/applications_state.dart';
import '../../features/work/state/work_session_controller.dart';
import 'home_shell.dart';
import 'placeholder_screen.dart';
import 'route_paths.dart';

/// Single source of truth for navigation.
///
/// Each route uses one of two builders:
/// - The real screen widget (currently: splash, login, signup) — ready
///   for production once the backend is wired.
/// - A [PlaceholderScreen] tagged with the implementation phase. The
///   placeholder is replaced one screen at a time as feature phases ship.
///
/// Bottom nav uses [StatefulShellRoute.indexedStack] so each tab keeps
/// its own `Navigator` history — the worker can drill into a job, switch
/// tabs, switch back, and resume exactly where they were.
GoRouter buildAppRouter() {
  final shellNavigatorJobs = GlobalKey<NavigatorState>(debugLabel: 'jobs');
  final shellNavigatorEarnings =
      GlobalKey<NavigatorState>(debugLabel: 'earnings');
  final shellNavigatorLoans = GlobalKey<NavigatorState>(debugLabel: 'loans');
  final shellNavigatorProfile =
      GlobalKey<NavigatorState>(debugLabel: 'profile');

  GoRoute placeholder(
    String path, {
    required String title,
    required String phase,
    String? routeId,
  }) =>
      GoRoute(
        path: path,
        builder: (BuildContext _, GoRouterState state) => PlaceholderScreen(
          title: title,
          phase: phase,
          routeId: routeId ?? state.pathParameters['id'],
        ),
      );

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: false,
    routes: <RouteBase>[
      // -----------------------------------------------------------------
      // Boot
      // -----------------------------------------------------------------
      GoRoute(
        path: RoutePaths.splash,
        builder: (BuildContext context, GoRouterState _) => Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => SplashScreen(
            // The splash entrance + minimum dwell + the session lookup
            // race in parallel — whichever finishes last unblocks the
            // route. So a returning user sees the wordmark for the
            // brand minimum, not a flash of login before being kicked
            // to /jobs.
            onReady: () async {
              // Resolve both auth state AND the persisted onboarding
              // flag before deciding. Reading `hasSeenOnboardingProvider`
              // synchronously here used to race against its background
              // hydration — on a cold cold-start the splash saw `false`
              // (the default) and sent returning users back through
              // the onboarding carousel. The `ensureLoaded` await fixes
              // that.
              final session = await ref.read(authSessionProvider.future);
              await ref
                  .read(hasSeenOnboardingProvider.notifier)
                  .ensureLoaded();

              // If the worker is authenticated and had a live work
              // session before the app was killed, rehydrate it from
              // disk so the on-the-clock timer resumes correctly from
              // the original clock-in timestamp. Wrapped in try/catch
              // so a network blip here can't block the splash route
              // — the worker can re-open the application manually if
              // restore fails.
              if (session is Authenticated) {
                try {
                  await ref
                      .read(workSessionProvider.notifier)
                      .restoreFromStorage((String applicationId) async {
                    final detail = await ref
                        .read(applicationsRepositoryProvider)
                        .fetchById(applicationId);
                    return detail.application;
                  });
                } catch (_) {
                  // Server unreachable / application 404 / parse fail —
                  // splash continues. The session stays unset; the
                  // worker can reopen it from My Applications when
                  // they're back online.
                }
              }

              if (!context.mounted) return;
              final destination = switch (session) {
                Authenticated() => RoutePaths.jobs,
                // Route via liveness, NOT directly to profile-setup.
                // The `photo_upload_id` profile-setup needs lives on
                // the in-memory `signupAvatarUploadIdProvider`, which
                // doesn't survive cold-start. Sending the worker
                // straight to profile-setup leaves them on a form
                // with no upload_id and the call fails server-side
                // (UPLOAD_NOT_FOUND). Liveness mints a fresh id,
                // then routes to profile-setup automatically.
                PendingProfileSetup() => RoutePaths.livenessCapture,
                Unauthenticated() =>
                  ref.read(hasSeenOnboardingProvider)
                      ? RoutePaths.login
                      : RoutePaths.onboarding,
              };
              context.go(destination);
            },
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.onboarding,
        builder: (BuildContext _, GoRouterState _) => const OnboardingScreen(),
      ),

      // -----------------------------------------------------------------
      // Auth — phone-entry → OTP → (signup) profile setup → permissions.
      // -----------------------------------------------------------------
      GoRoute(
        path: RoutePaths.login,
        builder: (BuildContext _, GoRouterState _) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        builder: (BuildContext _, GoRouterState _) => const SignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.otp,
        redirect: (BuildContext _, GoRouterState state) {
          // OTP isn't reachable without an active challenge. Bounce
          // back to login when the route is hit from a deep link or
          // a route-walking test.
          return state.extra is OtpFlowExtra ? null : RoutePaths.login;
        },
        builder: (BuildContext _, GoRouterState state) =>
            OtpScreen(extra: state.extra! as OtpFlowExtra),
      ),
      GoRoute(
        path: RoutePaths.livenessCapture,
        builder: (BuildContext _, GoRouterState _) =>
            const LivenessCaptureScreen(),
      ),
      GoRoute(
        path: RoutePaths.profileSetup,
        builder: (BuildContext _, GoRouterState _) =>
            const ProfileSetupScreen(),
      ),
      GoRoute(
        path: RoutePaths.permissionsLocation,
        builder: (BuildContext _, GoRouterState _) =>
            const LocationPermissionScreen(),
      ),
      GoRoute(
        path: RoutePaths.permissionsNotifications,
        builder: (BuildContext _, GoRouterState _) =>
            const NotificationPermissionScreen(),
      ),

      // Employer profile — top-level route (sibling of the shell) so
      // pushing it overlays the bottom nav. Reached from the "About
      // the employer" card on any job detail.
      GoRoute(
        path: '/employers/:id',
        builder: (BuildContext _, GoRouterState state) =>
            EmployerDetailScreen(
          employerId: state.pathParameters['id'] ?? '',
        ),
      ),

      // -----------------------------------------------------------------
      // Home shell — bottom nav with 4 branches.
      // -----------------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (BuildContext _, GoRouterState _,
                StatefulNavigationShell shell) =>
            HomeShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          // ---- Jobs branch ---------------------------------------------
          StatefulShellBranch(
            navigatorKey: shellNavigatorJobs,
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.jobs,
                builder: (BuildContext _, GoRouterState _) =>
                    const JobsScreen(),
                routes: <RouteBase>[
                  // Static `search` MUST be declared before the `:id`
                  // dynamic route — otherwise `/jobs/search` would be
                  // interpreted as a job whose id is "search".
                  GoRoute(
                    path: 'search',
                    builder: (BuildContext _, GoRouterState _) =>
                        const JobsSearchScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext _, GoRouterState state) =>
                        JobDetailScreen(
                      jobId: state.pathParameters['id'] ?? '',
                    ),
                    routes: <RouteBase>[
                      placeholder(
                        'apply',
                        title: 'Apply for job',
                        phase: 'Phase C (modal)',
                      ),
                      GoRoute(
                        path: 'status',
                        builder: (BuildContext _, GoRouterState state) =>
                            ApplicationStatusScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'clock-in',
                        builder: (BuildContext _, GoRouterState state) =>
                            ClockInScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'in-progress',
                        builder: (BuildContext _, GoRouterState state) =>
                            WorkInProgressScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'clock-out',
                        redirect: (BuildContext _, GoRouterState state) =>
                            '${state.matchedLocation}/camera',
                      ),
                      GoRoute(
                        path: 'clock-out/camera',
                        builder: (BuildContext _, GoRouterState state) =>
                            ClockOutCameraScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'clock-out/review',
                        builder: (BuildContext _, GoRouterState state) =>
                            PhotoReviewScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'clock-out/submitting',
                        builder: (BuildContext _, GoRouterState state) =>
                            SubmittingScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'clock-out/pending',
                        builder: (BuildContext _, GoRouterState state) =>
                            PendingReviewScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'clock-out/complete',
                        builder: (BuildContext _, GoRouterState state) =>
                            WorkCompleteScreen(
                          jobId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // ---- Earnings branch -----------------------------------------
          StatefulShellBranch(
            navigatorKey: shellNavigatorEarnings,
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.earnings,
                builder: (BuildContext _, GoRouterState _) =>
                    const EarningsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'transactions',
                    builder: (BuildContext _, GoRouterState _) =>
                        const TransactionsScreen(),
                  ),
                  GoRoute(
                    path: 'transactions/:id',
                    builder: (BuildContext _, GoRouterState state) =>
                        TransactionDetailScreen(
                      transactionId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                  GoRoute(
                    path: 'withdraw',
                    builder: (BuildContext _, GoRouterState _) =>
                        const WithdrawScreen(),
                  ),
                  GoRoute(
                    path: 'withdraw/receipt',
                    builder: (BuildContext _, GoRouterState state) =>
                        WithdrawReceiptScreen(
                      args: state.extra is WithdrawReceiptArgs
                          ? state.extra! as WithdrawReceiptArgs
                          : null,
                    ),
                  ),
                  GoRoute(
                    path: 'link-bank',
                    builder: (BuildContext _, GoRouterState _) =>
                        const LinkBankScreen(),
                  ),
                ],
              ),
            ],
          ),

          // ---- Loans branch --------------------------------------------
          StatefulShellBranch(
            navigatorKey: shellNavigatorLoans,
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.loans,
                builder: (BuildContext _, GoRouterState _) =>
                    const LoansScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'apply',
                    builder: (BuildContext _, GoRouterState _) =>
                        const LoanApplicationScreen(),
                  ),
                  GoRoute(
                    path: 'pending',
                    builder: (BuildContext _, GoRouterState _) =>
                        const LoanPendingScreen(),
                  ),
                  GoRoute(
                    path: 'approved',
                    builder: (BuildContext _, GoRouterState _) =>
                        const LoanApprovedScreen(),
                  ),
                  GoRoute(
                    path: 'rejected',
                    builder: (BuildContext _, GoRouterState _) =>
                        const LoanRejectedScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext _, GoRouterState state) =>
                        LoanDetailScreen(
                      loanId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ---- Profile branch ------------------------------------------
          StatefulShellBranch(
            navigatorKey: shellNavigatorProfile,
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.profile,
                builder: (BuildContext _, GoRouterState _) =>
                    const ProfileScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'edit',
                    builder: (BuildContext _, GoRouterState _) =>
                        const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'applications',
                    builder: (BuildContext _, GoRouterState _) =>
                        const MyApplicationsScreen(),
                  ),
                  GoRoute(
                    path: 'bookmarks',
                    builder: (BuildContext _, GoRouterState _) =>
                        const BookmarksScreen(),
                  ),
                  GoRoute(
                    path: 'work-history',
                    builder: (BuildContext _, GoRouterState _) =>
                        const WorkHistoryScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: ':id',
                        builder: (BuildContext _, GoRouterState state) =>
                            CompletedJobScreen(
                          applicationId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (BuildContext _, GoRouterState _) =>
                        const NotificationsScreen(),
                  ),
                  GoRoute(
                    path: 'active-jobs',
                    builder: (BuildContext _, GoRouterState _) =>
                        const ActiveJobsScreen(),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (BuildContext _, GoRouterState _) =>
                        const SettingsScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'manage-data',
                        builder: (BuildContext _, GoRouterState _) =>
                            const ManageDataScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'help',
                    builder: (BuildContext _, GoRouterState _) =>
                        const HelpSupportScreen(),
                  ),
                  GoRoute(
                    path: 'terms',
                    builder: (BuildContext _, GoRouterState _) =>
                        const TermsScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    builder: (BuildContext _, GoRouterState _) =>
                        const PrivacyScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
