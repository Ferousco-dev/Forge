# Profile — Read Worker

Covers `lib/features/profile/presentation/profile_screen.dart` (the hub) and supplies the Worker shape that several other endpoints embed.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/me` | Protected |

---

## `GET /me`

Returns the full worker record. This is the canonical Worker shape — every other endpoint that embeds a worker uses this exact subset.

### Response 200

```json
{
  "worker": {
    "id": "wkr_a3f81c",
    "name": "Tunde Adeyemi",
    "phone_number": "+2348012345678",
    "photo_url": "https://cdn.forge.app/worker/wkr_a3f81c.jpg",
    "primary_skill": "Loader",
    "preferred_radius_km": 8.0,
    "wallet_balance": 22500,
    "total_earned": 540000,
    "jobs_completed": 47,
    "reliability_score": 96,
    "average_rating": 4.7,
    "credit_score": 76,
    "joined_at": "2025-08-01T00:00:00Z"
  }
}
```

### Field shape (`Worker`)

Mirrors `lib/core/mock/models.dart` `Worker`. Server keys are snake_case; mobile maps to camelCase at the boundary.

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `wkr_xxx` |
| `name` | string | 2–60 chars |
| `phone_number` | string | E.164 |
| `photo_url` | string \| null | Public CDN URL. Null = use the initial-fallback. |
| `primary_skill` | enum | `Loader` \| `Driver` \| `Unloader` \| `General Labor` \| `Welder` |
| `preferred_radius_km` | double | 1.0–25.0 |
| `wallet_balance` | int | ₦. Live — reflects every clock-out and withdrawal. |
| `total_earned` | int | ₦. Cumulative gross earnings. Never decreases. |
| `jobs_completed` | int | Count of `completed` applications |
| `reliability_score` | int | 0–100. Server-computed (% of accepted jobs that the worker actually clocked in to + completed). |
| `average_rating` | double | 0.0–5.0, one decimal |
| `credit_score` | int | 0–100. Same value as `13_loans_home.md` `credit_score`. Returned here for the loans-home stats grid; sourcing from `/me` saves a round trip. |
| `joined_at` | ISO 8601 | Account creation. Drives the "Member since {Month YYYY}" footer in profile. |

### Errors

Standard auth errors only.

### Notes for backend

- This endpoint is hit on every cold start (after auth) and again on every pull-to-refresh in earnings, profile, and loans. Keep it fast — single row read, no joins. Stats are derived columns updated by triggers, not computed on read.
- `phone_number` is the worker's identifier. It can change via the "Change phone number" flow (see `18_settings.md`) — that flow re-issues OTP and updates this row.
- After `POST /auth/profile-setup` (signup) returns the same shape. Don't return a different model.

## Local-only fields (mobile, no endpoint)

These are *displayed on the profile screen* but never persisted to the backend:

- **App version (`v1.0.0`)** — read from `pubspec.yaml` at build time via `package_info_plus`.
- **Theme mode** — see `01_auth.md` "Local-only state".
