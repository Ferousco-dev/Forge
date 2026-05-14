# Liveness Capture — AI-verified Selfie

Covers `lib/features/auth/presentation/liveness_capture_screen.dart`.

After the worker verifies their phone via OTP on the **signup** flow,
the mobile shows a live selfie capture screen. The backend runs AI
liveness detection (single face, real human, not a photo-of-a-photo,
not a screen replay) and rejects spoofed images. On success the
returned `upload_id` flows into `POST /auth/profile-setup` as
`photo_upload_id` — the same field documented in `01_auth.md` and
`22_uploads.md`. So this endpoint replaces the generic `worker_avatar`
purpose for the signup path; existing `worker_avatar` upload remains
the route for **edit profile** updates from inside the app where the
worker is already trusted.

## Why a dedicated endpoint vs. extending `/uploads`

`POST /uploads` exists, but it's intentionally dumb — it stores the
file and returns an id. Image moderation runs at consumption time
(see `22_uploads.md` "Notes for backend"). For signup we need the
verification verdict **inline** so the mobile can ask the worker to
retry inside the same flow. Burying liveness behind
`/auth/profile-setup` would make the user fill out their name + skill
+ radius before learning their photo got rejected, which is a hostile
UX. Hence a separate endpoint that runs AI checks synchronously and
returns either an `upload_id` or a typed rejection reason.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/uploads/liveness` | Protected |

The worker is already authenticated by this point — OTP verify
returned a token pair, so the request rides the standard
`Authorization: Bearer <access_token>` header.

---

## `POST /uploads/liveness`

`multipart/form-data` only. Single image part.

### Request

```
POST /uploads/liveness HTTP/1.1
Authorization: Bearer <access_token>
Content-Type: multipart/form-data; boundary=----formboundary

------formboundary
Content-Disposition: form-data; name="file"; filename="selfie.jpg"
Content-Type: image/jpeg

<binary>
------formboundary
Content-Disposition: form-data; name="device_metadata"

{"platform":"ios","model":"iPhone 14","camera":"front"}
------formboundary--
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `file` | binary | yes | The selfie. |
| `device_metadata` | string (JSON) | no | Free-form context for fraud analytics — platform, model, capture camera. The mobile sends `{"platform":"ios\|android","model":"<device>","camera":"front\|rear"}`. |

### Constraints

| Property | Value |
|----------|-------|
| Allowed MIME | `image/jpeg`, `image/png`, `image/heic` |
| Max size | 12 MB |
| Max dimensions | 4096 × 4096 |
| Min dimensions | 240 × 240 (anything smaller fails quality check) |

The mobile pre-compresses to ~1024 px / quality 85 — server should
still enforce max bounds defensively.

### Response 201 — verified

```json
{
  "upload_id": "upl_8a3f2c",
  "url": "https://cdn-staging.forge.app/uploads/upl_8a3f2c.jpg",
  "expires_at": "2026-05-10T19:08:30Z",
  "liveness": {
    "passed": true,
    "confidence": 0.96,
    "face_count": 1
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `upload_id` | string | Mobile passes this back to `POST /auth/profile-setup` as `photo_upload_id`. |
| `url` | string | Temporary preview URL — usable for the photo-review step in the same screen. Becomes invalid once the upload is promoted (or after 24h if unused). |
| `expires_at` | ISO 8601 | After this, the upload is GC'd unless promoted by `/auth/profile-setup`. |
| `liveness.passed` | bool | Always `true` for 201. Always `false` paths return 422 below — never a 201 with `passed: false`. |
| `liveness.confidence` | float (0.0–1.0) | Anti-spoof model's confidence the photo is a live human. Persist for fraud analytics. |
| `liveness.face_count` | int | Always 1 for 201. |

### Errors

All liveness rejections return **HTTP 422** with the standard error
envelope. The mobile renders `error.message` directly; copy below is
the verbatim string the spec requires.

| HTTP | Code | When | Message (verbatim) |
|------|------|------|--------------------|
| 400  | `MISSING_FILE` | No file part | "No image was sent. Try again." |
| 413  | `FILE_TOO_LARGE` | > 12 MB | "That photo is too large. Try a smaller one." |
| 415  | `UNSUPPORTED_TYPE` | MIME not in allow-list | "Use a JPEG or PNG photo." |
| 422  | `LIVENESS_NO_FACE` | Face detector found nothing | "We couldn't see your face — try again in better light." |
| 422  | `LIVENESS_MULTIPLE_FACES` | More than one face | "Take the photo alone — only your face should be in frame." |
| 422  | `LIVENESS_SPOOF` | Anti-spoof model flagged a photo of a photo / screen replay / printed image | "Hold the phone up and look at the camera — don't take a photo of a photo." |
| 422  | `LIVENESS_LOW_QUALITY` | Blurry, dark, occluded, or below confidence floor | "The photo was too blurry or dark. Try again somewhere brighter." |
| 422  | `IMAGE_INVALID` | Server-side decode failed (corrupt) | "We couldn't read that photo. Take another one." |

#### Error envelope shape

```json
{
  "error": {
    "code": "LIVENESS_MULTIPLE_FACES",
    "message": "Take the photo alone — only your face should be in frame.",
    "details": {
      "reason": "multiple_faces",
      "face_count": 3
    }
  }
}
```

`details.reason` is a stable machine-readable enum (`no_face_detected`,
`multiple_faces`, `not_live`, `low_quality`) — mobile branches on it
for analytics + retry coaching. `details.face_count` is set on
`LIVENESS_MULTIPLE_FACES` and `LIVENESS_NO_FACE`. `details.confidence`
is set on `LIVENESS_SPOOF` and `LIVENESS_LOW_QUALITY`.

### Notes for backend

**AI provider — use Smile Identity.**

Smile Identity (Lagos) is the canonical pick for this endpoint:

- Their liveness model is trained on African faces — the AWS /
  Google / Face++ models have well-documented higher false-reject
  rates on darker skin tones. For a Nigerian labor app this isn't a
  fairness footnote, it's a workable-product question.
- Bundles face detection + liveness + anti-spoof + quality scoring
  into a single call (Smart Selfie Authentication / Registration),
  so the four-step pipeline below collapses into one HTTP request.
- Pairs naturally with the rest of the stack — same vendor family
  as the Nigerian KYC tooling Forge will need for higher-tier loans
  later (`Job Type 1` for document verification, `Job Type 5` for
  enhanced KYC). When that lands, the `partner_id` and SDK keys are
  already wired.
- NDPR / NDPC compliance and Nigerian data residency out of the
  box — relevant when the worker base is Nigerian and the data is
  biometric.

API: `POST /v1/smart_selfie_authentication` (or
`/v1/smart_selfie_registration` on the **first** capture for a
worker — registration creates a face record we can later authenticate
against, useful if Forge ever needs re-verification on suspicious
withdrawals). Pass `partner_id`, `job_id` (use the worker id), the
JPEG bytes, and a signed `signature` per the Smile partner doc.
Their response carries:

| Smile field | Forge mapping |
|-------------|---------------|
| `ResultCode = "0810"` (success) | `201` with `liveness.passed = true`, `confidence = 1 - SmileScore` |
| `ResultCode = "0820"` ("No Face Found") | `422 LIVENESS_NO_FACE` |
| `ResultCode = "0821"` ("Multiple Faces Found") | `422 LIVENESS_MULTIPLE_FACES`, with `details.face_count` from `Actions.Face_Count` |
| `Actions.Liveness_Check = "Spoof Detected"` | `422 LIVENESS_SPOOF`, with `details.confidence = SmileScore` |
| `Actions.Image_Quality_Check < threshold` | `422 LIVENESS_LOW_QUALITY` |
| Other non-success ResultCodes | `422 IMAGE_INVALID` (log Smile's raw `ResultText` for ops) |

Use Smile's sandbox environment (`https://testapi.smileidentity.com`)
in dev, production endpoint in prod. Credentials live in env vars —
**never** in the client.

