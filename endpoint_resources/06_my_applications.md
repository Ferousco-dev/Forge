# My Applications

Covers `lib/features/jobs/presentation/my_applications_screen.dart` — accessed from Profile → "My applications". Two tabs: **Active** (anything not `completed`/`rejected`) and **History**.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/applications` | Protected |

---

## `GET /applications`

### Query parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `bucket` | enum | yes | — | `active` \| `history` |
| `cursor` | string | no | — | Pagination cursor |
| `limit` | int | no | 20 | Max 50 |

`bucket` is the high-level filter:

- `active` returns applications with status in `applied`, `accepted`, `in_progress`.
- `history` returns `completed` and `rejected` (and `withdrawn` once that lands).

The two are mutually exclusive — every application is in exactly one bucket.

### Response 200

```json
{
  "items": [
    {
      "id": "app_2d1f4a",
      "status": "in_progress",
      "applied_at": "2026-05-09T14:30:00Z",
      "decided_at": "2026-05-09T14:42:00Z",
      "completed_at": null,
      "job": {
        "id": "job_a3f81c",
        "type": "loader",
        "title": "Load 5 tons of rebar",
        "pay_amount": 5000,
        "duration_hours": 4,
        "location": {
          "lat": 6.5901,
          "lng": 3.3725,
          "address": "Owode-Onirin Iron Market, Lagos"
        },
        "start_time": "2026-05-09T15:00:00Z",
        "employer": {
          "id": "emp_8c2e91",
          "name": "Adeolu Iron Wholesale",
          "photo_url": "https://cdn.forge.app/employer/emp_8c2e91.jpg"
        }
      }
    }
  ],
  "next_cursor": "eyJ0cyI6...",
  "has_more": true
}
```

### Notes for backend

- Use the **slim Job shape** above (no `description`, no `required_equipment`, no travel times, no `applicants_count`). The list view doesn't render any of those, so omit them to keep payload tight.
- Sort `active` by `applied_at DESC`. Sort `history` by `completed_at DESC` then `applied_at DESC`.
- Empty bucket → `{ items: [], next_cursor: null, has_more: false }`.
