# Work Session — Clock-in → In Progress → Clock-out

Covers the full work lifecycle:

- `lib/features/work/presentation/clock_in_screen.dart`
- `lib/features/work/presentation/work_in_progress_screen.dart`
- `lib/features/work/presentation/clock_out_camera_screen.dart`
- `lib/features/work/presentation/photo_review_screen.dart`
- `lib/features/work/presentation/submitting_screen.dart`
- `lib/features/work/presentation/work_complete_screen.dart`

The whole flow is server-authoritative. Mobile holds no state that isn't echoed back from the server.

## State machine

```
   accepted (from 05)
       │
       │ POST /sessions  ──► CLOCKED_IN
       │                      │
       │                      │ (worker stays on site; mobile polls)
       │                      ▼
       │                    IN_PROGRESS  ◄── GET /sessions/:id (heartbeat)
       │                      │
       │                      │ POST /sessions/:id/clock-out
       │                      │   { proof_upload_id, lat, lng }
       │                      ▼
       │                    SUBMITTING  (server is calling Squad to disburse)
       │                      │
       │                      ├── disbursement OK ──► COMPLETED
       │                      └── disbursement FAIL ──► PAYMENT_PENDING
                                                          (manual ops review)
```

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `POST` | `/sessions` | Protected | ⚡ |
| `GET`  | `/sessions/:id` | Protected | — |
| `POST` | `/sessions/:id/clock-out` | Protected | ⚡ |

---

## `POST /sessions` ⚡ — Clock in

Starts the work session. Verifies the worker is inside the geofence.

### Request

```json
{
  "application_id": "app_2d1f4a",
  "lat": 6.5902,
  "lng": 3.3726,
  "accuracy_meters": 8.0
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `application_id` | string | yes | Must be in `accepted` state |
| `lat` | double | yes | Worker's current GPS |
| `lng` | double | yes | |
| `accuracy_meters` | double | yes | From the device's location service. Server may reject sessions with poor accuracy (> 50m). |

### Response 201

```json
{
  "session": {
    "id": "ses_4b9c1f",
    "application_id": "app_2d1f4a",
    "status": "in_progress",
    "clock_in_at": "2026-05-09T15:02:00Z",
    "clock_in_location": { "lat": 6.5902, "lng": 3.3726 },
    "clock_out_at": null,
    "expected_clock_out_at": "2026-05-09T19:02:00Z",
    "duration_hours_worked": 0.0,
    "pay_amount_pending": 5000,
    "proof_photo_url": null
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `expected_clock_out_at` | ISO 8601 | `clock_in_at + job.duration_hours`. Mobile shows a countdown. |
| `pay_amount_pending` | int | What the worker will earn on successful clock-out. Locked at clock-in time. |
| `proof_photo_url` | string \| null | Set on clock-out (see below) |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Bad application id |
| 409 | `INVALID_STATE` | Application not `accepted`, or session already exists |
| 422 | `OUTSIDE_GEOFENCE` | Worker is > 200m from `job.location`. Returns `details.distance_meters` and `details.required_radius_meters` so mobile can show "You're 240m away — get closer to the site." |
| 422 | `LOCATION_ACCURACY_TOO_LOW` | `accuracy_meters > 50`. Mobile asks the user to move outdoors. |

### Notes for backend

- Geofence radius is **200m** by default. Per-job override in `job.geofence_radius_meters` (Phase H).
- Idempotency key required. A retry from the same key returns the existing session, not a duplicate.
- Update the `JobApplication.status` to `in_progress` atomically with session creation.
- Set the job to `filled` so other workers stop seeing it in the feed (though this should already be true if the employer used the accept flow correctly).

---

## `GET /sessions/:id` — Heartbeat / poll

Mobile polls this every 60s while `work_in_progress_screen.dart` is foregrounded. Returns the latest session state plus a server-computed `duration_hours_worked`.

### Response 200

Same shape as the create response above, with updated `duration_hours_worked` and (after clock-out) `clock_out_at`, `proof_photo_url`, and final `status`.

### Notes for backend

- Cheap — a single row read. Set CDN/edge cache TTL to 0; this is always live.
- Mobile uses this to detect when the server has finished disbursement (status flips from `submitting` → `completed`).

---

## `POST /sessions/:id/clock-out` ⚡

Ends the session, uploads the proof photo, triggers Squad disbursement.

### Request

```json
{
  "proof_upload_id": "upl_7e2c91",
  "lat": 6.5904,
  "lng": 3.3728,
  "accuracy_meters": 6.5,
  "worker_note": "All bundles loaded as agreed."
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `proof_upload_id` | string | yes | From `22_uploads.md`. Server fetches the photo and persists a `proof_photo_url`. |
| `lat` | double | yes | Worker's GPS at clock-out |
| `lng` | double | yes | |
| `accuracy_meters` | double | yes | |
| `worker_note` | string | no | 0–500 chars |

### Response 200 (sync — fast disbursement)

```json
{
  "session": {
    "id": "ses_4b9c1f",
    "status": "completed",
    "clock_in_at": "2026-05-09T15:02:00Z",
    "clock_out_at": "2026-05-09T19:08:00Z",
    "duration_hours_worked": 4.1,
    "pay_amount_pending": 0,
    "pay_amount_disbursed": 5000,
    "transaction_id": "txn_e7290b",
    "proof_photo_url": "https://cdn.forge.app/proof/ses_4b9c1f.jpg"
  }
}
```

### Response 202 (async — disbursement queued)

When Squad takes more than ~3 seconds, return 202 with status `submitting`. Mobile shows the submitting screen and polls until `completed`.

```json
{
  "session": {
    "id": "ses_4b9c1f",
    "status": "submitting",
    "clock_out_at": "2026-05-09T19:08:00Z",
    "duration_hours_worked": 4.1,
    "pay_amount_pending": 5000,
    "pay_amount_disbursed": 0,
    "transaction_id": null,
    "proof_photo_url": "https://cdn.forge.app/proof/ses_4b9c1f.jpg"
  }
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 409 | `INVALID_STATE` | Session not `in_progress` |
| 422 | `OUTSIDE_GEOFENCE` | Worker > 200m from job site at clock-out (configurable — some employers may not need this) |
| 422 | `UPLOAD_NOT_FOUND` | `proof_upload_id` not resolvable |
| 422 | `PROOF_REJECTED` | Server-side image moderation flagged the photo (blank, NSFW, completely black, etc.). Mobile asks the user to retake. |
| 502 | `PAYMENT_PROVIDER_UNAVAILABLE` | Squad is down. Mobile retries via the idempotency key. |

### Notes for backend

- The clock-out is the **payment trigger**. The whole flow must be atomic: session → completed, application → completed, transaction created, push notification sent.
- Squad integration: server calls Squad's transfer API with the worker's default bank account. On success, store `transaction_id` (linked to `txn_xxx` in the transaction table — see `09_transactions.md`).
- If Squad fails twice, status flips to `payment_pending` and ops gets a Slack alert. Mobile shows "Payment is processing — we'll notify you when it lands" instead of the success screen.
- Push to employer: "{worker} clocked out — pay disbursed".

## Push notifications referenced in this flow

| Trigger | Channel | Notification |
|---------|---------|--------------|
| Application accepted | FCM/APNs | "{employer} accepted you — clock in when you arrive" |
| Application rejected | FCM/APNs | Soft copy: "Another worker was chosen this time" |
| Clock-out succeeded | FCM/APNs | "₦{amount} arrived in your wallet" |
| Disbursement failed | FCM/APNs | "Your pay is processing — usually < 5 min" |

These all create entries in `19_notifications.md` so the in-app feed mirrors the push.
