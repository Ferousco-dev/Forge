# Job Detail

Covers `lib/features/jobs/presentation/job_detail_screen.dart`.

Single-job view with the full description, employer block, location preview, and an "Apply now" CTA at the bottom.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/jobs/:id` | Protected |

---

## `GET /jobs/:id`

Fetch one job. Same shape as the items in `02_jobs_feed.md`, plus a few fields that are too heavy for the list view.

### Path params

| Param | Type | Notes |
|-------|------|-------|
| `id` | string | Opaque job id (`job_a3f81c`) |

### Query parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `lat` | double | yes | Used to recompute `distance_meters` + travel times for the current location (the worker may have moved since the feed loaded). |
| `lng` | double | yes | |

### Response 200

```json
{
  "id": "job_a3f81c",
  "type": "loader",
  "title": "Load 5 tons of rebar",
  "description": "Loading bundled 12mm rebar onto a 911 truck...",
  "pay_amount": 5000,
  "duration_hours": 4,
  "location": {
    "lat": 6.5901,
    "lng": 3.3725,
    "address": "Owode-Onirin Iron Market, Lagos"
  },
  "distance_meters": 320,
  "travel_time_walking_minutes": 4,
  "travel_time_driving_minutes": 1,
  "start_time": "2026-05-09T15:00:00Z",
  "required_equipment": ["work gloves", "boots"],
  "employer": {
    "id": "emp_8c2e91",
    "name": "Adeolu Iron Wholesale",
    "photo_url": "https://cdn.forge.app/employer/emp_8c2e91.jpg",
    "rating": 4.7,
    "jobs_posted": 142,
    "member_since": "2024-08-01T00:00:00Z",
    "phone_number": "+2348012345678"
  },
  "viewer_application": null,
  "applicants_count": 7
}
```

### Extra fields (vs. feed item)

| Field | Type | Notes |
|-------|------|-------|
| `employer.phone_number` | string \| null | E.164. Only revealed once the worker is `accepted` for the job. `null` otherwise. |
| `viewer_application` | object \| null | If the current worker has already applied, this carries the application — see shape in `05_application_status.md`. `null` if not applied. |
| `applicants_count` | int | Total applicants. UI shows "7 others applied" social proof. |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Job id doesn't exist |
| 410 | `JOB_EXPIRED` | `start_time` already passed |
| 410 | `JOB_FILLED` | Employer accepted someone else |

### Notes for backend

- `JOB_EXPIRED` and `JOB_FILLED` are different HTTP 410s — mobile shows different copy ("This job has started" vs "Already filled — try the next one").
- `viewer_application` lets the mobile skip a separate `GET /applications/by-job/:id` round trip when the user revisits the screen.
- `employer.phone_number` is sensitive. Gate behind the `accepted` status.
