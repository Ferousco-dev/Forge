# Loans Home — AI Credit Score, Eligibility, Active Loan

Covers `lib/features/loans/presentation/loans_screen.dart`.

The screen shows: credit-score gauge (hero), 4-stat grid ("How you're
doing"), risk factors block (what's pulling the score down), an
eligibility CTA (no active loan) **or** an outstanding-balance card +
repayment history (active loan).

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/me/credit` | Protected |
| `GET` | `/me/loans/active` | Protected |

`GET /me` (16) covers the basic stats grid (`jobs_completed`,
`reliability_score`, `total_earned`, `joined_at`). Don't duplicate.

---

## ⚠️ Scoring overhaul — strict + AI-driven

The v1 scoring (rule-based ceilings keyed off `worker.credit_score`)
is **out**. Replace with a server-side ML model that re-evaluates
after every clock-out, every repayment, and on a daily idle batch.

### Inputs the model must consume

| Signal | Source | Notes |
|--------|--------|-------|
| `jobs_completed` | applications table | Same int as on `worker` |
| `on_time_rate` | session.clock_in_at vs job.start_time | 0.0–1.0. Counts a clock-in within 5 minutes of `start_time` as on-time. |
| `completion_rate` | sessions where `status=completed` ÷ total clock-ins | 0.0–1.0. Catches abandoned shifts. |
| `average_rating` | employer ratings | 0.0–5.0 |
| `tenure_days` | now − `worker.joined_at` | Days |
| `wallet_health` | composite of withdrawal frequency, idle balance variance, age of wallet | 0.0–1.0. Penalises workers who drain wallets to ₦0 the moment money lands. |
| `prior_loans_repaid` | loans where `status=repaid` | int |
| `prior_loans_defaulted` | loans where `status` enters a 30-day-overdue state | int. **Heavily** weights against re-borrowing. |
| `recent_no_shows` | accepted applications without a clock-in within 24h of `start_time` | rolling 30-day count |

### Output thresholds (strict)

| Score | Tier | Eligible? | Max principal |
|-------|------|-----------|---------------|
| < 60  | `building`  | ❌ no | — |
| 60–69 | `fair`      | ❌ no | — |
| 70–84 | `good`      | ✅ yes | ₦20k → ₦50k (linear in score) |
| 85+   | `excellent` | ✅ yes | ₦100k+ (linear up to ₦250k cap at score 100) |

The eligibility floor moved from **60 (v1)** to **70 (v2)** — this
is intentional. v1 let too many workers borrow before they had
enough behavioural signal to be priced correctly. With the AI
scorer the floor goes up; the per-tier ceilings get tighter.

A single recent default drops the worker to `building` regardless of
other signals. A single no-show in the last 7 days caps the score at
69 (just below eligibility) for 30 days.

### Recommended model

A lightweight gradient-boosted model (XGBoost or LightGBM) trained
on the full applications + sessions + transactions tables. Output a
probability-of-default in (0,1) → score = `100 * (1 - pd)`. Retrain
weekly off the previous month's outcomes.

For the demo / hackathon: ship a transparent rule-based scorer that
mirrors the structure (so the mobile fields populate correctly),
with clear comments marking the swap-out point for the ML model.
The mobile contract is identical either way.

---

## `GET /me/credit`

### Response 200 (full AI-scored shape)

```json
{
  "credit_score": 76,
  "tier": "good",
  "subtitle": "Good — keep working to qualify for higher amounts.",
  "eligibility": {
    "is_eligible": true,
    "max_principal": 50000,
    "min_principal": 5000,
    "interest_rate_percent": 5.0,
    "repayment_percent_per_job_default": 0.20
  },
  "next_unlock": {
    "score_target": 85,
    "max_principal_at_target": 100000,
    "jobs_to_unlock_estimate": 4
  },
  "signals": {
    "jobs_completed": 47,
    "on_time_rate": 0.92,
    "completion_rate": 0.98,
    "average_rating": 4.7,
    "tenure_days": 134,
    "wallet_health": 0.71,
    "prior_loans_repaid": 1,
    "prior_loans_defaulted": 0
  },
  "risk_factors": [
    {
      "code": "wallet_drain",
      "severity": "medium",
      "copy": "You withdraw within minutes of getting paid — keeping a small reserve helps your score.",
      "score_impact": -4
    },
    {
      "code": "low_tenure",
      "severity": "low",
      "copy": "You're new to Forge. Score climbs naturally over your first 90 days.",
      "score_impact": -3
    }
  ],
  "improvement_actions": [
    {
      "code": "complete_one_more_on_time_job",
      "copy": "Complete one more on-time job to lift your score by ~3 points.",
      "score_lift": 3,
      "deeplink": "forge://jobs"
    },
    {
      "code": "keep_wallet_above_5k_for_7_days",
      "copy": "Keep ₦5,000+ in your wallet for 7 days to lift your score by ~5 points.",
      "score_lift": 5,
      "deeplink": null
    }
  ],
  "last_evaluated_at": "2026-05-09T19:08:30Z",
  "model_version": "credit-v2.3"
}
```

### Field reference

#### Top level

| Field | Type | Notes |
|-------|------|-------|
| `credit_score` | int | 0–100. Strict tiers below. |
| `tier` | enum | `building` (<60), `fair` (60–69), `good` (70–84), `excellent` (85+). |
| `subtitle` | string | Server-rendered status line under the gauge. ≤ 80 chars. Locale-aware. |
| `eligibility` | object | See below. |
| `next_unlock` | object \| null | Carrot for sub-eligible / sub-excellent workers. `null` when `tier = excellent`. |
| `signals` | object \| null | The model's input snapshot. **Optional** — older clients may not show it, but emit when available so the UI can render the "your stats" block. |
| `risk_factors` | array | Newest first, capped at 3 server-side. |
| `improvement_actions` | array | Highest-impact first, capped at 3 server-side. |
| `last_evaluated_at` | ISO 8601 \| null | UI shows "Updated 5 minutes ago". |
| `model_version` | string \| null | Trace field for ops/A-B testing. |

#### `eligibility` (unchanged shape, stricter values)

| Field | Type | Notes |
|-------|------|-------|
| `is_eligible` | bool | True when `credit_score >= 70` (v2 floor). |
| `max_principal` | int | ₦. Server table; mobile must accept any ceiling — never hard-code. |
| `min_principal` | int | Floor for the slider in apply. Recommend ₦5k. |
| `interest_rate_percent` | double | Rate quoted on `/loans/apply`. Recommend tier-keyed: good=5.0%, excellent=4.0%. |
| `repayment_percent_per_job_default` | double | 0.0–1.0. Defaults the slider in apply. Recommend 0.20. |

#### `signals` — model inputs

| Field | Type | Notes |
|-------|------|-------|
| `jobs_completed` | int | |
| `on_time_rate` | double | 0.0–1.0. % of accepted jobs with clock-in within 5min of `start_time`. |
| `completion_rate` | double | 0.0–1.0. % of clock-ins that ended in successful clock-out. |
| `average_rating` | double | 0.0–5.0. |
| `tenure_days` | int | Since `joined_at`. |
| `wallet_health` | double | 0.0–1.0. Composite — see input table above. |
| `prior_loans_repaid` | int | |
| `prior_loans_defaulted` | int | |

The mobile renders these as a four-stat row: jobs, on-time %,
completion %, rating. The other inputs (tenure, wallet_health,
prior loans) feed risk factors / actions, not direct UI rows.

#### `risk_factors[]`

| Field | Type | Notes |
|-------|------|-------|
| `code` | string (enum-ish) | Stable handle the mobile branches on. See enum below. |
| `severity` | enum | `low` \| `medium` \| `high`. UI tints the row. |
| `copy` | string | Locale-aware, server-rendered. **Render verbatim**. |
| `score_impact` | int \| null | Negative — points the model removed for this factor. UI shows e.g. "−6" next to the row. |

Recommended `code` values (extensible — mobile falls back to a
generic icon when it sees an unknown one):
`low_on_time_rate`, `recent_no_show`, `low_completion_rate`,
`wallet_drain`, `prior_default`, `low_tenure`, `recent_rating_drop`,
`recent_loan_late_repayment`.

#### `improvement_actions[]`

| Field | Type | Notes |
|-------|------|-------|
| `code` | string | Stable handle. |
| `copy` | string | Server-rendered call to action. Verbatim. |
| `score_lift` | int \| null | Estimated points gained on completion. UI shows e.g. "+3". |
| `deeplink` | string \| null | `forge://jobs` etc. UI makes the row tappable when present. |

Recommended `code` values:
`complete_one_more_job`, `complete_one_more_on_time_job`,
`improve_completion_rate`, `keep_wallet_above_X_for_N_days`,
`maintain_rating_above_4`, `repay_existing_loan`.

### Errors

Standard auth errors only.

### Notes for backend

- This endpoint is the hot path on the loans tab — pull-to-refresh
  hits it every time. Cache the model output for 60s per worker;
  invalidate on clock-out / repayment.
- `subtitle`, `risk_factors[].copy`, and `improvement_actions[].copy`
  are server-rendered so copy can be A/B tested without an app
  release. Keep ≤ 100 chars per copy line.
- **Don't** expose the underlying model weights or feature
  importances. The mobile only needs the score + display copy +
  the input snapshot it's fed.
- Log every evaluation: `worker_id`, `model_version`, raw signals,
  resulting score, top-3 risk factors. Drives ops auditing and
  weekly retrain signal.
- Recompute on these triggers: successful clock-out, successful
  repayment, late-repayment detected, no-show detected, daily idle
  batch.

---

## `GET /me/loans/active`

(Unchanged from v1.) Returns the worker's active loan, or `null`.

### Response 200 (no active loan)

```json
{ "loan": null }
```

### Response 200 (active loan)

```json
{
  "loan": {
    "id": "loan_3c8a2f",
    "principal": 50000,
    "outstanding_balance": 32000,
    "interest_rate_percent": 5.0,
    "repayment_percent_per_job": 0.20,
    "disbursed_at": "2026-04-10T12:30:00Z",
    "status": "active",
    "next_repayment_estimate": 1000,
    "next_repayment_when": "On your next job",
    "repayments_count": 18,
    "repayments_total": 18000
  }
}
```

(Field reference — same as before; see prior versions of this doc.)

---

## What the backend dev needs to do

Concrete delta off the v1 implementation:

1. **Build / wire the credit-score evaluator.** Either an
   XGBoost/LightGBM service the API calls server-side, or a transparent
   rule-based scorer with the same output contract for v0/demo.
2. **Add the new response fields** to `GET /me/credit`:
   - `signals: {...}` — the model input snapshot.
   - `risk_factors: [{code, severity, copy, score_impact}, ...]` —
     server-rendered, capped at 3.
   - `improvement_actions: [{code, copy, score_lift, deeplink}, ...]` —
     server-rendered, capped at 3.
   - `last_evaluated_at`, `model_version` — trace fields.
3. **Tighten the tier cutoffs** — eligibility floor goes from
   `credit_score >= 60` to `credit_score >= 70`. Per-tier max-principal
   values stay configurable via the existing internal table; just
   shift the entry points up.
4. **Add the recompute triggers**: every clock-out, every repayment,
   and a daily idle batch.
5. **Cache** the response for 60s per worker; invalidate on the
   recompute triggers.

Mobile is already wired against this shape — no further mobile work
once the backend ships.
