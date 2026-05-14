# Settings — Notification + Privacy Preferences

Covers `lib/features/profile/presentation/settings_screen.dart`. Mobile groups: notifications, preferences (theme — local), privacy, account.

The **theme** picker is local-only (see `01_auth.md`). Everything else syncs.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET`  | `/me/preferences` | Protected |
| `PATCH` | `/me/preferences` | Protected |
| `POST` | `/me/account/delete` | Protected |
| `POST` | `/me/phone/change/request` | Protected |
| `POST` | `/me/phone/change/confirm` | Protected |
| `POST` | `/me/devices` | Protected |
| `DELETE` | `/me/devices/:device_id` | Protected |

---

## `GET /me/preferences`

```json
{
  "notifications": {
    "new_job_alerts": true,
    "application_updates": true,
    "payment_confirmations": true,
    "loan_reminders": true
  },
  "privacy": {
    "allow_location_tracking_during_work": true
  }
}
```

The `notifications` group controls **both** push delivery and the in-app feed entries (mobile shouldn't double-filter — server sources the truth).

The `privacy.allow_location_tracking_during_work` flag, when false, disables the heartbeat geofence check in `07_work_session.md`. Server falls back to time-based clock-out validation only — riskier for both sides, surfaced as a warning in the UI.

---

## `PATCH /me/preferences`

Same shape as GET. PATCH semantics — only present fields update.

### Response 200

Returns the merged result.

### Errors

Standard validation only.

### Notes for backend

- A toggle flip should be reflected immediately on the next push — don't batch.
- Mobile mirrors this in `lib/features/profile/state/settings_state.dart` (StateProvider). On every PATCH success, re-emit so the UI is consistent.

---

## `POST /me/account/delete`

Triggered from "Delete account" in settings. Currently the mobile shows a confirm dialog and a placeholder snackbar; this endpoint replaces the placeholder.

### Request

Empty body. The confirm-dialog already gated this on the device.

### Response 202 (deletion queued)

```json
{
  "deletion_request_id": "dr_8a3f2c",
  "scheduled_at": "2026-05-09T14:30:00Z",
  "completes_at": "2026-06-08T14:30:00Z"
}
```

Soft delete with a 30-day window. The user can recover by signing back in within 30 days.

### Errors

| HTTP | Code | When |
|------|------|------|
| 409 | `DELETE_BLOCKED` | Active loan or pending withdrawal exists. `details.reason` carries copy. |

### Notes for backend

- After this call, the mobile's `_LogoutGroup` flow runs — clear tokens, route to login.
- During the 30-day window, login MUST succeed and re-activate the account silently. The deletion job runs at `completes_at` and only proceeds if the worker hasn't logged in since the request.
- A successful re-login during the window cancels the request and notifies ops.

---

## `POST /me/phone/change/request`

Step 1 of changing phone number. Sends OTP to the **new** number.

### Request

```json
{
  "new_phone": "+2348099999999"
}
```

### Response 200

Same shape as `01_auth.md` `POST /auth/otp/request` — returns `challenge_id`.

### Errors

| HTTP | Code | When |
|------|------|------|
| 409 | `PHONE_ALREADY_EXISTS` | New number is already someone else's account |

---

## `POST /me/phone/change/confirm`

Step 2: verify OTP and atomically swap the phone number.

### Request

```json
{
  "challenge_id": "chl_8a3f2c1d",
  "code": "482301"
}
```

### Response 200

Returns the updated worker (same shape as `16_profile.md`).

### Errors

Same as `01_auth.md` OTP verify.

### Notes for backend

- Atomicity is critical: the row gets the new number AND the old number is freed for someone else to register, in a single transaction.
- All existing tokens for this worker remain valid — phone change does not require re-login.

---

## `POST /me/devices`

Register a push token for FCM. The mobile calls this on first launch after permission grant, on every FCM `onTokenRefresh`, and on cold start when the cached token diverges from the device's current one.

For the full push transport contract (payload shape, channels, custom sounds, server-side triggers), see [`24_push_notifications.md`](24_push_notifications.md). This section is the upstream-facing endpoint only.

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
| `push_token` | string | yes | FCM registration token. iOS uses the FCM-bridged token, not the raw APNs token. |
| `device_id` | string | yes | Persistent UUID, generated on first launch and stored in `flutter_secure_storage` |
| `app_version` | string | yes | Build identifier from `pubspec.yaml` (e.g. `1.0.0+1`) |

### Response 204

Empty.

### Notes for backend

- UPSERT on `(worker_id, device_id)`. A worker can have multiple active devices — push to all of them.
- Stale tokens (FCM returns `NotRegistered` / `InvalidRegistration`) get pruned by the push-send job, not by mobile.
- If the same `push_token` shows up under a different `worker_id` (worker A signed out, worker B signed in on the same phone), revoke the old binding and re-attach to the new worker.

---

## `DELETE /me/devices/:device_id`

Called from the mobile during logout, before tokens are cleared, so the row is removed cleanly.

### Response 204

Empty. Idempotent — deleting an already-deleted row returns 204 (do not 404).
