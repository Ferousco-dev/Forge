# Help & Support

Covers `lib/features/profile/presentation/help_support_screen.dart`. FAQ list + "Contact us" form.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| `GET`  | `/help/articles` | Public |
| `POST` | `/help/tickets` | Protected |

---

## `GET /help/articles`

Returns the FAQ. Public so it works during onboarding before the user has a token.

### Query parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `category` | enum | no | `getting_started` \| `payments` \| `loans` \| `account` |

### Response 200

```json
{
  "items": [
    {
      "id": "art_a3f2c",
      "category": "payments",
      "title": "When does my pay arrive?",
      "body_markdown": "Your pay is sent to your default bank...",
      "updated_at": "2026-04-12T08:00:00Z"
    }
  ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `body_markdown` | string | Rendered with `flutter_markdown` (TBD — not yet a dep). Keep markdown simple: paragraphs, bullet lists, links. |

### Notes for backend

- Cache aggressively: `Cache-Control: public, max-age=3600`. Articles change rarely.
- Edited via a CMS — not part of the deploy pipeline. Don't hard-code in source.

---

## `POST /help/tickets`

Submit a support ticket from the "Contact us" form.

### Request

```json
{
  "category": "payments",
  "subject": "Pay didn't arrive after clock-out",
  "message": "I clocked out at 3pm but the wallet still shows the old balance...",
  "related_transaction_id": "txn_e7290b",
  "related_job_id": "job_a3f81c"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `category` | enum | yes | Same enum as articles |
| `subject` | string | yes | 5–120 chars |
| `message` | string | yes | 20–2000 chars |
| `related_transaction_id` | string | no | When the user opens "Contact us" from a transaction detail, this is pre-filled |
| `related_job_id` | string | no | Same idea, from a job/application context |

### Response 201

```json
{
  "ticket_id": "tkt_8a3f2c",
  "estimated_response": "within 1 business day"
}
```

### Errors

| HTTP | Code | When |
|------|------|------|
| 400 | `VALIDATION_FAILED` | Subject / message out of bounds |
| 429 | `RATE_LIMITED` | More than 3 tickets / 24h |

### Notes for backend

- Auto-attach worker context to the ticket: `worker_id`, `device_id`, `app_version`, recent error logs (if mobile sends them — Phase H, not v1).
- Pipe to whatever ticketing system ops uses (Zendesk / Intercom / email-to-Linear).
