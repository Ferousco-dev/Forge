# Employer-Signed Payouts — Backend Brief

**Audience:** backend (claude-coding-the-server) + ops + ML.
**Status:** mobile side is shipped; backend has the work below.
**Last edit:** 2026-05-13.

---

## 1. The thesis

Every existing fraud check in the platform — photo verification, GPS
geofence, liveness selfie, mocked-location detection — is the platform
*guessing* whether work happened. They're smart proxies, but proxies.

There's one party who isn't guessing: **the employer**. They had eyes
on the worker. They're the one whose money is leaving the platform.
They're the only entity with a real financial interest in not paying
for fake work.

So: **the best fraud defense is giving the ground-truth party a quiet
2-hour window to say "no."**

Default-accept. Silence releases payment automatically. The employer
has to actively dispute to block it — and disputes cost them
reputation.

The existing photo + GPS + AI verification stays in place. It runs
*during* the hold. Three independent rails:

| Signal                          | Stops                              | Runs when |
|---------------------------------|------------------------------------|-----------|
| Photo + GPS + liveness AI       | Identity + presence fraud          | At clock-out submit |
| Employer 2-hour dispute window  | Performance fraud (the hard one)   | During the hold |
| Risk-scored hold duration       | Velocity / pattern fraud           | At session creation |

Defeat one → the other two still hold the line.

---

## 2. State machine

```
                  clock-out submit (mobile)
                            │
                            ▼
              ┌─── server runs photo+GPS AI ───┐
              │                                │
        passes│                                │ fails
              ▼                                ▼
   verification_state =              session.status =
   'auto_review'                     'rejected' (existing)
   pay_amount_pending = X            payment never created
   hold_release_at = now + 2h
              │
              │   ┌──────────────────────────────────┐
              │   │ Three terminal paths:            │
              ├──▶│ A. Employer hits Confirm         │ → 'employer_confirmed'
              ├──▶│ B. Employer hits Dispute         │ → 'disputed'
              └──▶│ C. 2-hour cron fires, no dispute │ → 'auto_released'
                  └──────────────────────────────────┘
                                  │
                                  ▼
              A / C: pay_amount_disbursed = X
                     Squad transfer queued
                     Worker push: 'payment_processed'

              B:     payment frozen
                     Worker push: 'payment_disputed'
                     Dispute ticket opens, ops review
```

The mobile already renders all three terminal states from existing
fields (`pay_amount_pending` vs `pay_amount_disbursed`) plus the new
`verification_state` enum.

---

## 3. Database changes

### `WorkSession` (existing table) — add three columns

```sql
ALTER TABLE work_sessions
  ADD COLUMN verification_state TEXT NOT NULL DEFAULT 'auto_review'
    CHECK (verification_state IN (
      'auto_review',
      'employer_confirmed',
      'auto_released',
      'disputed'
    )),
  ADD COLUMN hold_release_at TIMESTAMPTZ,
  ADD COLUMN employer_reviewed_at TIMESTAMPTZ;
```

`hold_release_at` is only populated for sessions where the AI checks
passed and the employer hasn't acted yet. Null for already-released
or disputed sessions.

### `Dispute` (new table)

```sql
CREATE TABLE disputes (
  id              TEXT PRIMARY KEY,
  work_session_id TEXT NOT NULL REFERENCES work_sessions(id),
  opened_by       TEXT NOT NULL,             -- employer_id
  reason          TEXT NOT NULL,             -- enum, see below
  description     TEXT,                      -- free text from employer
  evidence_urls   TEXT[],                    -- optional photo proofs
  status          TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'resolved_for_worker', 'resolved_for_employer')),
  opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ,
  resolved_by     TEXT,                      -- ops user id
  resolution_note TEXT
);

CREATE INDEX disputes_open_idx ON disputes(status) WHERE status = 'open';
```

`reason` enum: `no_show` | `left_early` | `poor_quality` | `wrong_person` | `other`.

---

## 4. Endpoints

### 4.1 `POST /v1/sessions/{id}/clock-out` — update the response

This endpoint already exists. **Add two new fields to the response
body** when the session enters `auto_review`:

```json
{
  "session": {
    "id": "ses_…",
    "status": "pending_verification",
    "pay_amount_pending": 11500,
    "pay_amount_disbursed": 0,
    "verification_state": "auto_review",
    "hold_release_at": "2026-05-13T14:23:11Z",
    "clock_in_at": "...",
    "clock_out_at": "...",
    "duration_hours_worked": 0.85,
    "proof_photo_url": "https://..."
  }
}
```

The mobile reads `verification_state` + `hold_release_at` to drive the
pending-review screen's countdown. The same fields show up in
`GET /v1/sessions/{id}` so the screen's 30-second poller can detect
state transitions.

