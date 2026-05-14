# Auth — Login, Signup, OTP, Profile Setup

Covers screens:
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/signup_screen.dart`
- `lib/features/auth/presentation/otp_screen.dart`
- `lib/features/auth/presentation/profile_setup_screen.dart`

## Flow

```
Login:                Signup:
  phone                 phone
    ↓                     ↓
  request OTP           request OTP
    ↓                     ↓
  enter OTP             enter OTP
    ↓                     ↓
  tokens + worker       tokens + (worker = null)
                          ↓
                        complete profile
                          ↓
                        worker created
```

The same OTP endpoint is used for both flows; the mobile sends a `flow` discriminator so the server can issue the right response (login returns the existing worker; signup returns `null` and expects a profile-setup call).

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `POST` | `/auth/otp/request` | Public | — |
| `POST` | `/auth/otp/verify` | Public | — |
| `POST` | `/auth/profile-setup` | Protected | ⚡ |
| `POST` | `/auth/refresh` | Public (uses refresh token in body) | — |
| `POST` | `/auth/logout` | Protected | — |

---

## `POST /auth/otp/request`

Send a one-time code via SMS to the supplied phone number.

### Request

```json
{
  "phone": "+2348012345678",
  "flow": "login"        // "login" | "signup"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `phone` | string | yes | E.164 |
| `flow` | enum | yes | Determines what `verify` does next. On `login` the phone must already exist; on `signup` it must not. |

### Response 200

```json
{
  "challenge_id": "chl_8a3f2c1d",
  "expires_at": "2026-05-09T14:35:00Z",
  "resend_after_seconds": 30
}
```

| Field | Type | Notes |
|-------|------|-------|
| `challenge_id` | string | Opaque. Echoed back in `verify`. |
| `expires_at` | ISO 8601 | OTP becomes invalid after this. UI shows a countdown. |
| `resend_after_seconds` | int | Server-enforced cooldown for `request` retries. |

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Phone not E.164 |
| 404 | `PHONE_NOT_FOUND` | `flow=login` but phone has no account |
| 409 | `PHONE_ALREADY_EXISTS` | `flow=signup` but phone is registered |
| 429 | `RATE_LIMITED` | More than 3 OTP requests / phone / 15 min |

### Notes for backend

- OTP is 6 digits. Don't include it in the response — only deliver via SMS.
- In dev/staging, expose a debug endpoint `GET /auth/otp/debug/:challenge_id` that returns the code (gated by an env flag).
- SMS provider TBD (Termii / Twilio). Sender ID `FORGE`.

---

## `POST /auth/otp/verify`

Exchange a challenge + code for a token pair.

### Request

```json
{
  "challenge_id": "chl_8a3f2c1d",
  "code": "482301"
}
```

### Response 200 (login)

```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "access_expires_at": "2026-05-09T14:50:00Z",
  "refresh_expires_at": "2026-06-08T14:35:00Z",
  "worker": { /* see 16_profile.md `Worker` shape */ },
  "needs_profile_setup": false
}
```

### Response 200 (signup)

```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "access_expires_at": "2026-05-09T14:50:00Z",
  "refresh_expires_at": "2026-06-08T14:35:00Z",
  "worker": null,
  "needs_profile_setup": true
}
```

When `needs_profile_setup: true`, the mobile routes to `/auth/profile-setup` next. The token pair is **already valid** — `POST /auth/profile-setup` is a protected call.

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Code not 6 digits |
| 404 | `CHALLENGE_NOT_FOUND` | Bad `challenge_id` |
| 410 | `CHALLENGE_EXPIRED` | `expires_at` passed |
| 422 | `CODE_INCORRECT` | Wrong digits. Returns `attempts_remaining` in `details`. |
| 429 | `TOO_MANY_ATTEMPTS` | More than 5 wrong codes per challenge |

---

## `POST /auth/profile-setup` ⚡

Complete signup by setting a name, primary skill, optional photo, and preferred work radius. Called once after signup OTP verify.

### Request

```json
{
  "name": "Tunde Adeyemi",
  "primary_skill": "Loader",
  "preferred_radius_km": 8.0,
  "photo_upload_id": "upl_a3f81c"   // optional, from 22_uploads.md
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `name` | string | yes | 2–60 chars, trimmed |
| `primary_skill` | enum | yes | One of: `Loader`, `Driver`, `Unloader`, `General Labor`, `Welder`. Mirrors `JobType.label` in the mobile model. |
| `preferred_radius_km` | double | yes | 1.0–25.0 |
| `photo_upload_id` | string | no | Reference to a previously uploaded photo (see 22) |

### Response 200

Returns the now-complete worker. Same shape as `16_profile.md`.

```json
{
  "worker": { /* Worker */ }
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Any field invalid |
| 409 | `ALREADY_SET_UP` | Worker already exists for this account |
| 422 | `UPLOAD_NOT_FOUND` | `photo_upload_id` doesn't resolve |

### Notes for backend

- Idempotency key required. A retry must return the existing worker, not 409.
- After this call, the `worker` row exists and all worker-scoped data is queryable.

---

## `POST /auth/refresh`

Exchange a refresh token for a new pair. Single-use refresh — server invalidates the old token immediately.

### Request

```json
{
  "refresh_token": "eyJhbGc..."
}
```

### Response 200

```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "access_expires_at": "2026-05-09T15:05:00Z",
  "refresh_expires_at": "2026-06-08T14:50:00Z"
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 401 | `TOKEN_INVALID` | Bad signature, malformed, or already used |
| 401 | `TOKEN_EXPIRED` | Refresh expired — user must re-login |

### Notes for backend

- Mobile calls this opportunistically when an access token has < 60s left, and reactively when any 401 with `TOKEN_EXPIRED` is received.
- On `TOKEN_INVALID` the mobile clears local tokens and routes to login.

---

## `POST /auth/logout`

Invalidate the current refresh token (server-side blocklist).

### Request

```json
{
  "refresh_token": "eyJhbGc..."
}
```

### Response 204

Empty body.

### Errors

Logout is best-effort. If the request fails, mobile still clears local state and routes to login. So 4xx/5xx are logged but never surfaced.

### Notes for backend

- The access token is short-lived; no need to revoke. Just blocklist the refresh.
- Future: revoke all refresh tokens for the user when they tap "Sign out of all devices" in settings.

---

## Local-only state (mobile, no endpoint)

These do **not** hit the backend:

- **Onboarding seen** — `lib/features/auth/state/onboarding_state.dart`. Boolean in secure storage.
- **Theme mode** — `lib/features/profile/state/settings_state.dart`. Light / Dark / System.

These never need server persistence — they're per-install preferences.
