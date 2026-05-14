# Notifications — In-app Feed

Covers `lib/features/profile/presentation/notifications_screen.dart`. The bell-icon feed of in-app notifications mirroring delivered pushes.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET`   | `/me/notifications` | Protected |
| `POST`  | `/me/notifications/:id/read` | Protected |
| `POST`  | `/me/notifications/read-all` | Protected |

---

## `GET /me/notifications`

### Query parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `cursor` | string | no | — | Pagination |
| `limit` | int | no | 30 | Max 100 |

### Response 200

```json
{
  "items": [
    {
      "id": "ntf_8a3f2c",
      "kind": "payment",
      "title": "₦5,000 arrived in your wallet",
      "body": "Loading job at Owode-Onirin · 4h",
      "timestamp": "2026-05-09T19:08:30Z",
      "unread": true,
      "deeplink": "forge://transactions/txn_e7290b"
    }
  ],
  "next_cursor": "eyJ0cyI6...",
  "has_more": false,
  "unread_count": 3
}
```

### Field shape (`AppNotification`)

Mirrors `lib/core/mock/models.dart`, with one extra:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `ntf_xxx` |
| `kind` | enum | `new_job` \| `application_update` \| `payment` \| `loan` \| `system` |
| `title` | string | One-line. ≤ 60 chars. |
| `body` | string | Two-line max. ≤ 160 chars. |
| `timestamp` | ISO 8601 | When created |
| `unread` | bool | |
| `deeplink` | string \| null | Custom-scheme URL. Tapping the row navigates the mobile to it. See "Deeplink scheme" below. |

### Deeplink scheme

Mirrors the `RoutePaths` constants in `lib/app/router/route_paths.dart`. Stable contract:

| Notification kind | Deeplink |
|-------------------|----------|
| `new_job` | `forge://jobs/:id` |
| `application_update` (accepted) | `forge://jobs/:job_id/clock-in` |
| `application_update` (rejected) | `forge://jobs/:job_id/status` |
| `payment` | `forge://transactions/:id` |
| `loan` (approved) | `forge://loans/approved` |
| `loan` (rejected) | `forge://loans/rejected` |
| `loan` (active reminder) | `forge://loans/:id` |
| `system` | `null` (no nav, just an info banner) |

Server constructs these. Mobile parses and routes.

### Notes for backend

- `unread_count` is the global unread total, NOT just on this page. UI uses it for the bell badge.
- When a delete-account 30-day window starts, generate a `system` notification: "Your account is scheduled for deletion in 30 days. Sign in to cancel."

---

## `POST /me/notifications/:id/read`

Marks a single notification as read.

### Response 204

Empty.

### Notes for backend

- Idempotent — flipping already-read to read returns 204 silently.

---

## `POST /me/notifications/read-all`

### Response 204

Marks every unread notification as read. Used by the "Mark all as read" affordance at the top of the screen.

### Notes for backend

- Should be cheap: a single UPDATE WHERE worker_id = ... AND unread = true. Don't enumerate.
