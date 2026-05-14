# Forge — Backend Endpoint Spec

This folder is the contract between the **mobile app** (this repo) and the **backend service** (TBD). One file per screen / feature. Backend dev should be able to read these top-to-bottom and stand up the API without ever opening the Flutter codebase.

The mobile app is built and wired against mock providers in `lib/core/mock/`. When the backend lands, only the provider bodies change — call sites, models, and screens are stable. So the response shapes in this folder are not speculation; they're already what the UI consumes.

## Index

| # | File | Covers |
|---|------|--------|
| 00 | `00_README.md` | Conventions (this file) |
| 01 | `01_auth.md` | Login, signup, OTP, profile setup, refresh, logout |
| 02 | `02_jobs_feed.md` | Nearby jobs list, filters, search |
| 03 | `03_job_detail.md` | Single job fetch |
| 04 | `04_apply_for_job.md` | Submit application |
| 05 | `05_application_status.md` | Read single application |
| 06 | `06_my_applications.md` | Active + history lists |
| 07 | `07_work_session.md` | Clock-in → in-progress → clock-out (full lifecycle) |
| 08 | `08_earnings_home.md` | Wallet balance + stats |
| 09 | `09_transactions.md` | Transactions list (paginated) |
| 10 | `10_transaction_detail.md` | Single transaction |
| 11 | `11_withdraw.md` | Initiate withdrawal to bank |
| 12 | `12_bank_accounts.md` | List, link, set default, remove |
| 13 | `13_loans_home.md` | Credit score, eligibility, active loan |
| 14 | `14_loan_apply.md` | Submit loan application |
| 15 | `15_loan_detail.md` | Single loan + repayment ledger |
| 16 | `16_profile.md` | Read worker profile |
| 17 | `17_edit_profile.md` | Update name / photo / skill / radius |
| 18 | `18_settings.md` | Notification + privacy prefs |
| 19 | `19_notifications.md` | In-app feed, mark read |
| 20 | `20_work_history.md` | Completed-jobs history |
| 21 | `21_help_support.md` | Submit ticket, FAQ |
| 22 | `22_uploads.md` | Photo / file upload (cross-cutting) |
| 23 | `23_liveness.md` | Liveness selfie verification |
| 24 | `24_push_notifications.md` | FCM transport, device registration, payload contract |
| 25 | `25_employer_profile.md` | Employer profile + their jobs (active + history) |
| — | `ai.md` | AI surfaces (summary, search parse, profile extract, liveness sidecar, dispute mediation) |

## Base

- **Base URL**: `https://api.forge.app/v1` (placeholder — backend dev to confirm).
- **API version** lives in the URL prefix. Breaking changes bump the prefix (`/v2`).
- **Content type**: `application/json; charset=utf-8` for both requests and responses, except `22_uploads.md` which is `multipart/form-data`.
- **Encoding**: UTF-8 everywhere.

## Auth

- **Bearer token** on every protected endpoint:
  ```
  Authorization: Bearer <access_token>
  ```
- **Tokens**:
  - `access_token` — short-lived (15 min target). Used in the header above.
  - `refresh_token` — long-lived (30 days), stored in secure storage on device. Exchanged for a new access token via `POST /auth/refresh`.
- **Public endpoints** (no token required) are explicitly called out per file. Default is protected.
- **Token rotation**: refresh issues a new pair every time. The previous refresh token must be invalidated — single-use refresh.

## Field naming (wire format)

- Server JSON uses **`snake_case`** for keys (`first_name`, `created_at`, `is_default`).
- Mobile maps these to Dart `camelCase` at the boundary (existing models in `lib/core/mock/models.dart`).
- IDs are **opaque strings**. Mobile never parses them. Recommend the existing mock pattern: `<entity>_<id>` e.g. `job_a3f81c`, `txn_e7290b`. Use base32/uuid v4 for the suffix; never sequential integers (leaks volume).

## Dates & times

