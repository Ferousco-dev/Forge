# FCM Push + OTP Delivery Channels — Backend Brief

**Audience:** backend (claude-coding-the-server).
**Status:** mobile side is implemented and shipping. Backend has the gaps below.
**Last edit:** 2026-05-13.

This document covers two adjacent topics:

1. **Part A — Firebase Cloud Messaging (FCM):** the push pipeline the mobile already consumes. The mobile is fully wired. Backend has to (a) register devices, (b) emit pushes via FCM Admin SDK, (c) clean up dead tokens.

2. **Part B — OTP channel switch:** we don't have a paid SMS gateway (Termii bills credit per send). Proposal: send the OTP via **WhatsApp Business API** (primary) and **FCM push** (fallback for already-installed users). Keep the existing SMS path as a final fallback for users on basic phones.

---

# Part A — FCM Push

## 1. What the mobile already does

### Token lifecycle

- On cold start, `Firebase.initializeApp()` runs and the background-message handler is registered against a top-level function (`firebaseMessagingBackgroundHandler`).
- After OS permission grant (`POST_NOTIFICATIONS` on Android 13+, `UNUserNotificationCenter` on iOS), the app:
  1. Calls `FirebaseMessaging.getToken()`.
  2. Generates / reads a stable `device_id` from secure storage (`dvc_<16-char-uuid>`).
  3. POSTs the device row (see contract below).
- On `FirebaseMessaging.onTokenRefresh`, the app re-POSTs the same `device_id` with the new token. Server MUST UPSERT.
- On logout, the mobile clears the cached token locally. There is **no DELETE call today** — the server has to prune dead rows itself (see §3 below).

### Channels (Android)

Three Android `NotificationChannel`s are created at first launch:

| `channel_id`       | Name           | Importance | Sound              | Use                                   |
|--------------------|----------------|------------|--------------------|---------------------------------------|
| `forge_payments`   | Payments       | HIGH       | `opay_credit.mp3`  | `payment_processed`, `payment_initiated` |
| `forge_jobs`       | Jobs           | HIGH       | default            | `new_job`, `application_update`       |
| `forge_default`    | General        | DEFAULT    | default            | anything else (`system`, etc.)        |

You can either set `data.channel_id` explicitly per push, or send `data.kind` and the mobile maps kind → channel.

### Delivery, by app state

| App state       | Who draws the tray notification?                                           | Mobile code path                                  |
|-----------------|----------------------------------------------------------------------------|---------------------------------------------------|
| **Foreground**  | The mobile (`flutter_local_notifications`) — FCM doesn't auto-show on Android, and iOS suppresses by default. | `_displayForeground` in `notifications_service.dart` |
| **Background**  | The OS. App's background isolate runs `firebaseMessagingBackgroundHandler` purely to keep FCM happy.        | `push_background_handler.dart`                    |
| **Terminated**  | The OS. On tap, `getInitialMessage()` is drained on cold boot.             | `_drainInitialMessage` in `notifications_service.dart` |

So: **always send a `notification` block** (`title`, `body`). The OS uses it for tray rendering in background/terminated states. Send the `data` block too — the mobile uses it for channel selection, deeplink, and the in-app feed sync.

### Tap → deeplink

`data.deeplink` is a `forge://` URI. The mobile translates it to a GoRouter path:

| Deeplink                                | In-app route                       |
|-----------------------------------------|------------------------------------|
| `forge://jobs/{id}`                     | `/jobs/{id}`                       |
| `forge://jobs/{id}/clock-in`            | `/jobs/{id}/clock-in`              |
| `forge://jobs/{id}/status`              | `/jobs/{id}/status`                |
| `forge://transactions/{id}`             | `/earnings/transactions/{id}`      |
| `forge://loans/approved`                | `/loans/approved`                  |
| `forge://loans/rejected`                | `/loans/rejected`                  |
| `forge://loans/{id}`                    | `/loans/{id}`                      |
| `forge://notifications`                 | `/profile/notifications`           |

Keep the deeplink **stable** for a given `kind` so server-side and mobile-side routing don't drift.

## 2. Endpoints the backend has to implement

These are the contracts the mobile already calls. **None of them are in the OpenAPI spec yet** — add them.

### 2.1 `POST /v1/me/devices` — register / upsert push token

**Auth:** Bearer (worker scope).
**Idempotency:** server-side UPSERT keyed on `(user_id, device_id)`. No `Idempotency-Key` header required — calling with the same `device_id` twice updates the row, never duplicates.

**Request**

```json
{
  "device_id": "dvc_8a1b3c4d5e6f7g8h",
  "push_token": "<FCM registration token>",
  "platform": "android" | "ios",
  "app_version": "1.0.0+1"
}
```

