# Bank Accounts

Covers `lib/features/earnings/presentation/link_bank_screen.dart` plus the Profile → Bank accounts entry that points to the same screen.

Workers can link multiple Nigerian bank accounts. One is marked default — that's the destination for clock-out disbursements unless the worker overrides per-withdrawal.

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `GET`  | `/banks` | Public | — |
| `GET`  | `/me/bank-accounts` | Protected | — |
| `POST` | `/me/bank-accounts/resolve` | Protected | — |
| `POST` | `/me/bank-accounts` | Protected | ⚡ |
| `POST` | `/me/bank-accounts/:id/default` | Protected | — |
| `DELETE` | `/me/bank-accounts/:id` | Protected | — |

---

## `GET /banks`

Static list of supported Nigerian banks. Mobile loads this once at app open (cache for 24h). Used to populate the bank dropdown in the link-bank form.

### Response 200

```json
{
  "items": [
    { "code": "058", "name": "GTBank" },
    { "code": "044", "name": "Access Bank" },
    { "code": "057", "name": "Zenith Bank" }
  ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `code` | string | NIBSS bank code. Squad uses this for transfers. |
| `name` | string | Display name |

### Notes for backend

- Bank codes are stable. Cache aggressively. Set a long `Cache-Control: public, max-age=86400`.
- Public endpoint — workers may not be authenticated yet (e.g. coming from signup).

---

## `GET /me/bank-accounts`

Lists the worker's linked accounts.

### Response 200

```json
{
  "items": [
    {
      "id": "bnk_b2c8e1",
      "bank_name": "GTBank",
      "bank_code": "058",
      "account_number": "0123456789",
      "account_name": "TUNDE ADEYEMI",
      "is_default": true,
      "created_at": "2026-05-01T10:30:00Z"
    }
  ]
}
```

### Field shape (`BankAccount`)

Mirrors `lib/core/mock/models.dart` `BankAccount`. The mobile receives the **full `account_number`** here because this is the worker's own account — display masking is a UI choice (mobile shows `****6789`), not a server policy.

For *other people's* accounts (e.g. transaction detail), use last4 only.

---

## `POST /me/bank-accounts/resolve`

Validates a bank + account number against NIBSS, returns the official account name. Used to populate the read-only "Account name" field in the link-bank form *before* the user submits — confirms they typed the number right.

### Request

```json
{
  "bank_code": "058",
  "account_number": "0123456789"
}
```

### Response 200

```json
{
  "account_name": "TUNDE ADEYEMI"
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Account number not 10 digits |
| 404 | `ACCOUNT_NOT_FOUND` | NIBSS lookup returned nothing |
| 502 | `PROVIDER_UNAVAILABLE` | NIBSS / Squad down |

### Notes for backend

- Rate-limit: 10 calls / minute per worker. Workers shouldn't be hammering NIBSS.
- Cache (bank_code, account_number) → name for 1 hour. NIBSS responses don't change.

---

## `POST /me/bank-accounts` ⚡

Links the verified account.

### Request

```json
{
  "bank_code": "058",
  "account_number": "0123456789",
  "account_name": "TUNDE ADEYEMI",
  "set_as_default": true
}
```

`account_name` is what the resolve endpoint returned. Server should **re-resolve** and reject if it doesn't match — never trust the client's copy.

### Response 201

The new `BankAccount` object (same shape as the list).

### Errors

| HTTP | Code | When |
|------|------|------|
| 409 | `ALREADY_LINKED` | Same (bank_code, account_number) already on this worker |
| 422 | `NAME_MISMATCH` | Re-resolve returned a different name |
| 422 | `NAME_DOES_NOT_MATCH_PROFILE` | Server compares account name to `worker.name` and rejects if they're not a fuzzy match (handles "TUNDE ADEYEMI" vs "Tunde A. Adeyemi"). Reduces fraud. |

---

## `POST /me/bank-accounts/:id/default`

Promote an account to default. Demotes the previous default automatically.

### Response 200

The updated list (same shape as `GET /me/bank-accounts`).

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | id doesn't belong to worker |

---

## `DELETE /me/bank-accounts/:id`

### Response 204

Empty body.

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | id doesn't belong to worker |
| 409 | `CANNOT_REMOVE_DEFAULT` | Can't delete the default while other accounts exist. Promote one first. |
| 409 | `CANNOT_REMOVE_LAST_ACCOUNT` | Worker has an active loan; needs at least one bank for repayment routing. |
