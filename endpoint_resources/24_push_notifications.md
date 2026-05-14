# Push Notifications — FCM Transport

This is the **transport** spec. The in-app feed (`/me/notifications`) is documented in [`19_notifications.md`](19_notifications.md); this file covers what the **server pushes to the device** and how the device proves it can receive.

The contract is intentionally small:

1. The mobile registers a device + push token (`POST /me/devices`).
2. The server fans out push messages via **Firebase Cloud Messaging (FCM)** for both Android and iOS — Apple devices get APNs delivery via FCM's bridge, so the backend only ever talks to one provider.
3. Every push that has a corresponding in-app row also writes that row server-side, so a delivered push and the bell-feed entry stay in lockstep.
4. The mobile shows the push (system shows it in background/terminated; Flutter shows it via local notifications in foreground) and routes on tap via the deeplink in the payload.

---

## Triggers — when the server sends a push

| Trigger | `kind` | Channel (Android) | Sound | Deeplink |
|---------|--------|-------------------|-------|----------|
| Employer **accepts** the worker's application | `application_update` | `forge_payments` | `opay_credit` | `forge://jobs/:job_id/clock-in` |
| Employer **rejects** the worker's application | `application_update` | `forge_default` | default | `forge://jobs/:job_id/status` |
| **New job posted near** the worker (within their `preferred_radius_km`) | `new_job` | `forge_jobs` | default | `forge://jobs/:id` |
| Wallet **credited** (job payment, loan disbursement) | `payment` | `forge_payments` | `opay_credit` | `forge://transactions/:id` |
| Loan decision (approved / rejected / reminder) | `loan` | `forge_default` | default | `forge://loans/...` (see `19_notifications.md`) |
| System (account, security) | `system` | `forge_default` | default | `null` |

**`opay_credit`** is the custom "money-just-arrived" tone. It's a single short sound shared by the two money events (acceptance — work + earnings unlocked, and payment — actual credit). The asset lives at:

- Android: `android/app/src/main/res/raw/opay_credit.mp3` (raw resource — must be lowercase, no extension in the manifest reference)
- iOS: `ios/Runner/opay_credit.caf` (added to the Xcode bundle resources; APNs requires `.caf`/`.aiff`/`.wav`)

Both files are bundled into the app at build time. The server only sends the **name** (`opay_credit` on Android, `opay_credit.caf` on iOS) — the actual audio is shipped with the app.

### "Near you" — geofencing rule

The server is the source of truth for "near":

- Worker's last known location comes from the most recent `GET /jobs?lat=...&lng=...` query the device made (the API client logs the lat/lng of every request).
- Radius is the worker's `preferred_radius_km` from `/me` (default 10 km, settable in profile).
- On every job creation, the backend runs a `ST_DWithin` (or equivalent) query and enqueues a push job for each matched worker whose `notifications.new_job_alerts` preference is `true`.
- Rate-limit: at most **5 `new_job` pushes per worker per hour** (server-side throttle). Excess matches still create in-app feed rows but don't ring the device — prevents notification fatigue in dense markets.

---

## `POST /me/devices`

Already specified in [`18_settings.md`](18_settings.md); summarised here for completeness.

The mobile calls this:

- Right after the worker grants notification permission (signup permission screen).
- Whenever FCM rotates the token (`onTokenRefresh`).
- On every cold start, **only if** the cached token differs from FCM's current token (so we don't hammer the endpoint every launch).

### Request

