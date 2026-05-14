# Forge worker app — system architecture

End-to-end picture of every component, flow, and state machine.
Updated 2026-05-13.

If you only read one diagram, read **§2 the landscape**.
If you only read one section, read **§5.4 payment release lifecycle**.

---

## 1. The mental model

Forge is a **two-sided marketplace** (worker ↔ employer) glued by a
**payment processor** (Squad GTBank) and a **notification fabric**
(Firebase Cloud Messaging). The mobile app is the worker's surface;
the employer has a separate web dashboard out of scope here.

Three rules govern everything:

1. **Mobile expresses intent. Backend executes.** The mobile never
   talks to Squad, NIBSS, or any payment partner directly.
2. **Money moves async; the UI converges.** A clock-out kicks off a
   Squad transfer. The mobile renders the in-flight state via push
   notifications and polling.
3. **Idempotency keys make every retry safe.** Mint once, reuse on
   network blips, server returns the same response.

---

## 2. System landscape

```
                          ┌──────────────────────────────┐
                          │  Worker (mobile app, Flutter)│
                          └──────────────┬───────────────┘
                                         │ HTTPS /v1/...
                                         │ Bearer + Idempotency-Key
                                         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                                                                            │
│                          FORGE BACKEND (Railway)                           │
│       forgebe-production.up.railway.app                                    │
│                                                                            │
│  Controllers: Auth · Jobs · Applications · Sessions · Wallet · Loans       │
│               Ratings · Disputes · Notifications · Devices · AI · Help     │
│                                                                            │
│  Background workers:                                                       │
│    • auto-release-cron      (60s)   payouts after employer hold window     │
│    • squad-webhook-listener         settles processing → completed         │
│    • reconciliation-cron    (24h)   DB vs Squad ledger diff                │
│    • loan-repayment-cron    (5m)    deduct dues from incoming pay          │
│    • credit-score-cron      (24h)   recompute reliability / credit tier    │
│    • dispute-resolution-cron        ops queue surface                      │
│                                                                            │
│  Postgres: sessions, transactions, wallets, jobs, applications,            │
│            disputes, ratings, loans, devices, ai_audit                     │
│                                                                            │
└──┬───────────┬───────────┬───────────┬──────────┬────────────┬─────────────┘
   │           │           │           │          │            │
   │           │           │           │          │            │
   ▼           ▼           ▼           ▼          ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐   ┌──────────┐ ┌────────┐  ┌──────────┐
│Squad │   │ FCM  │   │Termii│   │Smile     │ │GPT-4   │  │  NIBSS   │
│GTBank│   │      │   │      │   │Identity  │ │Vision  │  │          │
└──┬───┘   └──┬───┘   └──┬───┘   └──────────┘ └────────┘  └──────────┘
   │          │          │
   │          │          │
   │          │   SMS / WhatsApp
   │          │   (OTP)
   │          │
   │      Push messages
   │      to devices
   │
   │   Bank transfers
   │   (wallets, payouts, withdrawals)
   │
   ▼
┌─────────────────┐    ┌─────────────────────┐
│ Worker's bank   │    │ Employer's wallet   │
│ (any NG bank)   │    │ (Squad-managed)     │
└─────────────────┘    └─────────────────────┘

Other actors (separate apps, out of scope but referenced):
   • Employer dashboard (web)
   • Bank credit-officer dashboard (web)
   • Ops/admin dashboard (web)
```

**Third-party responsibilities at a glance:**

| Provider        | Job                                                   |
|-----------------|-------------------------------------------------------|
| Squad GTBank    | Virtual NUBANs, fund transfers, settlement webhooks   |
| Firebase FCM    | Push delivery (Android tray, iOS APNs bridge)         |
| Termii          | SMS + WhatsApp OTP delivery                           |
| Smile Identity  | Liveness selfie verification                          |
| GPT-4 Vision    | Photo content sanity check (clock-out proof)          |
| NIBSS           | Bank account name resolution                          |
| OpenStreetMap   | Map tiles (light + dark)                              |

