# Jobs Feed — Nearby Jobs List

Covers `lib/features/jobs/presentation/jobs_screen.dart` — the home tab.

The screen shows a live map of pins + a draggable bottom sheet listing jobs sorted by relevance. Filters live in a sticky chip row above the list (job type, max distance, min pay).

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/jobs` | Protected |

---

## `GET /jobs`

Returns jobs the worker is eligible for, near their current location, sorted by `relevance_score` descending. The server computes relevance from distance + pay + skill match + employer rating; mobile does not re-sort.

### Query parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `lat` | double | yes | — | Worker's current latitude. WGS84. |
| `lng` | double | yes | — | Worker's current longitude. |
| `radius_km` | double | no | worker's `preferred_radius_km` | Override for this query only |
| `types` | csv of enum | no | all | `loader,driver,unloader,general_labor,welder` |
| `min_pay` | int | no | — | Filter to jobs with `pay_amount >= min_pay` |
| `cursor` | string | no | — | Cursor from a previous response |
| `limit` | int | no | 20 | Max 50 |

Example:
```
GET /jobs?lat=6.5895&lng=3.3719&types=loader,unloader&min_pay=3000
```

### Response 200

```json
{
  "items": [
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
        "member_since": "2024-08-01T00:00:00Z"
      },
      "relevance_score": 0.94    // server-computed; mobile ignores
    }
  ],
  "next_cursor": "eyJ0cyI6...",
  "has_more": true
}
```

### Field shape (`Job`)

Mirrors `lib/core/mock/models.dart` `Job` class. `type` is the enum's snake_case name:

| Mobile (`JobType`) | Wire (`type`) | Display label |
|--------------------|---------------|---------------|
| `loader` | `loader` | Loader |
| `driver` | `driver` | Driver |
| `unloader` | `unloader` | Unloader |
| `generalLabor` | `general_labor` | General Labor |
| `welder` | `welder` | Welder |

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Missing `lat`/`lng`, bad enum in `types` |
| 401 | `AUTH_REQUIRED` | No / expired token |

### Notes for backend

- Sort by `relevance_score DESC, distance_meters ASC` as a tiebreaker.
- A job that the worker has **already applied to** must NOT appear in this feed (server filter — mobile relies on this and won't dedupe).
- Jobs whose `start_time` has already passed must NOT appear.
- `distance_meters` and travel times are computed server-side from the `lat`/`lng` query params. Use a simple haversine + a constant walking pace (5 km/h) and driving pace (25 km/h Lagos-realistic). Don't call Google Maps for every list item.
- Cap response at `limit` items even when more match — let cursor pagination do its job.
- Empty state is `{ items: [], next_cursor: null, has_more: false }` — not 404.