**Recommended pipeline:**

1. **Decode + dimension/MIME validation.** Reject obvious junk locally
   before spending money on the Smile call.
2. **Smile Identity Smart Selfie call.** Server-to-server, JSON +
   base64 image. Returns face count, anti-spoof verdict, and quality
   in one envelope.
3. **Map the Smile response** to a Forge `LIVENESS_*` envelope per
   the table above.
4. **Persist** to the same staging bucket the rest of `/uploads`
   uses (`22_uploads.md`). Return `upload_id` only on Smile success.

**Fallback providers (only if Smile setup is blocked):**

- **AWS Rekognition Face Liveness** (`StartFaceLivenessSession`) —
  fastest if the backend is already on AWS, ~$0.025 / session,
  decent anti-spoof. Less accurate on African faces but acceptable.
- **Sightengine** `models=anti_spoof,face,quality` — single REST
  call, no SDK, cheap. Weakest anti-spoof of the three.

Switching providers later is a one-day refactor since this endpoint
keeps the public contract stable — the mobile only sees the Forge
`LIVENESS_*` envelope, never the underlying vendor's verdict.

**Costs / rate limits:**

- Rate-limit at **5 attempts / 10 minutes / worker**. After that,
  return `429 RATE_LIMITED` with `Retry-After`.
- Smile Smart Selfie pricing varies by partner contract — typically
  ~$0.05 / call. Rejecting on step 1 (size/MIME) before the AI call
  keeps cost predictable.

**Storage privacy:**

- Strip EXIF before serving (selfies often carry GPS).
- Keep the **rejected** images for 7 days in a separate audit bucket
  (so ops can review false-positive complaints), then GC.

**Promotion:**

- `POST /auth/profile-setup` already accepts `photo_upload_id` — when
  it sees an id from this endpoint, treat it identically to a
  `worker_avatar` upload: copy from staging to the canonical bucket
  and write the CDN URL into `worker.photo_url`.

**Edit-profile vs. signup:**

- Edit profile (`PATCH /me` with `photo_upload_id`) currently consumes
  the dumb `/uploads?purpose=worker_avatar` route. We **do not** force
  liveness there for now — the worker is already trusted. If product
  later wants periodic re-verification, adding `/uploads/liveness`
  acceptance to `PATCH /me` is a one-line change.

**Logging for fraud analytics:**

For every request log: `worker_id`, `device_metadata`, AI provider
verdicts (face_count, anti-spoof score, blur score), final decision,
elapsed ms. This lets ops trace a fraud pattern across attempts later.

## Mobile flow recap

```
OTP verify (signup, needs_profile_setup=true)
   │
   ▼
LivenessCaptureScreen
   ├── front camera, oval face guide
   ├── tap "Take photo"
   ├── POST /uploads/liveness (multipart, with bytes)
   │     │
   │     ├── 201 → store upload_id locally → "Continue"
   │     └── 4xx → render error.message inline → "Retake"
   ▼
ProfileSetupScreen
   └── POST /auth/profile-setup with the stored photo_upload_id
```

The verified `upload_id` is held in a Riverpod state provider for the
signup flow only — it's cleared on logout.
