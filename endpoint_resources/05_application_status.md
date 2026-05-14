# Application Status

Covers `lib/features/work/presentation/application_status_screen.dart`. Single application view with a status timeline and (when accepted) the "Clock in" CTA.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/applications/:id` | Protected |
| `POST` | `/applications/:id/withdraw` | Protected |

---

## `GET /applications/:id`

### Path params

| Param | Type | Notes |
|-------|------|-------|
| `id` | string | Application id (`app_2d1f4a`) |

### Response 200

```json
{
  "id": "app_2d1f4a",
  "status": "accepted",
  "applied_at": "2026-05-09T14:30:00Z",
  "decided_at": "2026-05-09T14:42:00Z",
  "completed_at": null,
  "note": "I have my own gloves...",
  "job": { /* full Job object — see 03_job_detail.md */ },
  "session": null
}
```

### Status timeline fields

| Field | Set when status reaches | Notes |
|-------|------------------------|-------|
| `applied_at` | `applied` | Always set |
| `decided_at` | `accepted` or `rejected` | When the employer made a call |
| `completed_at` | `completed` | When the worker clocked out and Squad disbursed pay |

### `session`

When `status` is `in_progress` or `completed`, this carries the work-session record (clock-in timestamp, geofence lat/lng, photos). See `07_work_session.md` for the full shape. `null` for any other status.

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Application id doesn't exist or belongs to another worker |

### Notes for backend

- `404` is intentional even when the row exists but belongs to another worker — never confirm existence to the wrong user.
- Mobile polls this endpoint every 30s while status is `applied` and the screen is foregrounded. Cap server-side rate at 60s if it becomes a hotspot.

---

## `POST /applications/:id/withdraw`

Worker pulls back an application before the employer decides. Only valid while status is `applied`.

### Request

Empty body.

### Response 200

```json
{
  "id": "app_2d1f4a",
  "status": "withdrawn",
  "withdrawn_at": "2026-05-09T14:35:00Z"
}
```

A new status `withdrawn` is added to the enum. Update mobile's `ApplicationStatus` enum when this lands. (UI shows it as "Withdrawn" — same shape as rejected, less harsh copy.)

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Bad id / not the worker's application |
| 409 | `INVALID_STATE` | Status is anything other than `applied` |