Return codes:
- `200 OK` — payment settled synchronously (only possible for low-risk
  workers with hold_duration = 0, see §6 below).
- `202 Accepted` — held for review. Mobile routes to the pending screen.
- Existing 422 codes unchanged.

### 4.2 `GET /v1/sessions/{id}` — already returns the same shape

No new endpoint needed. The poller hits this every 30s. Make sure the
response carries the same `verification_state` + `hold_release_at`
fields.

### 4.3 `POST /v1/employer/work-sessions/{id}/confirm` — NEW

**Audience:** employer dashboard.
**Auth:** Bearer (employer scope).
**Idempotency:** required, scoped to `confirm:{session_id}:{employer_id}`.

```http
POST /v1/employer/work-sessions/ses_abc123/confirm
Idempotency-Key: 7b5c8d8a-…
```

No request body. Returns the updated session:

```json
{
  "session": {
    "id": "ses_abc123",
    "verification_state": "employer_confirmed",
    "pay_amount_disbursed": 11500,
    "pay_amount_pending": 0,
    "transaction_id": "txn_…",
    "employer_reviewed_at": "2026-05-13T13:08:42Z"
  }
}
```

Side effects (in the same DB transaction):
1. Set `verification_state = 'employer_confirmed'`, `hold_release_at = NULL`.
2. Set `employer_reviewed_at = NOW()`.
3. Queue Squad transfer (existing payment pipeline).
4. Emit `payment_processed` push to the worker.
5. Cancel any pending `clock_out_pending_review` reminder push.

Errors:

| HTTP | code                   | meaning |
|------|------------------------|---------|
| 404  | `SESSION_NOT_FOUND`    | wrong id, or session belongs to a different employer |
| 409  | `INVALID_STATE`        | session is already released or disputed |
| 502  | `PAYMENT_PROVIDER_UNAVAILABLE` | Squad outage — retry-safe via idempotency |

### 4.4 `POST /v1/employer/work-sessions/{id}/dispute` — NEW

**Audience:** employer dashboard.
**Auth:** Bearer (employer scope).
**Idempotency:** required, scoped to `dispute:{session_id}:{employer_id}`.

```json
{
  "reason": "no_show",
  "description": "Worker never arrived. Photo doesn't match the site.",
  "evidence_upload_ids": ["upl_x9k…"]  // optional
}
```

Response:

```json
{
  "session": {
    "id": "ses_abc123",
    "verification_state": "disputed",
    "pay_amount_pending": 0,
    "pay_amount_disbursed": 0
  },
  "dispute": {
    "id": "dis_…",
    "status": "open",
    "opened_at": "2026-05-13T13:08:42Z"
  }
}
```

Side effects:
1. Set `verification_state = 'disputed'`, `hold_release_at = NULL`.
2. Create `Dispute` row.
3. **Reverse the pending payment** — clear `pay_amount_pending`. The
   funds stay in the employer's wallet pending resolution.
4. Emit `payment_disputed` push to the worker.
5. Record the dispute against both the worker's and the employer's
   trust scores (see §6).

Errors:

| HTTP | code                | meaning |
|------|---------------------|---------|
| 404  | `SESSION_NOT_FOUND` | as above |
| 409  | `INVALID_STATE`     | session is already released or already disputed |
| 422  | `REASON_REQUIRED`   | empty reason field |

### 4.5 Scheduled job — `auto-release-cron`

Runs every **60 seconds**. SQL:

```sql
UPDATE work_sessions
SET verification_state = 'auto_released',
    pay_amount_disbursed = pay_amount_pending,
    pay_amount_pending = 0,
    hold_release_at = NULL
WHERE verification_state = 'auto_review'
  AND hold_release_at < NOW()
  AND id NOT IN (SELECT work_session_id FROM disputes WHERE status = 'open')
RETURNING id, application_id, pay_amount_disbursed;
```

For each returned row:
1. Queue Squad transfer.
2. Emit `payment_processed` push to the worker.
3. Update the worker's credit score with the auto-released session as a positive signal (see §6).

The 60s cadence is the worst-case lag a worker sees past the 2-hour
timer. Anything tighter is overkill; anything looser starts feeling
broken.

---

## 5. Push notifications

### To the employer (new kind)

**`clock_out_pending_review`** — sent immediately after a clock-out
passes AI checks.

```json
{
  "notification": {
    "title": "Femi clocked out — ₦11,500",
    "body": "Tap to review before auto-release in 2 hours"
  },
  "data": {
    "kind": "clock_out_pending_review",
    "notification_id": "ntf_…",
    "deeplink": "forgeemployer://work-sessions/ses_abc123",
    "session_id": "ses_abc123",
    "channel_id": "forge_review"
  }
}
```

