# Transactions — Full Ledger

Covers:
- Earnings home preview (top 10) — `lib/features/earnings/presentation/earnings_screen.dart`.
- All-transactions page — `lib/features/earnings/presentation/transactions_screen.dart`.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/transactions` | Protected |

---

## `GET /transactions`

Returns the worker's full transaction ledger, newest first.

### Query parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `kinds` | csv of enum | no | all | Filter by kind (see below) |
| `cursor` | string | no | — | Pagination |
| `limit` | int | no | 20 | Max 100 |

### Response 200

```json
{
  "items": [
    {
      "id": "txn_e7290b",
      "kind": "job_payment",
      "amount": 5000,
      "timestamp": "2026-05-09T19:08:12Z",
      "title": "Adeolu Iron Wholesale",
      "subtitle": "Loading job · Owode-Onirin",
      "squad_reference": "sqd_8a3f2c1d",
      "related_job_id": "job_a3f81c"
    },
    {
      "id": "txn_e7290c",
      "kind": "loan_repayment",
      "amount": -1000,
      "timestamp": "2026-05-09T19:08:12Z",
      "title": "Loan repayment",
      "subtitle": "Auto-deducted from job payment",
      "squad_reference": "sqd_8a3f2c1e",
      "related_job_id": null
    }
  ],
  "next_cursor": "eyJ0cyI6...",
  "has_more": true
}
```

### Field shape (`Transaction`)

Mirrors `lib/core/mock/models.dart` `Transaction`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `txn_xxx` |
| `kind` | enum | See enum below |
| `amount` | int | **Signed**. Positive = credit (job pay, loan disbursed). Negative = debit (loan repayment, withdrawal). |
| `timestamp` | ISO 8601 | When the money moved |
| `title` | string | One-line label. For job payments: the employer's name. For repayments: "Loan repayment". |
| `subtitle` | string | Context line under the title |
| `squad_reference` | string \| null | Squad's transfer reference for support tickets. Null only for non-money internal transactions (none today, future-proofing). |
| `related_job_id` | string \| null | Set only for `job_payment` and the `loan_repayment` that auto-deducts from one |

### Kind enum

| Wire | Display | Sign |
|------|---------|------|
| `job_payment` | Job payment | + |
| `loan_disbursement` | Loan disbursed | + |
| `loan_repayment` | Loan repayment | − |
| `withdrawal` | Withdrawal | − |

### Errors

Nothing screen-specific — standard auth errors only.

### Notes for backend

- Sort `timestamp DESC, id DESC` (id is a tie-breaker so two transactions with identical timestamps don't flip on re-pagination).
- A single Squad disbursement can produce two ledger rows: one `job_payment` credit and one `loan_repayment` debit (when the worker has an active loan and `repayment_percent_per_job` is configured). They MUST share the same `timestamp`. The mobile renders them as adjacent rows.
- Don't include cancelled / failed transactions. Only successful ones.
- Cap server-side at 1000 transactions per call, even if `limit` exceeds. Anyone needing more should paginate.
