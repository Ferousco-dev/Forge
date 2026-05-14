# Loan Detail

Covers `lib/features/loans/presentation/loan_detail_screen.dart`. Reached from "View details" on the active-loan card.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/loans/:id` | Protected |

---

## `GET /loans/:id`

### Path params

| Param | Type | Notes |
|-------|------|-------|
| `id` | string | Loan id (`loan_3c8a2f`) |

### Response 200

```json
{
  "id": "loan_3c8a2f",
  "principal": 50000,
  "outstanding_balance": 32000,
  "interest_rate_percent": 5.0,
  "repayment_percent_per_job": 0.20,
  "disbursed_at": "2026-04-10T12:30:00Z",
  "status": "active",
  "purpose": "stock_purchase",
  "expected_full_repayment_at": "2026-07-15T00:00:00Z",
  "repayments": [
    {
      "id": "rep_a8c2f1",
      "amount": 1000,
      "paid_at": "2026-05-09T19:08:12Z",
      "from_job_id": "job_a3f81c",
      "from_job_title": "Load 5 tons of rebar",
      "transaction_id": "txn_e7290c"
    }
  ]
}
```

### Field shape (`Loan` extended)

Same fields as the loans-home active loan (see `13_loans_home.md`), plus:

| Field | Type | Notes |
|-------|------|-------|
| `expected_full_repayment_at` | ISO 8601 \| null | Server's projection based on the worker's average jobs/week × repayment_percent_per_job. `null` if not enough data. |
| `repayments` | array of `LoanRepayment` | Newest first |

### `LoanRepayment` shape

Mirrors `lib/core/mock/models.dart`, with extras:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `rep_xxx` |
| `amount` | int | ₦. Positive — sign is handled by the parent transaction. |
| `paid_at` | ISO 8601 | When the deduction landed |
| `from_job_id` | string | The job whose pay this came out of |
| `from_job_title` | string | Slim title for the row label |
| `transaction_id` | string | Links to the parallel `loan_repayment` transaction in `09_transactions.md` |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Bad id or not the worker's loan |

### Notes for backend

- `repayments` can grow large for long-running loans. Inline up to 50 in this response; expose `GET /loans/:id/repayments` (paginated, same shape) if more are needed (Phase H — not required for v1).
- A row in `repayments` always has a sibling row in the transaction ledger with `kind=loan_repayment`. Keep them in sync; one is the "loan view" and the other is the "wallet view" of the same money movement.
