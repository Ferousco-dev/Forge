# Transaction Detail

Covers `lib/features/earnings/presentation/transaction_detail_screen.dart`.

Single transaction with full context: receipt, source job (if applicable), Squad reference, deeplink to the related job.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/transactions/:id` | Protected |

---

## `GET /transactions/:id`

### Path params

| Param | Type | Notes |
|-------|------|-------|
| `id` | string | Transaction id |

### Response 200

Same fields as the list shape (see `09_transactions.md`), plus:

```json
{
  "id": "txn_e7290b",
  "kind": "job_payment",
  "amount": 5000,
  "timestamp": "2026-05-09T19:08:12Z",
  "title": "Adeolu Iron Wholesale",
  "subtitle": "Loading job · Owode-Onirin",
  "squad_reference": "sqd_8a3f2c1d",
  "related_job_id": "job_a3f81c",
  "related_job_summary": {
    "id": "job_a3f81c",
    "type": "loader",
    "title": "Load 5 tons of rebar",
    "location_address": "Owode-Onirin Iron Market, Lagos",
    "duration_hours": 4,
    "completed_at": "2026-05-09T19:08:00Z"
  },
  "bank_account_summary": {
    "bank_name": "GTBank",
    "account_number_last4": "5678"
  }
}
```

### Extra fields

| Field | Type | When | Notes |
|-------|------|------|-------|
| `related_job_summary` | object \| null | `kind=job_payment` or `loan_repayment` with a `related_job_id` | Slim job for the receipt block. Mobile uses this to render "Job: Load 5 tons of rebar · Owode-Onirin". |
| `bank_account_summary` | object \| null | `kind=withdrawal` | Where the withdrawal landed. Last 4 digits only — never the full PAN. |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Bad id or not the worker's transaction |

### Notes for backend

- Don't return `account_number` in full anywhere. Always last4.
- `related_job_summary` saves a round-trip — the detail screen always needs it.