```json
{
  "platform": "android",
  "push_token": "fcm_eR3...long-base64-string...",
  "device_id": "dvc_8a3f2c1d",
  "app_version": "1.0.0+1"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `platform` | enum | yes | `ios` \| `android` |
| `push_token` | string | yes | FCM registration token. For iOS this is the **FCM token**, not the raw APNs token — FCM gives us one bridged identifier. |
| `device_id` | string | yes | Persistent UUID, generated on first launch and stored in `flutter_secure_storage`. Survives app reinstall on iOS (Keychain), regenerates on Android reinstall (encrypted shared prefs). |
| `app_version` | string | yes | `pubspec.yaml` version + build number. Lets the backend gate features per-version. |

### Response 204

Empty.

### Notes for backend

- UPSERT on `(worker_id, device_id)`. A worker can have multiple active devices — push to all of them.
- A given `push_token` is unique per `(device_id, app install)`. If FCM returns `NotRegistered` or `InvalidRegistration` on a send attempt, prune the row in the **send job** — never trust the mobile to clean up tokens.
- If the same `push_token` shows up under a different `worker_id` (worker A signed out, worker B signed in on the same phone), revoke the old binding and attach to the new worker. This is the normal device-handoff path.

---

## `DELETE /me/devices/:device_id`

Called from the mobile during the logout flow, **before** the access token is cleared, so the row is removed cleanly.

### Response 204

Empty. Idempotent — deleting an already-deleted row returns 204.

### Notes for backend

- Don't 404 on missing rows. The mobile calls this best-effort and shouldn't have to check first.
- This is a **soft cleanup**, not the canonical pruning path. The send job's `NotRegistered` handling is the real garbage collector — this endpoint just keeps the count tidy when the user explicitly signs out.

---

## FCM message payload (server → device)

The backend MUST send a single FCM message that contains **both** a `notification` object (so the system tray draws the message in background/terminated) **and** a `data` object (so the mobile can route on tap and refresh the in-app feed).

`data` values are always strings in FCM — keep that in mind.

### Canonical shape (HTTP v1 API)

```json
{
  "message": {
    "token": "<device push_token>",

    "notification": {
      "title": "Your application was accepted",
      "body": "Loading job at Owode-Onirin · ₦5,000 · 4h"
    },

    "data": {
      "kind": "application_update",
      "notification_id": "ntf_8a3f2c",
      "deeplink": "forge://jobs/job_a3f81c/clock-in",
      "sent_at": "2026-05-09T19:08:30Z"
    },

    "android": {
      "priority": "HIGH",
      "notification": {
        "channel_id": "forge_payments",
        "sound": "opay_credit",
        "icon": "ic_stat_forge",
        "color": "#0E695F",
        "click_action": "FLUTTER_NOTIFICATION_CLICK"
      }
    },

    "apns": {
      "headers": { "apns-priority": "10" },
      "payload": {
        "aps": {
          "alert": {
            "title": "Your application was accepted",
            "body": "Loading job at Owode-Onirin · ₦5,000 · 4h"
          },
          "sound": "opay_credit.caf",
          "badge": 3,
          "mutable-content": 1
        }
      }
    }
  }
}
```

### Field rules

| Path | Required | Notes |
|------|----------|-------|
| `notification.title` | yes | ≤ 60 chars. Same string as the in-app row's `title`. |
| `notification.body` | yes | ≤ 160 chars. Same as the in-app row's `body`. |
| `data.kind` | yes | One of the `kind` enum values from `19_notifications.md`. |
| `data.notification_id` | yes | The `id` of the in-app row this push corresponds to. Lets the mobile mark it read on tap and avoid double-counting the bell badge. |
| `data.deeplink` | conditional | Required for every `kind` except `system`. Mobile parses + routes via `RoutePaths`. |
| `data.sent_at` | yes | ISO 8601 UTC. Mobile uses it to drop pushes that arrive out-of-order. |
| `android.notification.channel_id` | yes | Routes to the right Android channel. See "Channels" below. |
| `android.notification.sound` | yes | Sound name **without extension**. Must be a raw resource on the device. |
| `apns.payload.aps.sound` | yes | iOS sound filename **with extension** (e.g. `opay_credit.caf`). Must be bundled in the iOS app. |
| `apns.payload.aps.badge` | optional | Set to the worker's current `unread_count`. iOS shows it on the home-screen icon. |

### Why both `notification` and `data`?

- **`notification` only**: system displays it, but if the app is killed, `data` from the tap is lost on iOS.
- **`data` only**: silent push — system won't display it in background/terminated unless the device explicitly handles it. Battery optimisations on Android also drop these aggressively.
- **Both**: system displays in background, app receives `data` reliably on tap, foreground delivery hits `FirebaseMessaging.onMessage` with both fields. This is the FCM-recommended pattern for user-facing notifications.

---

## Channels (Android)

Created by the mobile on first launch via `flutter_local_notifications`. Must exist before the first push of that channel arrives or Android falls back to the default channel and ignores `sound`.

| `channel_id` | Name (UI) | Importance | Sound | Used for |
|--------------|-----------|------------|-------|----------|
| `forge_payments` | "Payments & approvals" | `high` | `opay_credit` | Application accepted, wallet credited |
| `forge_jobs` | "New jobs near you" | `high` | default | `new_job` |
| `forge_default` | "General" | `default` | default | Rejections, loans, system |

User can disable any channel from system settings — the server-side `notifications.*` toggles in `/me/preferences` are the user's "soft" off-switch; channels are the OS-level switch. Both are honoured.

---

## Backend setup checklist

**One-time (per environment):**

1. Create a Firebase project (Console → Add project). Add **two apps**:
   - Android (`com.example.forge` — change to the production package id before launch).
   - iOS (`com.example.forge`). Upload an APNs **auth key** (`.p8`) from Apple Developer → Keys. FCM bridges to APNs using this key.
2. Generate a **service-account JSON** for the backend (Firebase Console → Project Settings → Service accounts → "Generate new private key"). Mount it as a secret on the API service. The backend uses this to mint OAuth tokens for the FCM HTTP v1 API (`https://fcm.googleapis.com/v1/projects/<project-id>/messages:send`).
3. Drop the platform configs into the mobile repo (handled by the mobile dev via `flutterfire configure` — see `lib/core/notifications/README.md` for the mobile setup).