- All timestamps are **ISO 8601 in UTC**:
  ```
  2026-05-09T14:30:00Z
  ```
- The mobile app converts to local time at the display layer.
- **Never** send naive (timezone-less) timestamps.

## Money

- All amounts are **whole Naira (₦)** as **integers**. No kobo. Nigerian B2C apps in this segment don't transact in fractions.
- Mobile renders with `intl`'s NumberFormat (`₦12,345`).
- Loan interest rates are **percentages as `double`** (e.g. `5.0` = 5%).

## Phone numbers

- **E.164** format: `+2348012345678`. Always include the `+` and country code.
- Server validates Nigerian numbers (`+234XXXXXXXXXX` — 13 chars after the `+`).

## Coordinates

- WGS84 decimal degrees, `double` precision.
  ```json
  { "lat": 6.5895, "lng": 3.3719 }
  ```
- Distances in **meters** (`int`).
- Travel times in **minutes** (`int`).

## Pagination

- **Cursor-based** for all list endpoints. Offset pagination is forbidden — drifts when items are added.
- Request: `?cursor=<opaque>&limit=20` (default 20, max 100).
- Response envelope:
  ```json
  {
    "items": [ ... ],
    "next_cursor": "eyJ0cyI6...",
    "has_more": true
  }
  ```
- When `has_more: false`, `next_cursor` is `null`.

## Idempotency

State-changing endpoints that the user might retry (clock-in, clock-out, withdrawal, loan application) **must** accept an `Idempotency-Key` request header. Server stores the key + response for 24h and returns the cached response on retry. Mobile generates a UUID v4 per logical action.

```
Idempotency-Key: 7b5c8d8a-9af2-4c8e-9c2c-1b2d3e4f5a6b
```

Endpoints that require this are flagged ⚡ in their file.

## Errors

Single, consistent envelope. HTTP status carries the category; `code` carries the specifics.

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Phone number must be in E.164 format.",
    "details": {
      "field": "phone",
      "expected_format": "+234XXXXXXXXXX"
    }
  }
}
```

| HTTP | When |
|------|------|
| 400 | `VALIDATION_FAILED`, `MALFORMED_BODY` |
| 401 | `AUTH_REQUIRED`, `TOKEN_EXPIRED`, `TOKEN_INVALID` |
| 403 | `FORBIDDEN` (authenticated but not allowed — e.g. clocking in to someone else's job) |
| 404 | `NOT_FOUND` |
| 409 | `CONFLICT` (idempotency key reused with different body, double-apply, etc.) |
| 422 | `BUSINESS_RULE_VIOLATION` (e.g. clocking in outside the geofence) |
| 429 | `RATE_LIMITED` (include `Retry-After` header in seconds) |
| 500 | `INTERNAL` (no details exposed) |
| 503 | `MAINTENANCE` |

The mobile app surfaces `error.message` directly to the user when it's user-friendly. Codes drive programmatic retry / branching.

## Common headers

| Header | Required on | Purpose |
|--------|-------------|---------|
| `Authorization: Bearer <token>` | Protected endpoints | Auth |
| `Idempotency-Key: <uuid>` | ⚡-flagged endpoints | Safe retry |
| `Accept-Language: en-NG` | All | Future-proofing for Yoruba/Hausa/Igbo (Phase H) |
| `X-App-Version: 1.0.0+1` | All | Backend can serve a deprecation warning when needed |
| `X-Device-Platform: ios \| android` | All | Platform-specific quirks (push tokens, etc.) |

## Conventions in these files

- `Path:` — full HTTP method + path with parameters in `:param` form.
- `Auth:` — Public / Protected.
- `⚡ Idempotent` — requires `Idempotency-Key`.
- Request and response bodies shown as JSON examples with comments where useful.
- "Notes for backend" — anything the spec can't capture (rate limits, side effects, edge cases).

## Out of scope of this folder

- Webhooks for Squad payment confirmations — Squad handles, backend listens.
- Admin endpoints — backend dev defines their own for the dashboard.
