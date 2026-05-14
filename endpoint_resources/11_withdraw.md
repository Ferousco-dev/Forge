# Withdraw

Covers `lib/features/earnings/presentation/withdraw_screen.dart`.

User picks an amount and a destination bank, confirms, server initiates a Squad transfer.

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `GET`  | `/wallet/withdrawals/preview` | Protected | — |
| `POST` | `/wallet/withdrawals` | Protected | ⚡ |

---

## `GET /wallet/withdrawals/preview`

Computes fees, ETA, and the destination given an amount + bank. Used to populate the confirmation row before the user taps "Withdraw".

### Query parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `amount` | int | yes | Whole Naira |
| `bank_account_id` | string | yes | From `12_bank_accounts.md` |

### Response 200

```json
{
  "amount": 10000,
  "fee": 50,
  "amount_credited": 9950,
  "estimated_arrival": "in 5 minutes",
  "estimated_arrival_at": "2026-05-09T19:13:00Z",
  "destination": {
    "bank_name": "GTBank",
    "account_number_last4": "5678",
    "account_name": "TUNDE ADEYEMI"
  }
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | `amount <= 0` or above `wallet_balance` |
| 422 | `BELOW_MINIMUM` | Amount < ₦500 (Squad's NIP minimum). `details.minimum: 500`. |
| 422 | `BANK_NOT_FOUND` | `bank_account_id` doesn't belong to this worker |

---

## `POST /wallet/withdrawals` ⚡

### Request

```json
{
  "amount": 10000,
  "bank_account_id": "bnk_b2c8e1"
}
```

### Response 201

```json
{
  "transaction": {
    "id": "txn_a1f2c8",
    "kind": "withdrawal",
    "amount": -10000,
    "timestamp": "2026-05-09T19:08:30Z",
    "title": "Withdrawal to GTBank ****5678",
    "subtitle": "Estimated arrival in 5 min",
    "squad_reference": "sqd_w4f2e9a1",
    "related_job_id": null
  },
  "wallet_balance_after": 12500
}
```

The mobile uses `wallet_balance_after` to instantly update the wallet hero without waiting for `GET /me` to re-fetch.

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Amount invalid |
| 422 | `INSUFFICIENT_BALANCE` | Balance changed between preview and submit |
| 422 | `BELOW_MINIMUM` | Same as preview |
| 502 | `PAYMENT_PROVIDER_UNAVAILABLE` | Squad down — mobile retries with the same idempotency key |

### Notes for backend

- Idempotency is non-negotiable. A retried POST must return the **same transaction**, not a new one.
- Deduct the wallet balance **before** calling Squad; refund on Squad failure. Otherwise a slow Squad call lets the user double-spend.
- Withdrawal is asynchronous — the transaction is created in `pending` Squad state, then flipped to `succeeded` when Squad's webhook lands. The `txn` row exists immediately so mobile sees the debit.
- The transaction's `subtitle` is generated server-side ("Estimated arrival in 5 min"). On webhook success it flips to "Arrived at {bank}".