**Response 200/201**

```json
{
  "device": {
    "id": "dvc_8a1b3c4d5e6f7g8h",
    "registered_at": "2026-05-13T10:23:11Z"
  }
}
```

**Errors**

| HTTP | code                | meaning                                            |
|------|---------------------|----------------------------------------------------|
| 400  | `VALIDATION_FAILED` | platform not in enum, push_token empty, etc.       |

Notes:
- `device_id` is the **stable per-install identifier**, NOT the FCM token. FCM tokens rotate; `device_id` does not (it survives sign-out, dies on uninstall).
- The mobile debounces: it only POSTs when the FCM token differs from the last successfully-posted one (`last_registered_push_token` in secure storage).

### 2.2 `DELETE /v1/me/devices/{device_id}` — unregister (not yet implemented)

**Auth:** Bearer.
**Status:** **mobile is ready to call this but skips it today** because the server endpoint doesn't exist. Implement it and the mobile will start calling it on logout.

**Response:** `204 No Content`. Best-effort — succeeds even if the row is already gone.

**Why we need it:** today, logging out of device A and signing in as a different worker on the same device leaves the OLD worker's row pointing at the device's FCM token. The send pipeline either has to dedupe by token (expensive) or you get phantom pushes to the wrong worker until the token rotates.

### 2.3 Server-side token pruning (no endpoint, just a job)

When FCM's `messages:send` returns `messaging/registration-token-not-registered` (or `UNREGISTERED`), delete the Device row. This is the canonical cleanup for uninstalled apps.

## 3. FCM payload contract

The mobile reads three things from every push: `notification.title`, `notification.body`, and the entire `data` block. The `data` block keys are:

| key               | required | example                                | meaning                                                  |
|-------------------|----------|----------------------------------------|----------------------------------------------------------|
| `kind`            | **yes**  | `payment_processed`                    | Drives channel inference + in-app feed grouping.         |
| `notification_id` | yes      | `ntf_b3e1…`                            | Server-side id; mobile uses for tap deduplication.       |
| `deeplink`        | yes*     | `forge://transactions/txn_a1b…`        | `forge://` URI. Required for kinds that route somewhere. |
| `channel_id`      | optional | `forge_payments`                       | Overrides the kind → channel mapping in §1.              |
| `image_url`       | optional | `https://cdn.../hero.png`              | Big-picture style on Android (rich notifications).       |

\* `system` and other non-routable kinds can omit `deeplink`. The mobile will silently ignore taps with no deeplink.

### Canonical `kind` values

| `kind`                  | When the server sends it                          | Suggested `channel_id` | Suggested deeplink                          |
|-------------------------|---------------------------------------------------|------------------------|---------------------------------------------|
| `application_accepted`  | Employer accepted the worker's application        | `forge_jobs`           | `forge://jobs/{job_id}/status`              |
| `application_rejected`  | Employer rejected (or another applicant was accepted) | `forge_jobs`       | `forge://jobs/{job_id}/status`              |
| `new_job`               | A new job within the worker's preferred radius posts | `forge_jobs`        | `forge://jobs/{job_id}`                     |
| `clock_in_reminder`     | 30 min before `job.start_time` for an accepted app | `forge_jobs`          | `forge://jobs/{job_id}/clock-in`            |
| `payment_initiated`     | Clock-out → `pay_amount_disbursed` queued         | `forge_payments`       | `forge://transactions/{txn_id}`             |
| `payment_processed`     | Squad webhook confirmed transfer settled          | `forge_payments`       | `forge://transactions/{txn_id}`             |
| `loan_approved`         | Loan auto-approved or credit officer approved     | `forge_payments`       | `forge://loans/{loan_id}`                   |
| `loan_rejected`         | Loan denied                                       | `forge_default`        | `forge://loans/rejected`                    |
| `loan_repayment_due`    | 24 h before a scheduled `LoanRepayment.due_at`    | `forge_default`        | `forge://loans/{loan_id}`                   |
| `system`                | App-wide announcement, security alert, etc.       | `forge_default`        | (omit)                                      |

### Example payload (FCM Admin SDK)

```js
admin.messaging().send({
  token: device.push_token,
  notification: {
    title: '₦11,500 just paid out',
    body:  'Maxim Corps · General laborer (Stocker)'
  },
  data: {
    kind:            'payment_processed',
    notification_id: 'ntf_b3e102a4',
    deeplink:        'forge://transactions/txn_a1b2c3',
    channel_id:      'forge_payments'
  },
  android: {
    priority: 'high',
    notification: {
      sound:        'opay_credit',   // matches the channel sound
      channelId:    'forge_payments'
    }
  },
  apns: {
    headers: { 'apns-priority': '10' },
    payload: { aps: { sound: 'opay_credit.caf' } }
  }
});
```