Optional reminder push at T+1.5h if no action — gives the employer a
30-min nudge before auto-release fires.

### To the worker — three new kinds

**`payment_held_for_review`** — sent the moment the server enters the
hold window. The mobile already has the pending-review screen open by
the time this lands, but we still emit it so the OS notification tray
shows the state change in the background.

```json
{
  "notification": {
    "title": "Your work is being verified",
    "body": "₦11,500 lands automatically in 2h if all looks good"
  },
  "data": {
    "kind": "payment_held_for_review",
    "session_id": "ses_abc123",
    "deeplink": "forge://jobs/job_abc/clock-out/pending",
    "channel_id": "forge_payments"
  }
}
```

**`payment_processed`** — existing push, no change. Sent on
auto-release OR employer confirm.

**`payment_disputed`** — sent when the employer hits Dispute.

```json
{
  "notification": {
    "title": "Your employer flagged this clock-out",
    "body": "We'll resolve within 24h. Tap for details."
  },
  "data": {
    "kind": "payment_disputed",
    "session_id": "ses_abc123",
    "deeplink": "forge://jobs/job_abc/clock-out/pending",
    "channel_id": "forge_payments"
  }
}
```

The mobile's pending-review screen polls the session every 30s, so
even without these pushes the UI converges to the right state. The
pushes are belt-and-braces for when the app is backgrounded.

---

## 6. Risk-scored hold duration (Phase 2)

Ship Phase 1 with a **flat 2-hour hold for everyone.** Once you have
~1,000 sessions of dispute data, layer in adaptive holds:

| Worker tier × Employer trust    | Hold duration |
|---------------------------------|---------------|
| Excellent × verified employer   | 0 s (synchronous settlement) |
| Good × verified employer        | 5 min        |
| Fair × verified employer        | 30 min       |
| Any worker × new employer       | 2 h          |
| Poor × any employer             | 4 h + manual ops review |

The mobile doesn't need to change for this — it reads
`hold_release_at` from the response and renders whatever duration the
server picks.

**Honest workers are rewarded with faster payouts the more clean
sessions they accumulate.** That's the right incentive.

---

## 7. AI training

You already run photo verification (Smile Identity + GPT-4 Vision).
The new layer is **learning from disputes** to predict P(dispute) at
clock-out time and set adaptive hold windows.

### 7.1 Training data structure

Each session is one row. Collect features at clock-out time, label
when the session resolves.

**Features** (~30 numeric/categorical):

```
# Photo
photo_face_match_score           [0..1]   liveness against profile
photo_scene_match_score          [0..1]   GPT-Vision: matches job_type?
photo_nonce_visible              bool     server-issued code present?
photo_exif_age_seconds           int      should be < 60
photo_phash_collision            bool     matches a prior session photo?

# Location
clock_in_geofence_distance_m     float
clock_out_geofence_distance_m    float
gps_accuracy_p50_m               float    across all samples
mock_location_detected           bool     isMocked at any sample
geofence_breach_count            int      samples outside 100m during session

# Time
duration_hours_worked            float
duration_vs_expected_ratio       float    actual / posted
clocked_out_early_vs_start_time  bool

# Worker history (30-day)
worker_completed_count           int
worker_disputed_count            int
worker_dispute_rate              float    disputed / completed
worker_avg_session_duration      float
worker_account_age_days          int
worker_credit_tier_int           int      poor=0, fair=1, good=2, excellent=3

# Employer history (30-day)
employer_completed_count         int
employer_disputed_count          int
employer_dispute_rate            float
employer_avg_payout              float
employer_account_age_days        int

# Cross signals
worker_x_employer_prior_jobs     int      have they worked together before?
worker_x_employer_avg_rating     float
worker_x_employer_concentration  float    % of worker's recent jobs with this employer
```

**Label** (categorical, set when the session terminates):

```
clean_employer_confirmed     # employer hit Confirm
clean_auto_released          # 2h timer fired, no dispute
fraud_employer_disputed_won  # dispute resolved in employer's favor
spurious_employer_disputed   # dispute resolved in worker's favor
```

For binary `P(dispute)`, collapse to:
- positive (`fraud`): `fraud_employer_disputed_won`
- negative (`clean`): `clean_employer_confirmed` + `clean_auto_released`
- ignore: `spurious_employer_disputed` (these say more about the employer)

### 7.2 Model choice

**Phase 1 (cold start, < 1k sessions):** no model. Flat 2h hold.