**Send pipeline:**

- Push send is **always async** — never block an HTTP response on FCM. Trigger event → enqueue job → job sends.
- The send job:
  1. Loads all `(device_id, push_token)` rows for the worker.
  2. Sends one FCM HTTP v1 request per token.
  3. On `NotRegistered` / `InvalidRegistration` → delete the row.
  4. On `SenderIdMismatch` → log + alert (means the project rotated and old tokens are invalid).
  5. On 5xx → exponential backoff retry (3 attempts), then drop.
- Every successful send writes (or marks) the matching `notifications` row server-side. On tap, the mobile calls `POST /me/notifications/:id/read` using the `data.notification_id` from the payload — that's why the field is required.

**Quotas:**

- FCM free tier is generous (no hard daily cap on user-facing notifications). The bottleneck at scale is the per-project send rate (~360k QPS aggregated). At our target of 1M users with ~5 pushes/day each, we're well inside one project — no sharding needed for v1.

---

## Mobile-side wiring (reference, not contract)

The mobile half lives in `lib/core/notifications/`:

- `notifications_service.dart` — init, permission request, token register, foreground display, tap routing.
- `push_background_handler.dart` — top-level handler required by FCM for background/terminated isolate.
- `notification_channels.dart` — Android channel definitions (must match the `channel_id`s above).
- `device_repository.dart` — `POST` / `DELETE /me/devices`.

Wired in:

- `lib/main.dart` — `Firebase.initializeApp` + register background handler **before** `runApp`.
- `lib/app.dart` — service init after first frame; subscribes to tap stream and routes via GoRouter.
- `lib/features/auth/presentation/permissions/notification_permission_screen.dart` — calls `requestPermission` + `registerDevice` on the primary CTA.
- `lib/features/auth/data/auth_repository.dart` (logout flow) — calls `unregisterDevice` before clearing tokens.

---

## Out of scope of this file

- **Webhooks for Squad payment confirmations** — Squad → backend. The `payment` push is a downstream effect.
- **In-app feed shape** — see `19_notifications.md`.
- **Permission UI copy** — see the permission screen in the mobile repo.