All keys in `data` MUST be strings — FCM enforces this. Numbers and booleans have to be `JSON.stringify`'d.

## 4. Required FCM credentials

- **Server-side:** a Firebase service-account JSON. The backend uses `firebase-admin` with this credential to call `messaging().send()`.
- **Project:** must match the one referenced by `lib/firebase_options.dart` on mobile.
- **Sender ID:** must match the `google-services.json` / `GoogleService-Info.plist` bundled in the mobile build, or tokens won't decrypt.

If the backend doesn't already have FCM credentials, ask the mobile team to share the Firebase project access (Firebase Console → Project settings → Service accounts → Generate new private key).

---

# Part B — OTP via WhatsApp / FCM (the new ask)

## Why change SMS

- Termii bills credit per SMS; running with no balance just means OTPs silently fail.
- WhatsApp Business has free-tier service messages for authentication templates (rate-limited but no per-message cost).
- Returning users **already have the app installed and a registered FCM device** — for them we can deliver the OTP as a push notification and skip both SMS and WhatsApp entirely.

## Channel selection rules

For each `POST /v1/auth/otp/request`, the server picks ONE channel and returns which one it used so the mobile UI can render the right "Check your WhatsApp" / "Check your messages" / "Check your notifications" copy.

```
                                        ┌─────────────────────────────────────┐
phone arrives ──▶ Is this a known       │ YES + has active FCM device ──▶ FCM │
                  user (returning)?     │ YES + no active FCM device   ─┐     │
                                        │ NO (signup)                  ─┤     │
                                        └──────────────────────────────┬┘     │
                                                                       │      │
                                                          ┌────────────┘      │
                                                          │                   │
                                       ┌──────────────────▼─────────────┐    │
                                       │ Has WhatsApp opted-in?         │    │
                                       │  ↓ unknown / never asked       │    │
                                       │ Send via WhatsApp (default for │    │
                                       │ NG numbers — high coverage)    │    │
                                       └────────────────────────────────┘    │
                                                                              │
                                       last-resort fallback: SMS via Termii ──┘
                                       (only when WhatsApp send fails AND
                                        no FCM device)
```

Concrete rule:

1. **If the phone matches an existing user AND that user has ≥1 active device row with a non-stale push_token → FCM push.** This is "silent OTP" — the user gets a notification, taps it (or the in-app handler reads the code), and is one tap from logged in.
2. **Otherwise → WhatsApp.** Cheaper than SMS for Nigerian numbers and higher delivery on weak networks.
3. **WhatsApp fails (provider error, number not on WhatsApp) → SMS via Termii.** Final fallback.

## API changes

### 2.1 `POST /v1/auth/otp/request` — accept a channel hint, return the channel used

**Request — extend with `preferred_channel`**

```json
{
  "phone": "+2348012345678",
  "flow": "login" | "signup",
  "preferred_channel": "auto" | "whatsapp" | "sms" | "push"
}
```

- `"auto"` (default) — server picks via the rule above. **Mobile should send `"auto"` always**; the dropdown is for support tooling only.
- The other three force the channel. `"push"` returns `422 NO_PUSH_DEVICE` if the user has no registered device.

**Response — extend with `channel`**

```json
{
  "challenge_id": "chl_b8a3…",
  "expires_at": "2026-05-13T10:43:11Z",
  "resend_available_at": "2026-05-13T10:39:11Z",
  "channel": "whatsapp" | "sms" | "push",
  "channel_hint": "your WhatsApp" | "your phone" | "your Forge app"
}
```

`channel_hint` is a pre-localised string the mobile can paste into the OTP screen ("Code sent to your WhatsApp"). Saves the mobile from hardcoding the mapping.

**New errors**

| HTTP | code              | meaning                                            |
|------|-------------------|----------------------------------------------------|
| 422  | `NO_PUSH_DEVICE`  | `preferred_channel=push` but the user has no device |
| 502  | `CHANNEL_UNAVAILABLE` | WhatsApp/SMS/FCM provider returned an error    |

### 2.2 `POST /v1/auth/otp/verify` — no change

Same DTO, same response. The channel doesn't affect verification — the server just compares the submitted code against the challenge.

### 2.3 New endpoint: `POST /v1/auth/otp/channels` — quick lookup

