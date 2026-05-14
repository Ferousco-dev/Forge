# Uploads — Photos & Files (Cross-cutting)

Used by:
- `04_auth_profile_setup` (worker photo at signup) — see `01_auth.md`
- `07_work_session.md` (proof photo at clock-out)
- `17_edit_profile.md` (avatar update)

## Pattern

The mobile uploads a file, gets back an `upload_id`, then references that id in whatever business endpoint needs it (`profile-setup`, `clock-out`, `edit profile`). The business endpoint is responsible for promoting the upload to a permanent asset (CDN URL).

Why two-phase:
- Decouples slow, large file transfers from the small business request that follows.
- Lets the business endpoint validate the rest of its body (geofence, image moderation, etc.) before accepting the upload.
- Stale uploads (no business call within 24h) get garbage-collected automatically.

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `POST` | `/uploads` | Protected | — |

(Signup-time uploads are an exception — the upload happens *after* OTP verify, which already issues a token. No public upload endpoint.)

---

## `POST /uploads`

`multipart/form-data` only. Single file per request.

### Request

```
POST /uploads HTTP/1.1
Authorization: Bearer <access_token>
Content-Type: multipart/form-data; boundary=----formboundary

------formboundary
Content-Disposition: form-data; name="purpose"

clock_out_proof
------formboundary
Content-Disposition: form-data; name="file"; filename="IMG_4129.jpg"
Content-Type: image/jpeg

<binary>
------formboundary--
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `purpose` | enum | yes | `worker_avatar` \| `clock_out_proof`. Drives validation rules + storage path. |
| `file` | binary | yes | The file. |

### Constraints

| Purpose | Allowed types | Max size | Max dimensions | Notes |
|---------|---------------|----------|----------------|-------|
| `worker_avatar` | `image/jpeg`, `image/png`, `image/heic` | 8 MB | 2048×2048 | Server transcodes HEIC → JPEG |
| `clock_out_proof` | `image/jpeg`, `image/png`, `image/heic` | 12 MB | 4096×4096 | EXIF preserved (timestamp + GPS) so we can cross-check geofence |

### Response 201

```json
{
  "upload_id": "upl_8a3f2c",
  "url": "https://cdn-staging.forge.app/uploads/upl_8a3f2c.jpg",
  "expires_at": "2026-05-10T19:08:30Z"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `upload_id` | string | Reference for the business call. |
| `url` | string | Temporary URL — usable for preview during the photo-review screen. Becomes invalid after the upload is promoted (or after 24h if unused). |
| `expires_at` | ISO 8601 | After this, the upload is GC'd unless promoted. Mobile MUST call the consuming endpoint before this. |

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `MISSING_FILE` | No `file` part |
| 400 | `MISSING_PURPOSE` | No `purpose` part |
| 413 | `FILE_TOO_LARGE` | Over the per-purpose cap |
| 415 | `UNSUPPORTED_TYPE` | MIME not in the allowed list |
| 422 | `IMAGE_INVALID` | Server-side decode failed (corrupt) |

### Notes for backend

- Store uploads in a separate "staging" bucket. Promote to the canonical bucket (`worker-avatars/`, `clock-out-proofs/`) at consumption time.
- Strip EXIF for `worker_avatar` before serving (privacy). Keep EXIF for `clock_out_proof` (audit trail).
- Run image moderation **at consumption time**, not upload — it's expensive and we don't want to pay for uploads that get abandoned.
- If a user re-takes a photo, the previous `upload_id` is simply abandoned. No DELETE endpoint needed; GC handles it.
- Consider direct-to-S3 presigned URLs as an optimization later. Phase H.
