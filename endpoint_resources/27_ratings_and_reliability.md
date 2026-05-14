# Ratings & Reliability — Backend Brief

**Audience:** backend (claude-coding-the-server) + ML + product.
**Status:** mobile has the consumer surface (profile screen renders
`average_rating` and `reliability_score` from `/me`). The write side
— the actual rating endpoints — is **not yet implemented anywhere.**
**Last edit:** 2026-05-13.

This document covers two related but distinct concepts:

1. **Rating** — qualitative, 1-to-5 star feedback exchanged between
   the worker and the employer after every completed session.
2. **Reliability score** — quantitative, 0-to-100 server-computed
   integer derived from on-time + completion + dispute behaviour. NOT
   a function of ratings.

Both surface on the worker's profile screen today. Only reliability
is real on the server; rating displays whatever stale value `/me`
returns (currently always 0.0 for new workers because nothing writes
to it).

---

## 1. The thesis

Ratings are the **softest** signal in the system. They reflect
sentiment, not facts. So the design has three properties:

- **Mandatory on the employer side** (but not blocking the worker's
  payout). The employer cannot post their NEXT job until they've
  rated their last batch of completed workers. Creates real
  incentive without holding worker money hostage.
- **Mutual + blind**. The worker also rates the employer after the
  session. Neither side sees the other's rating until both have
  submitted, or until 48 hours have passed. Defeats retaliation
  loops.
- **Separate from disputes**. A dispute means "I'm not paying." A
  rating means "they were fine but the music was loud." Conflating
  them creates bad incentives.

---

## 2. Endpoints

All four endpoints are **new**. Add them to OpenAPI and ship in one
release.

### 2.1 `POST /v1/employer/work-sessions/{id}/rating` — employer rates worker

**Audience:** employer dashboard.
**Auth:** Bearer (employer scope).
**Idempotency:** required, scoped to `rating:{session_id}:{employer_id}`.
The same employer submitting twice for the same session returns the
existing rating row — no duplicate, no rewrite.