---

## 3. Mobile app architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                       │
│                                                                 │
│   GoRouter (declarative routes)                                 │
│      │                                                          │
│      ├─ splash, onboarding, login/signup/otp, liveness, profile-│
│      │  setup, permissions                                      │
│      ├─ home shell (jobs/earnings/loans/profile tabs)           │
│      ├─ /jobs/* (search, detail, apply, status, clock-in,       │
│      │           in-progress, clock-out/camera/review/           │
│      │           submitting/pending/complete)                   │
│      ├─ /profile/* (edit, applications, work-history,           │
│      │              notifications, settings, help, terms,       │
│      │              privacy)                                    │
│      └─ /earnings/* (transactions, withdraw, link-bank)         │
│                                                                 │
│   Screens are ConsumerStatefulWidget / ConsumerWidget           │
│   (Riverpod). Reusable widgets in shared/widgets/.              │
└──────────────────────┬──────────────────────────────────────────┘
                       │ ref.watch / ref.read
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                          STATE LAYER                            │
│                                                                 │
│   Riverpod providers per feature:                               │
│   • AsyncNotifier (auth_state.dart)        — session lifecycle  │
│   • FutureProvider (currentWorker, jobs,   — server-backed      │
│      transactions, loans, …)                                    │
│   • Notifier      (work_session_controller — local state +      │
│                    onboarding_state)         persistence        │
│   • StateProvider (theme_mode, mock_config)— UI prefs           │
└──────────────────────┬──────────────────────────────────────────┘
                       │ ref.read(<repo>Provider)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                       REPOSITORY LAYER                          │
│                                                                 │
│   One per domain — wraps the ApiClient with typed methods       │
│   and DTO conversion:                                           │
│                                                                 │
│   AuthRepository       JobsRepository      ApplicationsRepo     │
│   SessionsRepository   WalletRepository    TransactionsRepo     │
│   LoansRepository      BookmarksRepo       NotificationsRepo    │
│   ProfileRepository    HelpRepo            EmployerRepo         │
│   UploadsRepository    DeviceRepository    AiRepository         │
└──────────────────────┬──────────────────────────────────────────┘
                       │ via ApiClient
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE LAYER                         │
│                                                                 │
│   ApiClient (core/api/api_client.dart)                          │
│   • Base URL: ApiConfig.baseUrl (Railway prod)                  │
│   • Bearer access token (in-memory)                             │
│   • Refresh token (secure storage) — auto-refresh on 401        │
│   • Idempotency-Key auto-injected for write endpoints           │
│   • IdempotencyStore caches successful responses for 24h        │
│   • Standardised ApiException with code / message / details     │
│                                                                 │
│   SessionStorage (core/storage/session_storage.dart)            │
│   • Keychain (iOS) / encrypted SharedPreferences (Android)      │
│   • refresh_token, worker, device_id, bookmarks,                │
│     active_session pointer, push token cache                    │
│                                                                 │
│   NotificationsService (core/notifications/*)                   │
│   • Firebase Messaging wiring                                   │
│   • Permission flow + token registration                        │
│   • Foreground display via flutter_local_notifications          │
│   • Background handler (separate isolate, top-level fn)         │
│   • Deeplink stream → consumed by app.dart → GoRouter           │
│                                                                 │
│   Location services (core/location/current_location.dart)       │
│   • Geolocator real GPS                                         │
│   • No fallback to a fake coordinate — explicit error state     │
│                                                                 │
│   Theme (app/theme/) · spacing · text styles · palette          │
└─────────────────────────────────────────────────────────────────┘
```

### Persistence summary (device-side)

```
flutter_secure_storage:
  auth.refresh_token
  auth.refresh_expires_at
  auth.worker                  (cached profile snapshot)
  auth.needs_profile_setup
  app.onboarding_seen
  push.device_id               (stable per install, dvc_<uuid>)
  push.last_registered_token   (debounce vs current FCM token)
  bookmarks.v1                 (full Job blobs)
  work.active_session.v1       (jobId, applicationId, phase,
                                clockedInAt, server_session_id)
```

In-memory only (cleared on cold start):
- Access token (held by ApiClient)
- Current work session record + clock-out lat/lng/accuracy
- All Riverpod provider state

---

## 4. Backend architecture (server-side surface)

The mobile sees the backend as a flat `/v1/...` REST API. Internally
it's organised by domain — each controller maps onto an
`endpoint_resources/*.md` doc.

```
HTTP entry → Auth middleware (verifies Bearer, refreshes on 401)
           → Idempotency middleware (checks cache for write keys)
           → Controller → Service → Repository → Postgres
                                  ↳ Adapter ─→ Squad / FCM / Termii / etc.
                                  ↳ Push     ─→ FCM messages:send
                                  ↳ Audit log
```

**Domain ownership map (mobile-relevant):**

| Domain        | Endpoints                                          | Doc(s) |
|---------------|----------------------------------------------------|--------|
| Auth          | `/auth/otp/*`, `/auth/refresh`, `/auth/logout`, `/auth/profile-setup` | `01_auth.md`, `24b_fcm_and_otp_channels.md` |
| Jobs feed     | `/jobs`, `/jobs/{id}`                              | `02_jobs_feed.md`, `03_job_detail.md` |
| Applications  | `/jobs/{id}/apply`, `/applications`, `.../withdraw`| `04_apply_for_job.md`, `05_application_status.md`, `06_my_applications.md` |
| Work sessions | `/sessions`, `/sessions/{id}`, `.../clock-out`     | `07_work_session.md`, `07b_clock_out_submit.md`, `26_employer_signed_payouts.md` |
| Wallet        | `/wallet/withdrawals/*`, `/transactions`           | `09_transactions.md`, `10_transaction_detail.md`, `11_withdraw.md` |
| Bank accounts | `/banks`, `/me/bank-accounts`, `.../resolve`       | `12_bank_accounts.md` |
| Loans         | `/loans`, `/me/credit`, `/me/loans/active`         | `13_loans_home.md`, `14_loan_apply.md`, `15_loan_detail.md` |
| Profile       | `/me`, `/me/preferences`                           | `16_profile.md`, `17_edit_profile.md`, `18_settings.md` |
| Notifications | `/me/notifications/*`, `/me/devices`               | `19_notifications.md`, `24_push_notifications.md`, `24b_fcm_and_otp_channels.md` |
| Uploads       | `/uploads`, `/uploads/liveness`                    | `22_uploads.md`, `23_liveness.md` |
| Help          | `/help/articles`, `/help/tickets`                  | `21_help_support.md` |
| AI            | `/ai/jobs/{id}/summarize`, `/ai/search/parse`, `/ai/profile/extract` | `ai.md` |
| **Ratings (new)** | `/{worker,employer}/work-sessions/{id}/rating`, `/me/pending-ratings`, `/me/ratings` | `27_ratings_and_reliability.md` |

---

## 5. End-to-end flows

### 5.1 First-time signup

```
Splash
  │
  ├─ has refresh_token + valid? ─yes─▶ go to home (skip rest)
  │
  no
  ▼
Onboarding carousel (3 panels)
  │
  ▼
Signup screen (phone entry)
  │  POST /auth/otp/request {phone, flow=signup, preferred_channel=auto}
  │  ◀── {challenge_id, channel: 'whatsapp', channel_hint, …}
  ▼
OTP screen (badge shows WhatsApp / SMS / Push)
  │  POST /auth/otp/verify {challenge_id, code}
  │  ◀── {access_token, refresh_token, needs_profile_setup=true}
  ▼  also fires unawaited registerIfPermitted() so the device row
     is bound to the new worker_id as soon as auth lands
Liveness capture (front camera)
  │  POST /uploads/liveness (multipart, with device_metadata)
  │  ◀── {upload_id}     (Smile Identity verified server-side)
  ▼
Profile setup (name, primary skill, photo upload_id, preferred radius)
  │  POST /auth/profile-setup
  │  Idempotency-Key: signup-profile:<client_id>
  │  ◀── {worker, needs_profile_setup=false}
  ▼
Permissions screens (location → notifications)
  │  location grant → real GPS unblocks /jobs feed
  │  notifications grant → POST /me/devices {device_id, push_token,
  │                                           platform, app_version}
  ▼
Home shell (Jobs tab default)
```

### 5.2 Returning login

```
Splash
  │  refresh_token in secure storage? + not expired?
  │  POST /auth/refresh → fresh access_token (in-memory)
  │
  ├── yes → home
  │
  no / expired
  ▼
Login screen
  │  POST /auth/otp/request {phone, flow=login}
  ▼
OTP screen → verify → home
            (registerIfPermitted re-binds device to this worker)
```

### 5.3 The worker journey — discover to paid

```
Home / Jobs feed
  │  GET /jobs?lat=&lng=&radius_km=25     [nearbyJobsProvider]
  │  GET /jobs?lat=&lng=&radius_km=25 ext [allJobsProvider for map]
  │  Filters out applied-to + past start_time + team_first <30min
  │
  ▼
Tap card → Job detail
  │  GET /jobs/{id}
  │
  ▼
Tap Apply
  │  POST /jobs/{id}/apply
  │  Idempotency-Key: apply:<job_id>   (returns same app on retry)
  │  ◀── {application: status=applied}
  │
  ▼
Wait for employer (push: application_accepted → deeplink job/{id}/status)
  │
  ▼
Status screen "You got the job!"
  │  CTA "I've arrived" — disabled until <= 30 min before start_time
  │  (1Hz local ticker; gate flips automatically)
  │
  ▼ tap I've arrived
Clock-in screen
  │  LiveMap (OSM tiles) with worker pin + job pin + 100m geofence
  │  5s ticker re-invalidates currentLocationProvider
  │  Status banner: locating / unavailable / too_far(Xm) / at_site
  │  Clock-In CTA: disabled unless at_site
  │
  ▼ tap Clock In
  │  POST /sessions {application_id, lat, lng, accuracy_meters}
  │  Idempotency-Key: clock-in:<application_id>
  │  Server validates geofence + accuracy_meters ≤ 30
  │  ◀── 201 {session: {id, status=in_progress, clock_in_at}}
  │
  ▼ store session.id → WorkSession.serverSessionId
In-progress (on-the-clock) screen
  │  Live timer driven by clock_in_at (recovers across cold starts)
  │  GET /sessions/{id} polled every 60s (heartbeat)
  │  Worker can: call employer, report issue, view job details
  │
  ▼ tap Clock Out (only enabled after minimumDuration = 5 min)
Clock-out camera
  │  Camera capture (image_picker, no gallery, no flip)
  │  Re-verify geofence at the moment of snap (post-capture check)
  │  Stash photoPath + lat/lng/accuracy on WorkSession
  │
  ▼
Photo review
  │  Confirm or retake
  │
  ▼ tap Submit
Submitting screen
  │  Phase 1: read bytes, POST /uploads {purpose=clock_out_proof}
  │           ◀── {upload_id}
  │  Phase 2: POST /sessions/{id}/clock-out
  │           {proof_upload_id, lat, lng, accuracy_meters}
  │           Idempotency-Key: clock-out:<session_id>
  │
  │  Server runs AI + risk score (Smile + GPT-Vision + signals)
  │  Server decides hold duration from worker × employer tier
  │  Returns 200 (synchronous settlement) OR 202 (held for review)
  │  ◀── {session: {verification_state, pay_amount_pending|disbursed,
  │                  hold_release_at, transaction_id?}}
  │
  ├─ pay_amount_disbursed > 0 ──▶ Work-complete screen 🎉
  │                                (push payment_processed in parallel)
  │
  └─ pay_amount_pending > 0 ───▶ Pending-review screen
                                  (1Hz countdown + 30s poll loop —
                                   accelerates to 10s after countdown
                                   hits zero; auto-routes to complete
                                   when pay_amount_disbursed > 0)
```

### 5.4 Payment release lifecycle

This is the core of the platform's fraud + trust design. Three
independent rails defend the money flow:

```
clock-out request
       │
       ▼
┌──────────────────────────────┐
│ Rail 1: AI + GPS checks      │
│  • Smile face match          │
│  • GPT-Vision scene match    │
│  • Geofence ≤ 100m           │
│  • accuracy_meters ≤ 30      │
│  • isMocked = false          │
│  • EXIF age < 60s            │
│  • phash dedupe              │
└──────────────┬───────────────┘
               │ pass
               ▼
┌──────────────────────────────┐
│ Rail 2: Risk-scored hold     │
│  Worker × employer tier      │
│  → hold_minutes (0 / 5 / 30  │
│     / 120 / 240)             │
│  → hold_release_at = now+H   │
│  → verification_state =      │
│       'auto_review'          │
└──────────────┬───────────────┘
               │
               ├─ Hold = 0  (excellent × verified employer)
               │   └─▶ Squad transfer fires synchronously
               │       payment_processed push
               │       → Work-complete screen
               │
               └─ Hold > 0
                  │
                  ▼
┌──────────────────────────────┐
│ Rail 3: Employer review      │
│                              │
│  Three terminal outcomes:    │
│                              │
│  A. Employer Confirms        │
│     state → employer_confirmed
│     Squad transfer fires     │
│                              │
│  B. Auto-release cron        │
│     (no dispute by T+hold)   │
│     state → auto_released    │
│     Squad transfer fires     │
│                              │
│  C. Employer Disputes        │
│     state → disputed         │
│     pay_amount_pending = 0   │
│     Dispute row + ops queue  │
└──────────────┬───────────────┘
               │ outcome A/B
               ▼
       Squad transfer queued
               │
               ▼  (Squad webhook later)
       Transaction.status = completed
       Wallet balance reconciled
       payment_processed push fires
       (deduped if already sent)
               │
               ▼
       Worker's pending-review screen poll detects disbursal,
       pushReplaces to Work-complete celebration screen.
```

### 5.5 Withdrawal (worker → external bank)

```
Earnings → Withdraw screen
  │  GET /wallet/withdrawals/preview?amount=N
  │  ◀── {fee, eta, destination(bank,last4,name)}
  │
  ▼ tap Withdraw
  │  Mint stable _attemptId UUID (regenerated on amount edit)
  │  POST /wallet/withdrawals {amount}
  │  Idempotency-Key: withdraw:<_attemptId>
  │
  │  Server: validate balance → debit wallet immediately →
  │          create Transaction(kind=withdrawal, status=processing,
  │                              amount=-N)
  │          Squad: initiate_transfer
  │  ◀── 201 {transaction, wallet_balance_after}
  │
  ▼
Later, Squad webhook arrives:
  Transaction.status = completed | failed
  if completed → payment_processed push
  if failed   → re-credit wallet, withdrawal_failed push
```

### 5.6 Loan flow (one-shot)

```
Loans tab
  │  GET /me/credit  ◀── {score, tier, eligibility_ceiling, signals}
  │  GET /me/loans/active  ◀── existing loan? null on first run
  │
  ▼  No active loan, ceiling > 0
Apply screen (amount, term, confirm)
  │  POST /loans {amount, term_days}
  │  Idempotency-Key: loan:<client_attempt_id>
  │
  ├─ tier=excellent AND amount ≤ ₦50k
  │     ▶ auto-approved; bank disburses to default bank acct
  │     Transaction(kind=loan_disbursement, +amount)
  │     LoanRepayment schedule rows created
  │     push: loan_approved
  │
  └─ otherwise
        ▶ status=pending; queued for credit officer
        push: loan_under_review

Daily, loan-repayment-cron runs:
  For each incoming job_payment, check active loan schedule.
  If repayment is due, split: (repayment, net to wallet)
  Two Transaction rows: loan_repayment(-d), job_payment(+(X-d))
```

### 5.7 Push notification path

```
Server event (e.g. employer confirmed clock-out)
  │
  ▼
Server picks (kind, deeplink, channel_id, title, body)
  │
  ▼
firebase-admin .messaging().send({token, notification, data, android, apns})
  │
  ▼
FCM (Google infrastructure)
  │
  ├─ Android → device push channel
  │              │
  │              ├─ app FOREGROUND:
  │              │     onMessage listener fires
  │              │     ──▶ flutter_local_notifications.show()
  │              │         (uses Android channel from `data.channel_id`)
  │              │     ──▶ also emit on onForegroundMessage stream
  │              │         ──▶ refresh notificationsPageProvider
  │              │
  │              ├─ app BACKGROUND:
  │              │     OS draws the tray notification from `notification`
  │              │     background isolate runs firebaseMessagingBackgroundHandler
  │              │     (logs only — no provider access)
  │              │
  │              └─ app TERMINATED:
  │                    OS draws the tray notification
  │                    On tap → app cold-starts
  │                    getInitialMessage() drained at init →
  │                    deeplink emitted on onDeeplink stream
  │
  └─ iOS via APNs (requires Runner.entitlements aps-environment)
            UNNotificationCenter delivers
            setForegroundNotificationPresentationOptions handles the
            foreground case (system shows banner, no local-notif dupe)

Tap on the tray notification (any state)
  │
  ▼  message.data['deeplink']  e.g.  forge://transactions/txn_abc
  │
  ▼  NotificationsService.onDeeplink Stream<String>
  │
  ▼  app.dart _onDeeplink — Uri parse → GoRouter path
  │
  ▼  router.push('/earnings/transactions/txn_abc')
```

---

## 6. State machines

### 6.1 `WorkPhase` (mobile-side workflow state)

Persisted in `SessionStorage.work.active_session.v1`. Cold-start
restore re-hydrates and routes to the matching screen.

```
                start()
[null] ──────────────────▶ accepted
                              │
                              │ enterClockIn()
                              ▼
                           arriving
                              │
                              │ clockIn(serverSessionId, clockedInAt)
                              ▼
                           working ◀──────────┐
                              │               │
                              │ markPhotoCap  │ retakePhoto()
                              ▼               │
                           reviewing ─────────┘
                              │
                              │ enterSubmitting()
                              ▼
                          submitting
                              │
            ┌─────────────────┴────────────────┐
            │                                  │
   pay_amount_disbursed > 0      pay_amount_pending > 0
            │                                  │
            ▼                                  ▼
  complete() → done            enterPendingReview()
                                  → pendingReview
                                       │
                                       │ poll sees disbursed > 0
                                       ▼
                                  complete() → done
```

### 6.2 `verification_state` (server-side payment hold)

```
[clock-out accepted, AI passes]
              │
              ▼
        auto_review
              │
   ┌──────────┼──────────────┐
   │          │              │
   ▼          ▼              ▼
employer    auto_released  disputed
confirmed   (cron T+hold)  (frozen, ops queue)
   │          │
   └──┬───────┘
      │
      ▼
  pay_amount_disbursed = X
  Squad transfer queued
  payment_processed push
```

### 6.3 `Application.status`

```
                         apply
[no application] ────────────────▶ applied
                                      │
                  ┌───────────────────┼──────────────────┐
                  │                   │                  │
              employer            employer        worker withdraws
              accepts             rejects               │
                  │                   │                  ▼
                  ▼                   ▼               withdrawn
              accepted            rejected
                  │
              clock-in
                  ▼
              in_progress
                  │
              clock-out → completed
                          │
                          └─ disputed (still completed for the app,
                                       but payment may be frozen)
```

### 6.4 `Transaction.status`

```
                              [created]
                                  │
                                  ▼
                              processing
                                  │
                ┌─────────────────┴──────────────┐
                │                                │
       Squad webhook OK             Squad webhook FAIL
                │                                │
                ▼                                ▼
            completed                         failed
                                                 │
                                                 ▼
                                       wallet re-credited
                                       withdrawal_failed push
```

### 6.5 `OtpChannel` (per `24b_fcm_and_otp_channels.md`)

Server picks based on user's device-registration state and provider
availability. Mobile reads the response field and renders the matching
badge.

```
preferred_channel: auto
       │
       ▼
Has the user an active push device? ──yes──▶ channel: push
       │
       no
       ▼
WhatsApp send succeeds? ──yes──▶ channel: whatsapp
       │
       no (provider error)
       ▼
       channel: sms (Termii)
```

---

## 7. Data flow — where each field lives

### 7.1 Auth tokens
- **access_token** — ApiClient in-memory only. Cleared on app kill.
- **refresh_token** — SessionStorage (Keychain/encrypted SP). Single-use rotation: each refresh response carries a new pair.
- **First protected call** after cold start triggers a refresh round-trip; subsequent calls use the in-memory access token until it expires.

### 7.2 Worker profile
- **Server** = source of truth. `GET /me` is authoritative.
- **Device** = `auth.worker` blob cached for offline render; replaced on every `/me` response.

### 7.3 Work session
- **Server** holds the authoritative `clock_in_at`, `verification_state`, `pay_amount_*`.
- **Device** persists a *pointer* (jobId, applicationId, phase, server_session_id, clockedInAt). Full record refetched on resume — never trust local copy of money fields.

### 7.4 Wallet balance
- Denormalised on the worker record server-side, computed from the Transactions ledger. Daily cron audits for drift.

### 7.5 Bookmarks
- Pure-local for now. Stored as full Job blobs in `bookmarks.v1`. No server endpoint yet.

### 7.6 Device registration
- `(user_id, device_id)` pair on the server. `device_id` survives sign-out, dies on uninstall. `push_token` rotates and re-POSTs via `onTokenRefresh`.

---

## 8. Cross-cutting concerns

### 8.1 Auth + token refresh

```
Request flows through ApiClient:
  │
  ▼
authenticated=true?
  │
  yes
  ▼
Access token expiring within 60s leeway? ──yes──▶ refresh first
  │
  send with Bearer
  ▼
401 TOKEN_INVALID? ──yes──▶ try refresh → retry once
  │
  no / retry succeeded
  ▼
return response
  │
  refresh failed permanently? ──yes──▶ clear session, route to login
```

### 8.2 Idempotency

Every mutating endpoint takes `Idempotency-Key`. Naming conventions:

| Action       | Key shape                          | Lifetime |
|--------------|-----------------------------------|----------|
| Apply to job | `apply:<job_id>`                  | Stable per worker × job |
| Clock-in     | `clock-in:<application_id>`       | Stable forever |
| Clock-out    | `clock-out:<session_id>`          | Stable forever |
| Profile setup| `profile-setup:<client_uuid>`     | Per signup attempt |
| Withdraw     | `withdraw:<client_attempt_uuid>`  | Stable until amount edited |
| Link bank    | `link-bank:<bank_code>:<acct_no>` | Stable forever |
| Loan apply   | `loan:<client_attempt_uuid>`      | Stable per attempt |
| Rating       | `rating:<session_id>:<author_id>` | Stable forever |

Client minting: `IdempotencyStore` (core/api) generates and caches
keys; server caches responses for 24h.

### 8.3 Error handling

`ApiException(statusCode, code, message, details)`:
- `statusCode == 0` → network / offline. UI shows offline banner.
- `statusCode == 401` → auth client triggers refresh + retry.
- 4xx / 5xx with `error.code` → screens map specific codes to UX
  (e.g. `OUTSIDE_GEOFENCE` → retake photo, `RATE_LIMITED` → countdown).
- Unknown → render `error.message` verbatim.

### 8.4 Offline handling

- Read endpoints fail soft, surface `ErrorStateView` with retry.
- Mutating endpoints fail loud — no offline queue. The user retries
  when connectivity returns; idempotency keys keep retries safe.
- `OfflineBanner` shows on the home shell while the API client
  detects sustained network failure.

### 8.5 Logging / observability

- Debug builds: structured `debugPrint` per repository.
- Release builds: silent. Errors propagate as `ApiException`; the
  server's own audit log is the source of truth.
- No third-party crash analytics wired today.

---

## 9. Codebase index — where to find what

| Concern | Files |
|---|---|
| Entry point | [lib/main.dart](../lib/main.dart) |
| Root widget + router boot | [lib/app.dart](../lib/app.dart) |
| Routes table | [lib/app/router/route_paths.dart](../lib/app/router/route_paths.dart), [lib/app/router/app_router.dart](../lib/app/router/app_router.dart) |
| Theme | [lib/app/theme/](../lib/app/theme/) |
| HTTP client + idempotency | [lib/core/api/](../lib/core/api/) |
| Secure storage | [lib/core/storage/session_storage.dart](../lib/core/storage/session_storage.dart) |
| FCM service | [lib/core/notifications/](../lib/core/notifications/) |
| Location | [lib/core/location/current_location.dart](../lib/core/location/current_location.dart) |
| Uploads | [lib/core/uploads/](../lib/core/uploads/) |
| AI repository | [lib/core/ai/](../lib/core/ai/) |
| Models (all DTOs) | [lib/core/mock/models.dart](../lib/core/mock/models.dart) |
| Auth feature | [lib/features/auth/](../lib/features/auth/) |
| Jobs feature | [lib/features/jobs/](../lib/features/jobs/) |
| Work session | [lib/features/work/](../lib/features/work/) |
| Earnings / wallet | [lib/features/earnings/](../lib/features/earnings/) |
| Loans | [lib/features/loans/](../lib/features/loans/) |
| Profile | [lib/features/profile/](../lib/features/profile/) |
| Bookmarks | [lib/features/bookmarks/](../lib/features/bookmarks/) |
| Employers (read-only) | [lib/features/employers/](../lib/features/employers/) |
| Splash gate | [lib/features/splash/](../lib/features/splash/) |
| Shared widgets | [lib/shared/widgets/](../lib/shared/widgets/) |

---

## 10. Spec gap registry (what backend still owes)

From the various audits accumulated across these docs:

- `POST /v1/me/devices` + `DELETE /v1/me/devices/{id}` — `24_push_notifications.md` (mobile calls it; not in OpenAPI yet)
- `POST /v1/employer/work-sessions/{id}/confirm` + `.../dispute` — `26_employer_signed_payouts.md`
- Auto-release-cron — `26_employer_signed_payouts.md`
- `verification_state` + `hold_release_at` on session responses — `26_employer_signed_payouts.md`
- `preferred_channel` on OTP request + `channel` in response — `24b_fcm_and_otp_channels.md`
- `POST /v1/auth/otp/channels` — `24b_fcm_and_otp_channels.md` (Phase 3)
- Rating endpoints (worker + employer) — `27_ratings_and_reliability.md`
- `GET /v1/me/pending-ratings` and `PENDING_RATINGS_BLOCK_POSTING` rule — `27_ratings_and_reliability.md`
- Nightly `reliability_score` recompute — `27_ratings_and_reliability.md §5`
- Squad webhook HMAC verification + daily reconciliation cron — `00_system_architecture.md §8` (this doc)

iOS-only platform gap:
- `Runner.entitlements` with `aps-environment` — has to be added in Xcode

---

## 11. The one-line summary

> The mobile expresses intent. The backend, gated by AI + employer
> review + idempotency, executes. Squad moves money. FCM tells the
> worker. Everything else is plumbing to keep these four honest.
