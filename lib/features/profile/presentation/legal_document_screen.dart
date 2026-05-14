import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/back_button_header.dart';

/// One section in a legal document. Title is rendered as a section
/// header, [paragraphs] become body paragraphs with normal spacing.
@immutable
class LegalSection {
  const LegalSection({required this.title, required this.paragraphs});
  final String title;
  final List<String> paragraphs;
}

/// Generic legal-document viewer. The Terms and Privacy screens reuse
/// this — they just pass different content. Layout: standard back
/// header, document title, "last updated" date, sectioned body.
///
/// The placeholder content below is non-binding boilerplate the
/// product team will replace with reviewed legal copy. The structure
/// (Sections + last-updated date + acknowledgement footer) is the
/// shape backend can paginate when these move to a fetched
/// `GET /v1/legal/{document}` endpoint.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  final String title;
  final String lastUpdated;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: BackButtonHeader(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Last updated $lastUpdated',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    for (final section in sections) ...<Widget>[
                      Text(
                        section.title,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: palette.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final para in section.paragraphs) ...<Widget>[
                        Text(
                          para,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.onSurfaceVariant,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: palette.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.outlineVariant),
                      ),
                      child: Text(
                        'Questions? Reach out at support@forge.ng or '
                        'from the in-app Help & support screen.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Terms of service — placeholder copy
// ---------------------------------------------------------------------

/// Content displayed on the Terms screen. Plain Dart so it can be
/// reviewed in a PR; replace section-by-section with the reviewed
/// legal text. When the backend grows a `GET /v1/legal/terms`
/// endpoint, swap this constant for a server-fetched provider —
/// the screen widget doesn't need to change.
const List<LegalSection> kTermsSections = <LegalSection>[
  LegalSection(
    title: '1. Who we are',
    paragraphs: <String>[
      'Forge ("we", "us") operates the Forge worker mobile app, a '
          'platform connecting day-rate workers in Nigeria with vetted '
          'employers. By creating an account you ("you", "the worker") '
          'agree to these terms.',
    ],
  ),
  LegalSection(
    title: '2. Eligibility',
    paragraphs: <String>[
      'You must be at least 18 years old, a Nigerian resident, and '
          'have a valid phone number you control. You may not transfer '
          'your account, share login credentials, or operate multiple '
          'worker accounts on the platform.',
    ],
  ),
  LegalSection(
    title: '3. Jobs and clock-in',
    paragraphs: <String>[
      'Applying for a job is a non-binding expression of interest. An '
          'employer accepting your application creates a commitment to '
          'show up at the job site, on time, ready to work as posted.',
      'Clock-in requires you to be physically within 100 metres of the '
          'pinned site and to grant the app location access. Spoofed '
          'locations, photo manipulation, or sending another person in '
          'your place are violations of these terms and may result in '
          'permanent suspension and forfeiture of pending payouts.',
    ],
  ),
  LegalSection(
    title: '4. Payments',
    paragraphs: <String>[
      'Successful clock-out triggers an automatic Squad-routed payout '
          'to your wallet. Payouts may be held in a verification window '
          '(default 2 hours) during which the employer may confirm or '
          'dispute the session. Unreviewed sessions auto-release at the '
          'end of the window.',
      'Withdrawals from your wallet to a linked bank account are '
          'processed via Squad and typically settle within minutes. '
          'Forge does not custody your funds beyond what is required to '
          'process the transfer.',
    ],
  ),
  LegalSection(
    title: '5. Ratings and reliability',
    paragraphs: <String>[
      'After every completed job, the employer rates you on a five-star '
          'scale. Your average rating, reliability score (computed from '
          'on-time clock-in rate and successful completion rate), and '
          'dispute history are visible to future employers and inform '
          'job-matching and credit decisions.',
      'You may dispute a rating you believe to be unfair through the '
          'Help & support screen within 7 days. Resolved disputes are '
          'noted on your record.',
    ],
  ),
  LegalSection(
    title: '6. Loans',
    paragraphs: <String>[
      'Forge surfaces short-term loans from our bank partners based on '
          'your credit tier, computed nightly from job-completion '
          'signals. Loans are between you and the bank; Forge is a '
          'facilitator. Repayments may be deducted automatically from '
          'your job payouts as set out in your loan agreement.',
    ],
  ),
  LegalSection(
    title: '7. Suspension and termination',
    paragraphs: <String>[
      'We may suspend or terminate your account for fraud, repeated '
          'no-shows, repeated sustained employer disputes, or behaviour '
          'that endangers other workers, employers, or site safety. '
          'You may close your account at any time from Settings; '
          'pending payouts settle before closure completes.',
    ],
  ),
  LegalSection(
    title: '8. Changes to these terms',
    paragraphs: <String>[
      'We may update these terms. Material changes are surfaced in the '
          'app and require acknowledgement before continuing to use the '
          'platform. The "last updated" date at the top of this page '
          'reflects the most recent revision.',
    ],
  ),
];

/// Content displayed on the Privacy screen.
const List<LegalSection> kPrivacySections = <LegalSection>[
  LegalSection(
    title: '1. What we collect',
    paragraphs: <String>[
      'Identity: your name, phone number, profile photo, primary skill, '
          'and the liveness selfie captured during signup.',
      'Bank: account number, bank name, and the resolved NIBSS account '
          'name for each linked account. Stored encrypted at rest.',
      'Work: every clock-in and clock-out — timestamp, GPS coordinates, '
          'GPS accuracy, and the photo proof captured at clock-out. We '
          'sample GPS at low frequency during your shift solely to '
          'verify continued presence at the site.',
      'Device: a stable per-install device identifier, your FCM push '
          'token, app version, and platform. Used only for delivering '
          'push notifications and for fraud detection.',
    ],
  ),
  LegalSection(
    title: '2. How we use it',
    paragraphs: <String>[
      'We use your data to verify identity, route you to jobs near '
          'your location, process payouts via Squad, compute your '
          'reliability and credit scores, and detect fraud. We do not '
          'sell your data to advertisers.',
      'Anonymised aggregate signals (e.g. dispute rates by region) may '
          'be used internally to improve fraud-detection models.',
    ],
  ),
  LegalSection(
    title: '3. Who we share it with',
    paragraphs: <String>[
      'Employers see your name, profile photo, primary skill, rating, '
          'reliability score, and the photo proof from sessions you '
          'worked for them.',
      'Squad (our payment processor) receives the minimum data needed '
          'to route transfers — typically your virtual NUBAN, your '
          'linked bank account number, and the amount.',
      'Bank loan partners see your credit tier, the factors driving it, '
          'and your linked bank account when you apply for a loan with '
          'them.',
      'Smile Identity processes your liveness selfie to verify it is a '
          'real person; the underlying image is not retained beyond the '
          'verification window.',
      'Law enforcement may receive data when required by a valid '
          'Nigerian court order or to protect platform safety.',
    ],
  ),
  LegalSection(
    title: '4. Location while working',
    paragraphs: <String>[
      'During an active work session we sample your GPS periodically '
          'to verify continued presence at the job site. Sampling stops '
          'the moment you clock out. You can opt out of in-session '
          'sampling from Settings, though doing so may flag sessions '
          'for additional review.',
      'Outside of an active session, we only read your location when '
          'you open the Jobs tab (to filter the feed by distance) or '
          'when you actively clock in.',
    ],
  ),
  LegalSection(
    title: '5. Push notifications',
    paragraphs: <String>[
      'When you grant notification permission, we send you alerts for '
          'application updates, payment events, loan decisions, and '
          'platform announcements. You can manage individual channels '
          'from your device settings or disable all push from the '
          'Notifications screen.',
    ],
  ),
  LegalSection(
    title: '6. Retention',
    paragraphs: <String>[
      'Identity records: kept for the lifetime of the account, plus '
          '7 years after closure to meet Nigerian financial-services '
          'regulations.',
      'Work sessions: kept indefinitely as part of your work history. '
          'You may request redaction of specific sessions through '
          'support; we comply except where retention is legally '
          'mandated.',
      'Photo proofs: retained for the duration of the dispute window '
          'plus 90 days for audit, then deleted.',
      'Push tokens: deleted when you log out, uninstall the app, or '
          'when FCM reports the token as invalid.',
    ],
  ),
  LegalSection(
    title: '7. Your rights',
    paragraphs: <String>[
      'You can request a copy of your data, correct inaccuracies, or '
          'close your account at any time from Settings. Account '
          'closure removes your profile from employer search and '
          'cancels any pending applications.',
    ],
  ),
  LegalSection(
    title: '8. Contact',
    paragraphs: <String>[
      'For privacy questions or data requests, contact our Data '
          'Protection Officer at privacy@forge.ng. We respond within '
          '7 working days.',
    ],
  ),
];

/// Concrete screens — small wrappers around [LegalDocumentScreen].

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Terms of service',
      lastUpdated: '13 May 2026',
      sections: kTermsSections,
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Privacy policy',
      lastUpdated: '13 May 2026',
      sections: kPrivacySections,
    );
  }
}
