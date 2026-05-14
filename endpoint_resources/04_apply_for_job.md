# Apply for a Job

Triggered from the "Apply now" CTA on the job detail screen (`job_detail_screen.dart` → modal). Creates a `JobApplication` server-side.

## Endpoints

| Method | Path | Auth | Idempotent |
|--------|------|------|-----------|
| `POST` | `/jobs/:id/apply` | Protected | ⚡ |

---

## `POST /jobs/:id/apply` ⚡

### Path params

| Param | Type | Notes |
|-------|------|-------|
| `id` | string | Job id |

### Request

```json
{
  "note": "I have my own gloves and can be there in 5 min."
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `note` | string | no | Optional message to the employer. 0–280 chars. |

### Response 201

```json
{
  "application": {
    "id": "app_2d1f4a",
    "job_id": "job_a3f81c",
    "status": "applied",
    "applied_at": "2026-05-09T14:30:00Z",
    "completed_at": null,
    "note": "I have my own gloves and can be there in 5 min."
  }
}
```

### Status enum

Mirrors `ApplicationStatus` in `lib/core/mock/models.dart`:

| Wire | Display | Meaning |
|------|---------|---------|
| `applied` | Applied | Submitted, awaiting employer decision |
| `accepted` | Accepted | Employer chose this worker. Clock-in unlocks. |
| `rejected` | Rejected | Employer declined or chose someone else |
| `in_progress` | In progress | Worker has clocked in |
| `completed` | Completed | Worker has clocked out and the job is done |

### Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | Job id doesn't exist |
| 409 | `ALREADY_APPLIED` | Worker already applied. Returns the existing application in `details.application`. |
| 410 | `JOB_EXPIRED` | `start_time` passed |
| 410 | `JOB_FILLED` | Slot filled |
| 422 | `BUSINESS_RULE_VIOLATION` | E.g. worker has 3+ active applications already (Phase H — TBD with product) |

### Notes for backend

- Idempotency key required. A retry must return the same application (200, not 201) — never create duplicates.
- On `ALREADY_APPLIED` return 409 *with the existing application embedded* so mobile can navigate straight to the status screen without another call.
- Push a notification to the employer: "New applicant for {job.title}".
- Update `applicants_count` on the job (used by `03_job_detail.md`).
