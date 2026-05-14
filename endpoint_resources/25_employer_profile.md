# Employer Profile

Covers `lib/features/employers/presentation/employer_detail_screen.dart`. Workers reach this screen by tapping the "About the employer" card on a job detail, or the "View profile" button inside it.

The screen shows:

- Hero (photo, name, verified badge, rating, member since)
- Stats grid (open jobs, completed jobs, completion rate, average pay)
- About (business type, bio)
- Active jobs the employer has open right now
- History of recently-completed jobs

Two endpoints back this screen — one for the profile, one for the paginated job list.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET`  | `/employers/:id` | Protected |
| `GET`  | `/employers/:id/jobs` | Protected |

---

## `GET /employers/:id`

Full profile + stats. Extends the slim `Employer` shape that's already embedded in [`02_jobs_feed.md`](02_jobs_feed.md) — same `id`, `name`, `photo_url`, `rating`, `jobs_posted`, `member_since`, `phone_number` — and adds the richer fields the dedicated screen needs.

### Response 200

```json
{
  "id": "emp_8a3f2c1d",
  "name": "Lagos Logistics Co.",
  "photo_url": "https://cdn.forge.app/employers/emp_8a3f2c1d.jpg",
  "rating": 4.7,
  "jobs_posted": 142,
  "member_since": "2024-03-12T10:30:00Z",
  "phone_number": "+2348012345678",

  "verified": true,
  "business_type": "Logistics & freight",
  "bio": "Lagos-wide container offloading. We post 4–6 short-shift jobs every week — same workers welcome to come back.",

  "primary_location": {
    "address": "Apapa Wharf, Lagos",
    "lat": 6.4474,
    "lng": 3.3611
  },

  "stats": {
    "open_jobs": 4,
    "completed_jobs": 138,
    "completion_rate": 0.97,
    "average_pay": 6500,
    "average_response_time_minutes": 18,
    "ratings_breakdown": {
      "5": 98,
      "4": 24,
      "3": 8,
      "2": 5,
      "1": 3
    }
  }
}
```

### Field shape

Top-level — slim `Employer` fields (existing wire shape, unchanged):

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `emp_xxx` |
| `name` | string | Display name |
| `photo_url` | string \| null | Logo / avatar |
| `rating` | number | 0.0 – 5.0, one decimal |
| `jobs_posted` | int | Total all-time |
| `member_since` | ISO 8601 | Account creation |
| `phone_number` | string \| null | E.164 |

Top-level — additions for the profile screen:

| Field | Type | Notes |
|-------|------|-------|
| `verified` | bool | Triggers the verified badge in the hero. Verification process is admin-side; the mobile just renders. |
| `business_type` | string | Free-form short label (e.g. "Wholesale distributor", "Steel fabrication"). Display only — not enum-bounded so we can grow categories without a mobile release. |
| `bio` | string \| null | ≤ 280 chars. Plain text. |
| `primary_location` | object | Where the employer typically operates from. Used for "average distance from your radius" copy. |

`stats` — server-computed, refreshed on every read:

| Field | Type | Notes |
|-------|------|-------|
| `open_jobs` | int | Currently posted, not yet filled / closed. |
| `completed_jobs` | int | Lifetime delivered work sessions, by all workers. |
| `completion_rate` | number | 0.0 – 1.0. `completed_jobs / (completed_jobs + cancelled_jobs)`. Mobile renders as a percentage. |
| `average_pay` | int | NGN integer. Median across all posted jobs. |
| `average_response_time_minutes` | int | Median time from worker apply → employer accept/reject. Lets workers gauge "will I hear back today?". |
| `ratings_breakdown` | object | Histogram of 1–5 star ratings. Sum equals total ratings received (which can be lower than `jobs_posted` if some sessions weren't rated). |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `EMPLOYER_NOT_FOUND` | No employer with this id, or the employer was suspended |

### Notes for backend

- **Rating histogram** drives the small bar chart on the profile screen. Returning the breakdown lets the mobile render the chart without a second round-trip; the server already aggregates this for the admin dashboard, so it's cheap.
- **`completion_rate`** is the single most-important trust signal in this market. If you don't have enough sessions to compute it confidently (< 10 completions), return `0` and set `stats.completed_jobs < 10` — mobile hides the rate when it's not meaningful and shows "New employer" copy instead.
- **`average_response_time_minutes`** should be capped at a 30-day rolling window. A long-tail of stale applications would otherwise drag this number to useless ranges.

---

## `GET /employers/:id/jobs`

Paginated job list scoped to one employer. Same per-row shape as [`02_jobs_feed.md`](02_jobs_feed.md) — the mobile reuses the `JobCard` widget — but distance fields are computed against the worker's current location passed in the query.

### Query parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `status` | enum | no | `all` | `open` \| `closed` \| `all`. `open` = currently accepting applicants. `closed` = filled or expired. |
| `lat` | number | yes | — | Worker's current latitude. Distance fields are computed against this. |
| `lng` | number | yes | — | Worker's current longitude. |
| `cursor` | string | no | — | Pagination cursor |
| `limit` | int | no | 20 | Max 100 |

### Response 200

```json
{
  "items": [
    {
      "id": "job_a3f81c",
      "type": "loader",
      "title": "Offload 40ft container at Apapa warehouse",
      "description": "Six-hour loader shift...",
      "pay_amount": 6500,
      "duration_hours": 6,
      "location": {
        "lat": 6.4474,
        "lng": 3.3611,
        "address": "Plot 14, Apapa Wharf, Lagos"
      },
      "distance_meters": 4200,
      "travel_time_walking_minutes": 52,
      "travel_time_driving_minutes": 9,
      "start_time": "2026-05-11T07:00:00Z",
      "required_equipment": ["Safety boots", "Gloves"],
      "employer": { "...slim Employer shape..." },
      "status": "open"
    }
  ],
  "next_cursor": "eyJ0cyI6...",
  "has_more": false
}
```

Per-row shape is identical to `/jobs` (see `02_jobs_feed.md`) plus a single new field:

| Field | Type | Notes |
|-------|------|-------|
| `status` | enum | `open` \| `closed`. Required on this endpoint so the UI can group "active" vs. "history" without a second query. NOT present on the public `/jobs` feed (which only returns `open` jobs by definition). |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `EMPLOYER_NOT_FOUND` | Same as `GET /employers/:id` |

### Notes for backend

- Default `status=all` returns open jobs first, then closed, ordered by `start_time DESC`. Mobile relies on this ordering — the screen splits the rendered list at the first `closed` row to label "Active jobs" / "Recent history".
- `closed` jobs still need their `distance_meters` and `travel_time_*` fields populated (mobile renders them in muted text). Compute against `lat`/`lng` exactly like the open feed.
- For the hackathon demo, capping at the **last 30 days** is fine. Older history isn't useful on the mobile and clutters the list.

---

## Out of scope of this file

- Reviews / ratings on individual jobs — separate endpoint when we wire the worker's "leave a rating after clock-out" flow.
- Reporting / blocking an employer — admin-side, deferred to post-hackathon.
- Following an employer — would need a notification trigger ("X has posted a new job"); deferred.
