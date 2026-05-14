# Loan Application

Covers:
- `lib/features/loans/presentation/loan_application_screen.dart` — slider + repayment percentage + submit
- `lib/features/loans/presentation/loan_pending_screen.dart` — "Reviewing"
- `lib/features/loans/presentation/loan_approved_screen.dart` — "Funds disbursed"
- `lib/features/loans/presentation/loan_rejected_screen.dart` — "Try again later"

The four screens are different views of the same `loan` resource, branched on `status`.

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `POST` | `/loans` | Protected | ⚡ |

The post-submit screens read from `13_loans_home.md`'s `GET /me/loans/active` (which returns the loan with whatever status it's currently in) plus `15_loan_detail.md`.

---

## `POST /loans` ⚡

### Request

```json
{
  "principal": 50000,
  "repayment_percent_per_job": 0.20,
  "purpose": "stock_purchase"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `principal` | int | yes | Must be in `[eligibility.min_principal, eligibility.max_principal]` from `13_loans_home.md`. Server re-validates — never trust client. |
| `repayment_percent_per_job` | double | yes | 0.10–0.50. Higher = pay back faster, lower = lighter per-job deduction. |
| `purpose` | enum | no | `stock_purchase`, `tools`, `transport`, `family_emergency`, `other`. For underwriting + future analytics. |

### Response 201

```json
{
  "loan": {
    "id": "loan_3c8a2f",
    "principal": 50000,
    "outstanding_balance": 50000,
    "interest_rate_percent": 5.0,
    "repayment_percent_per_job": 0.20,
    "disbursed_at": null,
    "status": "pending",
    "estimated_decision_at": "2026-05-09T14:35:00Z",
    "purpose": "stock_purchase"
  }
}
```

`status` is one of:
- `pending` — typical case for the static-UI flow. Mobile routes to `loan_pending_screen.dart`.
- `approved` — auto-approved (high-tier borrower, instant disbursement). Routes to `loan_approved_screen.dart`. `disbursed_at` is set.
- `rejected` — fails an automated rule (e.g. credit score dropped between eligibility check and submit). Routes to `loan_rejected_screen.dart`. The response also carries a `rejection_reason` field for the UI.

```json
{
  "loan": {
    "id": "loan_3c8a2f",
    "status": "rejected",
    "principal": 50000,
    "rejection_reason": "Reliability dropped below 60% — complete 2 more jobs and try again.",
    ...
  }
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | `principal` out of allowed range, `repayment_percent_per_job` out of bounds |
| 409 | `ACTIVE_LOAN_EXISTS` | Worker already has an `active` or `pending` loan. Returns the existing loan in `details.loan` so mobile routes to the right status screen. |
| 422 | `NOT_ELIGIBLE` | Credit score dropped below threshold since eligibility was fetched |
| 422 | `BANK_ACCOUNT_REQUIRED` | No default bank — the mobile redirects to `12_bank_accounts.md` first |

### Notes for backend

- Idempotency key required. A retried `POST /loans` returns the same loan, never two.
- Auto-approval rule: tier `excellent` + `principal <= ₦50k` → instant approve and disburse via Squad.
- Manual review queue: tier `good` or principal > ₦50k → `pending`. Ops resolves; mobile polls `GET /me/loans/active` every 30s while the pending screen is open.
- Push notification on decision: "Your loan was approved — ₦{principal} on the way" or "Your loan needs another job — try again after one more clock-out."
- Disbursement creates a `loan_disbursement` transaction (see `09_transactions.md`).