**Preconditions:**
- The session belongs to this employer.
- The session is in a terminal state (`employer_confirmed`,
  `auto_released`, or `disputed` — yes, you rate even disputed
  sessions; the rating just doesn't affect a frozen payout).
- The employer has not already rated this session.

**Request:**

```json
{
  "stars": 5,
  "tags": ["punctual", "skilled"],
  "comment": "Got the bay loaded in half the time we expected."
}
```

| Field   | Type     | Constraints |
|---------|----------|-------------|
| stars   | int      | required, 1–5 |
| tags    | string[] | 0–3 from the vocabulary in §3 |
| comment | string   | optional, max 280 chars, profanity-filtered server-side |

**Response 201:**

```json
{
  "rating": {
    "id": "rat_…",
    "stars": 5,
    "tags": ["punctual", "skilled"],
    "comment": "Got the bay loaded in half the time we expected.",
    "submitted_at": "2026-05-13T14:23:11Z",
    "visible_to_subject": false
  }
}
```

`visible_to_subject` flips to `true` once the counterpart rating is
submitted OR 48 hours have passed. While `false`, the rating
contributes to the worker's `average_rating` aggregate but the
specific rating row is not exposed via the worker's read endpoints.

**Errors:**

| HTTP | code               | meaning |
|------|--------------------|---------|
| 404  | `SESSION_NOT_FOUND`| wrong session id or not yours |
| 409  | `ALREADY_RATED`    | this employer already rated this session |
| 422  | `INVALID_STATE`    | session has not reached a terminal state |
| 422  | `INVALID_STARS`    | not in 1–5 |
| 422  | `TOO_MANY_TAGS`    | more than 3 tags |
| 422  | `UNKNOWN_TAG`      | tag not in vocab |

### 2.2 `POST /v1/worker/work-sessions/{id}/rating` — worker rates employer

**Audience:** worker mobile app.
**Auth:** Bearer (worker scope).
**Idempotency:** required, scoped to `rating:{session_id}:{worker_id}`.

Mirror of 2.1 but with the worker→employer tag vocabulary (see §3).
Same response shape, same error codes.

### 2.3 `GET /v1/me/pending-ratings` — list sessions awaiting your rating

**Audience:** both the worker mobile app and the employer dashboard.
Server-side switches on the auth-scope to return the correct shape.
**Auth:** Bearer.

**Worker response:**

```json
{
  "items": [
    {
      "session_id": "ses_abc123",
      "job": { "id": "job_…", "title": "General laborer (Stocker)" },
      "employer": { "id": "emp_…", "name": "Maxim Corps", "logo_url": "…" },
      "completed_at": "2026-05-13T12:08:42Z"
    }
  ]
}
```

**Employer response** mirrors but with `worker` instead of `employer`.

Used by the mobile to gate the "Rate your last shift" reminder card on
the home sheet, and by the dashboard to enforce the
"can't-post-without-rating" rule in §4 below.

### 2.4 `GET /v1/me/ratings` — ratings I've received

**Audience:** worker mobile app + employer dashboard.
**Auth:** Bearer.
**Pagination:** cursor.

```json
{
  "items": [
    {
      "id": "rat_…",
      "stars": 5,
      "tags": ["punctual", "skilled"],
      "comment": "Got the bay loaded in half the time we expected.",
      "submitted_at": "2026-05-13T14:23:11Z",
      "from": {
        "id": "emp_…",
        "name": "Maxim Corps",
        "kind": "employer"
      },
      "job": { "id": "job_…", "title": "General laborer (Stocker)" }
    }
  ],
  "next_cursor": "…",
  "has_more": false
}
```

Only returns ratings where `visible_to_subject = true`.

### 2.5 `GET /v1/me` — extend response

The existing `/v1/me` already returns `average_rating`,
`reliability_score`, and `jobs_completed`. **Add** `ratings_count` (int):

```json
{
  "worker": {
    "id": "wrk_…",
    "average_rating": 4.7,
    "ratings_count": 23,
    "reliability_score": 92,
    "jobs_completed": 25,
    "tags_top": ["punctual", "skilled", "hard_working"]
  }
}
```

`tags_top` is the three most-frequently-attached tags across the
worker's last 30 days of ratings. Display-only.

---

## 3. Tag vocabulary

Fixed, server-validated, localised.

### Employer → worker

| wire           | label (en-NG)        |
|----------------|----------------------|
| punctual       | Punctual             |
| skilled        | Skilled              |
| courteous      | Courteous            |
| hard_working   | Hard-working         |
| careful        | Careful              |
| communicative  | Communicative        |
| would_rehire   | Would rehire         |

Negative tags are intentionally absent. Bad experiences go in
`comment` and (if severe) become disputes. Forcing "negative tagging"
in a 5-star UI weaponises the rating system; we don't.

### Worker → employer

| wire                  | label (en-NG)             |
|-----------------------|---------------------------|
| clear_instructions    | Clear instructions        |
| fair_pay              | Fair pay                  |
| respectful            | Respectful                |
| on_site_supervisor    | On-site supervisor        |
| safe_environment      | Safe environment          |
| would_work_again      | Would work again          |

---

## 4. Mandatory rating — the "can't-post-without-rating" rule

This is the brilliant bit. Don't gate **payouts** on the employer
rating — that punishes the worker for the employer being lazy. Gate
the **employer's next move** instead.

### Rule

When an employer hits `POST /v1/employer/jobs` (publish a new job),
the server pre-checks:

```sql
SELECT COUNT(*) FROM work_sessions ws
WHERE ws.employer_id = :employer_id
  AND ws.verification_state IN ('employer_confirmed', 'auto_released')
  AND ws.completed_at < NOW() - INTERVAL '24 hours'
  AND NOT EXISTS (
    SELECT 1 FROM ratings r
    WHERE r.work_session_id = ws.id AND r.author_role = 'employer'
  );
```

If the count is > 0, the response is:

```http
HTTP/1.1 422 Unprocessable Entity
{
  "error": {
    "code": "PENDING_RATINGS_BLOCK_POSTING",
    "message": "Rate your last 3 workers before posting a new job.",
    "details": {
      "pending_count": 3,
      "pending_session_ids": ["ses_a", "ses_b", "ses_c"]
    }
  }
}
```

Employer dashboard renders a modal listing those three workers, each
with a one-tap 5-star + optional tag picker. Once rated, the job-post
button re-enables.

**Why this works:**
- The employer wants to post a new job (high intent moment).
- Rating takes ~5 seconds per worker.
- The worker is already paid (no leverage problem).
- It's a soft block, not a hard one — employers who never want to
  post again aren't forced to rate, and that's fine; their account
  just won't grow.

**The 24-hour grace.** Sessions completed less than 24 hours ago do
NOT block job posting. Employers who run high-volume daily shifts
need to be able to post tomorrow's job tonight without rating
today's workers right away. The 24-hour window catches "next morning"
postings; anything older is fair game to block.

### Reminder pushes

T+3h after auto_release: `rate_your_worker` push to employer.
T+24h: a second reminder.
T+72h: rating ages out — recorded as `rated_lapsed`, doesn't count
toward the worker's `average_rating`. Counts against the employer's
own "rating compliance" score.

---

## 5. Reliability score — how it actually works

(This section exists because the mobile renders `reliability_score`
on the profile screen but there's no documented formula. Lock it
down here so backend and product agree.)

### Definition

`reliability_score` is an integer 0–100 computed nightly per worker.
It does **NOT** include rating. It's a pure behavioural signal:

```
reliability_score = round(100 * (
    0.40 * on_time_rate
  + 0.40 * completion_rate
  + 0.20 * (1 - dispute_rate)
))
```

Where, over the rolling 30-day window:

| Component        | Definition |
|------------------|------------|
| `on_time_rate`   | (clock-ins within 5 min of `job.start_time`) / (total clock-ins) |
| `completion_rate`| (sessions reaching `verification_state` IN (`employer_confirmed`, `auto_released`)) / (clock-ins) |
| `dispute_rate`   | (sessions resolved `resolved_for_employer`) / (terminal sessions) |

### Cold start (Bayesian prior)

For workers with fewer than 5 completed jobs, blend toward a neutral
prior of 75 so a single bad shift doesn't tank a new worker:

```
prior_jobs = 5
prior_score = 75

n = jobs_completed_30d
score_smoothed = (n * raw_score + prior_jobs * prior_score) / (n + prior_jobs)
```

The mobile already handles `jobs_completed == 0` by rendering an
em-dash ("—") on the reliability stat — see
[profile_screen.dart:415-425](../lib/features/profile/presentation/profile_screen.dart#L415-L425).
The smoothed score is for the 1–4 jobs window where math exists but
is statistically meaningless without smoothing.

### Tier bands

| Score range | Tier      | Surface |
|-------------|-----------|---------|
| 90–100      | Excellent | Verified pip on profile, shorter payout holds |
| 75–89       | Good      | Default tier |
| 60–74       | Fair      | Longer payout holds, surfaced at job-detail level |
| 0–59        | Poor      | Manual review on every clock-out, capped withdrawal velocity |

These bands feed directly into the hold-duration table in §6 of
`26_employer_signed_payouts.md`. Cross-document; if you change the
bands here, update there too.

### Refresh cadence

- Nightly recompute (UTC midnight) over the rolling 30-day window.
- Same-day events (a clock-in, a dispute) update the relevant
  counters in real time, but the displayed score doesn't refresh
  until the next nightly job.
- Why nightly: prevents whiplash UX (a worker watching their score
  tick up and down per session) and stabilises the model the credit
  scorer depends on.

### Distinct from credit score

`reliability_score` is a public-facing behavioural score (employers
see it).

`credit_score` is a private internal score (only the worker and the
bank loan partner see it). It includes reliability as one input among
many: `wallet_health`, `prior_loans_repaid`, `tenure_days`, etc.
See `13_loans_home.md`.

Don't conflate the two in API responses. The mobile already keeps
them on separate screens.

---

## 6. Mobile-side wiring (NEW — to be shipped with the endpoints)

Currently the mobile renders `average_rating` from `/me` but cannot
submit a rating. To unlock the worker→employer half:

1. **New screen:** `RateEmployerScreen` (1-tap 5-star + tag chips).
   Routed at `/jobs/:id/rate-employer` and `/profile/pending-ratings/:id`.
2. **Entry points:**
   - A "Rate your last shift" card on the home sheet when
     `/v1/me/pending-ratings` is non-empty.
   - A direct CTA on the work-complete screen.
3. **Repository:** new `RatingsRepository` with two methods —
   `rateEmployer(sessionId, stars, tags, comment)` and
   `pendingRatings()`.
4. **Display:** add a "Ratings" sub-page under Profile → Work history
   that consumes `GET /v1/me/ratings`.

Total mobile work: ~one day. Hold this until the four endpoints in
§2 are live in staging; building the UI against a 404 wastes review
cycles.

---

## 7. Schema

```sql
CREATE TABLE ratings (
  id              TEXT PRIMARY KEY,
  work_session_id TEXT NOT NULL REFERENCES work_sessions(id),
  author_id       TEXT NOT NULL,                  -- worker_id or employer_id
  author_role     TEXT NOT NULL
    CHECK (author_role IN ('worker', 'employer')),
  subject_id      TEXT NOT NULL,                  -- the counterpart
  stars           INT  NOT NULL CHECK (stars BETWEEN 1 AND 5),
  tags            TEXT[] NOT NULL DEFAULT '{}',
  comment         TEXT,
  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  visible_at      TIMESTAMPTZ                     -- when the subject can see it
);

CREATE UNIQUE INDEX ratings_one_per_author_per_session_idx
  ON ratings(work_session_id, author_role);

CREATE INDEX ratings_subject_idx ON ratings(subject_id, submitted_at DESC);
```

`visible_at` is set on insert to `NOW() + 48 hours`. Triggered to
`NOW()` immediately if the counterpart's rating is already on file.
The aggregate columns (`average_rating`, `ratings_count`, `tags_top`)
are denormalised onto the worker / employer row and updated by a
post-insert trigger on `ratings`.

---

## 8. AI / fraud touchpoints

Ratings feed the existing `P(dispute)` model from
`26_employer_signed_payouts.md §7` as additional features:

| Feature                       | Why |
|-------------------------------|-----|
| `worker_avg_rating_30d`       | Low ratings precede disputes |
| `worker_ratings_count_30d`    | Low data → wider hold window |
| `employer_avg_given_rating`   | Employers who chronically 1-star everyone are noisy |
| `worker_x_employer_avg_rating`| Pair-level signal |

Two adversarial behaviours to watch and dampen at the model level:

1. **Retaliation cascade.** Worker rates employer 1★, employer
   counter-rates 1★ within minutes. The 48h blind window already
   prevents this UX-wise, but logging `submission_delta_seconds`
   lets you detect operationally-coordinated retaliation by
   employers using a side channel.
2. **Concentration fraud.** Employer X always gets 5★ from their
   workers AND always gives 5★. Combined with high
   `worker_x_employer_concentration`, this pattern is the signal
   for collusion. Flag the pair for manual review when both signals
   exceed thresholds.

---

## 9. Backend checklist

- [ ] Migration: create `ratings` table with the schema in §7.
- [ ] Migration: add `ratings_count` and `tags_top` columns + trigger
  on the worker and employer profiles.
- [ ] Implement `POST /v1/employer/work-sessions/{id}/rating`.
- [ ] Implement `POST /v1/worker/work-sessions/{id}/rating`.
- [ ] Implement `GET /v1/me/pending-ratings` with role-switched
  response shape.
- [ ] Implement `GET /v1/me/ratings` with cursor pagination.
- [ ] Extend `GET /v1/me` response with `ratings_count` + `tags_top`.
- [ ] Enforce the `PENDING_RATINGS_BLOCK_POSTING` rule on
  `POST /v1/employer/jobs`.
- [ ] Add `rate_your_worker` push kind (T+3h, T+24h schedule).
- [ ] Nightly cron to recompute `reliability_score` per §5 +
  Bayesian smoothing for new workers.
- [ ] OpenAPI doc all of the above.
- [ ] Cross-update `26_employer_signed_payouts.md §6` if you tune
  the tier bands.

---

## 10. The one-line summary

> Reliability is what the worker **does**. Rating is what the
> employer **says**. Both go on the profile. Neither gates the
> other — but the next job post is gated on the rating debt.
