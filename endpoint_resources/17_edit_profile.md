# Edit Profile

Covers `lib/features/profile/presentation/edit_profile_screen.dart`. User can change their name, photo, primary skill, and preferred work radius.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `PATCH` | `/me` | Protected |

---

## `PATCH /me`

All fields optional. Only those present in the body are updated. Standard PATCH semantics (not PUT — partial update).

### Request

```json
{
  "name": "Tunde A. Adeyemi",
  "primary_skill": "Welder",
  "preferred_radius_km": 12.0,
  "photo_upload_id": "upl_8a3f2c"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | 2–60 chars trimmed. Updates `worker.name`. |
| `primary_skill` | enum | One of: `Loader`, `Driver`, `Unloader`, `General Labor`, `Welder`. |
| `preferred_radius_km` | double | 1.0–25.0 |
| `photo_upload_id` | string | From `22_uploads.md`. Server fetches the upload, persists it as the new `photo_url`, and discards the old image. |

To **remove** the photo (revert to the initial-fallback), send `"photo_upload_id": null` explicitly. Omitting the field is "no change".

### Response 200

```json
{
  "worker": { /* full Worker — see 16_profile.md */ }
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Field out of bounds |
| 422 | `UPLOAD_NOT_FOUND` | `photo_upload_id` not resolvable |
| 422 | `UPLOAD_REJECTED` | Image fails moderation (NSFW, blank, low quality) |

### Notes for backend

- `phone_number` is **NOT** mutable through this endpoint — it requires re-OTP. Phone change has its own flow under settings (Phase H — not yet specced).
- Changing `primary_skill` should NOT re-rank the jobs feed retroactively, but the next `GET /jobs` call will use the new skill in relevance.
- Image moderation: integrate AWS Rekognition / Sightengine. Reject NSFW, return `UPLOAD_REJECTED` so mobile asks the user for a different photo.
- Update `joined_at` is forbidden — server ignores it silently if a malicious client sends it.