**Auth:** none (used on the OTP screen BEFORE auth).
**Purpose:** mobile asks "for THIS phone, what channels can you reach me on right now?" so the "Send via WhatsApp / Send via SMS / Send to my app" buttons render correctly.

**Request**

```json
{ "phone": "+2348012345678" }
```

**Response**

```json
{
  "channels": [
    { "kind": "push",     "available": true,  "hint": "your Forge app" },
    { "kind": "whatsapp", "available": true,  "hint": "your WhatsApp" },
    { "kind": "sms",      "available": true,  "hint": "your phone" }
  ],
  "default": "push"
}
```

The server's `default` is what the mobile sends as `preferred_channel` when the user taps the primary CTA. The other entries back the "Try a different channel" sheet.

This endpoint has to be **public** (no auth) AND **rate-limited per phone** (e.g. 10 req / 15 min) so it can't be used as a phone-enumeration oracle. Keep `available: true` even for non-existent users — leak nothing.

## Channel implementations

### WhatsApp — recommended provider

Either **Termii's WhatsApp channel** (same vendor as current SMS, minimal integration work) or **Meta's Cloud API directly** (no per-message cost on the free tier, but more setup):

- **Termii WhatsApp:** `POST https://api.ng.termii.com/api/sms/send` with `channel: "whatsapp"`. Same SDK as the current SMS path. Cheapest path to ship.
- **Meta Cloud API:** requires a Business Manager + an approved Authentication template. The template body is something like:

  ```
  Your Forge code is {{1}}. Don't share it. Code expires in 10 min.
  ```

  Approval takes 24-48 h, but per-message cost is $0 in NG.

**My recommendation: ship with Termii's WhatsApp channel today (one-line SDK change from the current SMS call), apply for the Meta template in parallel, swap when approved.**

### FCM as an OTP channel

This is the interesting part. The push payload looks like:

```js
admin.messaging().send({
  token: device.push_token,
  notification: {
    title: 'Your Forge code',
    body:  '482 519 — don't share. Tap to log in.'
  },
  data: {
    kind:            'auth_otp',
    notification_id: 'ntf_otp_x9k…',
    deeplink:        'forge://auth/verify?challenge=chl_b8a3&code=482519',
    challenge_id:    'chl_b8a3',
    code:            '482519',           // see security note below
    channel_id:      'forge_default'
  },
  android: { priority: 'high' },
  apns:    { headers: { 'apns-priority': '10' } }
});
```

**Security:**
- The push is encrypted in transit (FCM uses TLS) and at rest on the device.
- The risk is a malicious app reading the notification via Android's `NotificationListenerService` (requires a user-granted accessibility-level permission — high bar, but not zero).
- For OTPs we'll send the code in `data.code` AND embed it in the deeplink. The mobile will:
  1. Auto-fill the OTP input when the deeplink fires.
  2. Show the notification with the code in the body so users on a different device (e.g. WhatsApp Web) can still type it.
- If we want stricter security later, drop `data.code` and ship only the deeplink — tapping the notification opens the app pre-authenticated with the challenge, no code visible.

**Mobile-side work needed (separate task — flag it):**
- Add `auth_otp` to the kind table in §1.
- Handle the `forge://auth/verify?...` deeplink: parse `challenge` + `code`, prefill the OTP screen, optionally auto-submit.

## Rollout

1. **Phase 1** — server adds `preferred_channel: "whatsapp"` and `channel` in the response. Mobile UI shows "Code sent to your WhatsApp". This alone covers ~95% of users.
2. **Phase 2** — server adds the FCM path. Mobile adds the `auth_otp` deeplink handler.
3. **Phase 3** — server adds `POST /v1/auth/otp/channels` and the "Try another channel" sheet on mobile.

You can do Phase 1 alone and we're already off the Termii SMS bill for returning users.

---

# Summary checklist for the backend

- [ ] Implement `POST /v1/me/devices` (UPSERT). **Mobile is already calling it.**
- [ ] Implement `DELETE /v1/me/devices/{id}`. Mobile is ready to call on logout.
- [ ] Add Device-row pruning when FCM returns `UNREGISTERED` from `messages:send`.
- [ ] Wire `firebase-admin` with a service-account credential. Ask mobile team for the Firebase project access if you don't have it.
- [ ] Implement the canonical `kind` → push table from §3. Every server-side state change that should notify a worker should map to one row of that table.
- [ ] Add `preferred_channel` to `POST /v1/auth/otp/request` and `channel` to its response. Default to WhatsApp via Termii's WhatsApp channel.
- [ ] (Optional Phase 3) Add `POST /v1/auth/otp/channels`.
- [ ] Document everything above in the OpenAPI spec so the audit gap closes.