**Phase 2 (~1k–10k sessions):** logistic regression or gradient-boosted
trees (XGBoost / LightGBM). Both train in minutes, are interpretable,
and handle the mixed feature types without preprocessing. Don't reach
for a neural net here.

Target: P(dispute | features) ∈ [0, 1].

Hold-duration policy:

```
hold_minutes(P) = clip(120, lower=0, upper=240) where:
  P < 0.05  → 0        (instant payout)
  P < 0.15  → 5
  P < 0.30  → 30
  P < 0.50  → 120      (default)
  P >= 0.50 → 240 + manual ops flag
```

**Phase 3 (> 10k sessions):** add interaction features and SHAP for
explanations. Surface the top-3 contributing features per held
session to ops reviewers ("held because: distant clock-in + new
employer + photo phash collision").

### 7.3 Pipeline

```
clock-out submit ──▶ feature builder (server)
                          │
                          ▼
                    model inference (P(dispute))
                          │
                          ▼
                    hold_release_at = NOW() + hold_minutes(P)
                          │
                          ▼
                    write to work_sessions
                          │
                          ▼
                    return to mobile
```

Inference latency budget: < 100 ms. XGBoost models well under that;
a Python sidecar or a Cloud Run model endpoint both fit.

### 7.4 Watch for these failure modes

- **Survivorship bias on auto-released labels.** A session that
  auto-released because the employer ghosted isn't truly "clean."
  Weight `clean_auto_released` rows lower (e.g. 0.5) than
  `clean_employer_confirmed` rows (1.0) during training.
- **Employer collusion.** If a worker and employer share a high
  `worker_x_employer_concentration` AND consistently low duration,
  flag for manual review regardless of `P(dispute)`. Two parties
  can collude to look "clean" to the model.
- **Drift.** Retrain weekly. Fraud patterns evolve faster than your
  monthly cadence will catch.

---

## 8. Mobile changes (already shipped)

You don't need to do anything mobile-side. For reference:

- `WorkPhase.pendingReview` enum value added.
- `WorkSession` carries `holdReleaseAt` + `pendingAmount` (nullable
  outside the pending phase).
- `WorkSessionRecord` parses `verification_state` + `hold_release_at`
  from the clock-out response.
- New route `/jobs/:id/clock-out/pending`, new screen
  `PendingReviewScreen`:
  - 1 Hz countdown.
  - 30 s poller on `GET /v1/sessions/{id}`.
  - Auto-routes to work-complete when `pay_amount_disbursed > 0`.
  - Renders the disputed state when `verification_state = 'disputed'`.
  - Accelerates polling to 10 s when the local countdown hits zero
    (catches the cron's actual release).
- Submitting screen routes to pending OR complete based on the
  clock-out response. Backwards-compatible: if the server hasn't
  shipped `hold_release_at` yet, the screen defaults to `now + 2h`
  and works fine.

---

## 9. Rollout plan

**Week 1** — server ships endpoints + flat 2h hold for everyone.
Mobile is already in production. Watch:
- Dispute rate (target < 2% of completed sessions).
- Auto-release rate (target > 95%).
- Time-to-confirm for employers who DO act (target median < 15 min).

**Week 2-3** — tune the hold-by-tier rules from §6 based on observed
dispute patterns. Some tiers might tolerate shorter holds; some need
longer.

**Week 4** — start collecting features in §7.1. No model yet, just
the data pipeline.

**Month 2-3** — train Phase 2 P(dispute) model. A/B test
ML-driven holds against hardcoded tiers. Roll out the winner.

**Month 6+** — Phase 3 features + SHAP explanations + ops queue
sorted by P(dispute) descending.

---

## 10. The one-line summary

> The worker's photo proves they were there. The employer's silence
> proves the work happened. Everything else in the fraud stack
> supports this, doesn't replace it.

---

## 11. Backend checklist

- [ ] Migration: add `verification_state`, `hold_release_at`, `employer_reviewed_at` to `work_sessions`.
- [ ] Migration: create `disputes` table.
- [ ] Update `POST /v1/sessions/{id}/clock-out` to write the new state + return the new fields.
- [ ] Update `GET /v1/sessions/{id}` to return the same fields.
- [ ] Implement `POST /v1/employer/work-sessions/{id}/confirm`.
- [ ] Implement `POST /v1/employer/work-sessions/{id}/dispute`.
- [ ] Add 60-second `auto-release-cron`.
- [ ] Add three push kinds: `clock_out_pending_review`,
  `payment_held_for_review`, `payment_disputed`.
- [ ] Build the feature pipeline from §7.1 (no model yet — just emit
  the features to a logging table for now).
- [ ] OpenAPI doc the new endpoints + the new response fields.
- [ ] Update `endpoint_resources/07_work_session.md` to reference this
  doc.
