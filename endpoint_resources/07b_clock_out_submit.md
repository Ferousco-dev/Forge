# Clock-out submit — mobile flow

End-to-end contract for the "Submit" CTA on the photo Review screen
(`lib/features/work/presentation/submitting_screen.dart`). Two
backend calls in strict sequence; either failing aborts the flow
without losing local state.

## Preconditions

Before this screen is reached the worker has:

1. Tapped **I've arrived** (≤ 30 min before `job.start_time`).
2. Cleared the clock-in geofence + `accuracy_meters ≤ 30`.
3. Called `POST /v1/sessions` → received `session.id` (stashed as
   `WorkSession.serverSessionId`, persisted by `SessionStorage`).
4. Stayed on the clock at least `WorkSession.minimumDuration` (5 min).
5. Captured a photo on the clock-out camera (`shot.path` +
   `pos.latitude` / `pos.longitude` / `pos.accuracy` stashed as
   `WorkSession.photoPath` / `clockOutLat` / `clockOutLng` /
   `clockOutAccuracy`).

If any of those are missing, the submit screen short-circuits to its
error state before hitting the network. Codes:

| Missing                       | Local code           |
|-------------------------------|----------------------|
| `serverSessionId`             | `NO_SERVER_SESSION`  |
| `photoPath`                   | `NO_PHOTO`           |
| `clockOutLat/Lng/Accuracy`    | `NO_LOCATION`        |
| no active session             | `NO_SESSION`         |

## Step 1 — Upload the proof

```
POST /v1/uploads
Authorization: Bearer <access_token>
Content-Type: multipart/form-data; boundary=...

--boundary
Content-Disposition: form-data; name="purpose"

clock_out_proof
--boundary
Content-Disposition: form-data; name="file"; filename="clock_out_<application_id>.jpg"
Content-Type: image/jpeg

<binary>
--boundary--
```

**Response 200**

```json
{
  "upload_id": "upl_8f3a2d…",
  "url": "https://cdn.forge.example.com/uploads/upl_8f3a2d…",
  "expires_at": "2026-05-13T19:42:00Z"
}
```

Errors surfaced as `ApiException`; the mobile UI renders `error.message`
verbatim and offers Retry.

## Step 2 — Clock out

```
POST /v1/sessions/<session_id>/clock-out
Authorization: Bearer <access_token>
Idempotency-Key: <uuid-v4 stable across retries — keyed on session_id>
Content-Type: application/json

{
  "proof_upload_id": "upl_8f3a2d…",
  "lat": 6.5894,
  "lng": 3.3719,
  "accuracy_meters": 14.7
}
```

`lat` / `lng` are the coords **captured at photo-snap time**, not a
fresh fix. Sending a fresh fix risks the 100 m geofence (the worker may
have walked off-site while uploading) and would re-introduce the bug
the camera-side geofence check was meant to prevent.

**Response 200 / 202**

```json
{
  "session": {
    "id": "ses_…",
    "application_id": "app_…",
    "status": "completed",
    "clock_in_at": "...",
    "clock_out_at": "...",
    "duration_hours_worked": 0.85,
    "pay_amount_pending": 0,
    "pay_amount_disbursed": 11500,
    "transaction_id": "txn_…",
    "proof_photo_url": "https://…"
  }
}
```

`200` = disbursement settled synchronously. `202` = queued (poll the
transaction or wait for the `payment_processed` push). Either is a
success — the mobile UI routes to `RoutePaths.jobClockOutComplete`.

## Error handling

Server `error.code` → mobile behaviour:

| code                            | HTTP | UI action                                        |
|---------------------------------|------|--------------------------------------------------|
| `OUTSIDE_GEOFENCE`              | 422  | Retake photo (geofence re-check happens client-side at snap, server-side at submit)  |
| `PROOF_REJECTED`                | 422  | Retake photo                                     |
| `UPLOAD_NOT_FOUND`              | 422  | Retake photo (upload expired — TTL is ~24 h)     |
| `INVALID_STATE`                 | 409  | Show message; offer Retry (e.g. session already completed → routes home on retry) |
| `PAYMENT_PROVIDER_UNAVAILABLE`  | 502  | Retry — Squad outage, session is `completed` server-side, payout queued separately |
| anything else                   | *    | Retry                                            |

`NO_PHOTO` / `NO_LOCATION` / `FILE_IO` are local-only codes (never
emitted by the server) and always route to **Retake photo**.

## Idempotency

- `POST /uploads` is **not** idempotent. A second submit-after-retry
  uploads the photo again. That's fine — the server keys uploads by
  content hash on the storage side and the wasted bandwidth is small.
- `POST /sessions/{id}/clock-out` **is** idempotent on
  `Idempotency-Key`. The mobile client uses the stable key
  `clock-out:<session_id>` (see `SessionsRepository.clockOut`). A
  Squad outage that returns 502 lets the worker hit Retry without
  risking double-disbursement.

## Mobile state machine

```
reviewing  ──submit──▶  submitting (upload)
                          │
                          ├─ 4xx/5xx ─▶ submitting (error)
                          │              ├─ retake ─▶ camera
                          │              └─ retry  ─▶ submitting (upload)
                          │
                          ▼
                        submitting (clock-out)
                          │
                          ├─ 4xx/5xx ─▶ submitting (error)
                          │              └─ retry ─▶ submitting (upload)
                          │
                          ▼
                        done ─▶ work_complete screen
```

Notes:
- `enterSubmitting` clears `submissionProgress` to 0 and persists the
  phase, so an app kill mid-submit resumes on a fresh attempt rather
  than skipping past the upload.
- `complete()` only runs after the clock-out HTTP returned ≥200/<300.
  The success screen never renders for a failed submit.
- `PopScope(canPop: _hasError)` blocks Android system-back while a
  network call is in flight.
