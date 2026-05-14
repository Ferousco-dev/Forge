# AI Surfaces — Forge AI Endpoints

Five AI-powered endpoints layered on top of the existing API. Each one
is a thin gateway in front of a managed provider (Anthropic / OpenAI /
Whisper / Smile Identity). The mobile app never talks to the AI vendor
directly — every key, prompt, and rate-limit lives on the Forge
backend.

| # | Endpoint | What it does | Provider | Latency budget |
|---|----------|--------------|----------|----------------|
| 1 | `POST /ai/jobs/:id/summarize` | One-line digest of a job description | Anthropic Haiku 4.5 | < 600 ms p95 |
| 2 | `POST /ai/search/parse` | Free-text or voice → structured filters | Whisper + Haiku 4.5 | < 1500 ms p95 (voice) / < 400 ms p95 (text) |
| 3 | `POST /ai/profile/extract` | Natural-language self-description → profile fields | Anthropic Haiku 4.5 | < 800 ms p95 |
| 4 | `POST /uploads/liveness` (v2 upgrade) | Already exists — additive fields only | Smile Identity (existing) + GPT-4 Vision sidecar | unchanged |
| 5 | `POST /ai/disputes/:id/mediate` | Suggested resolution + drafted messages for both parties | Anthropic Sonnet 4.6 | < 4 s p95 |

## Why a Forge gateway instead of "let the mobile call OpenAI"

1. **Keys never ship to the client.** A leaked OpenAI key from a
   published APK is unrecoverable; from a server it's a rotation.
2. **Rate-limit per worker, not per device.** A user reinstalling the
   app should not reset their daily quota.
3. **Prompt rotation without an app update.** Prompts are tuned weekly;
   if they live in the client, every tweak requires a release.
4. **Audit trail for fraud / abuse.** All five endpoints log the
   worker id, raw input, model verdict, elapsed ms. Mobile-direct
   calls can't be audited centrally.
5. **Vendor swap is one server change.** Today: Anthropic. Tomorrow:
   self-hosted Llama 4. Mobile contract doesn't move.

## Conventions specific to this file

- All five endpoints are **Protected** (Bearer token).
- All accept the standard `Idempotency-Key` header. Re-running the
  same request with the same key returns the cached response — important
  because LLMs are non-deterministic and you don't want a flaky network
  to charge twice and yield two different answers.
- All return a `meta` block alongside the payload:
  ```json
  {
    "data": { ... endpoint-specific ... },
    "meta": {
      "model": "claude-haiku-4-5",
      "provider": "anthropic",
      "elapsed_ms": 412,
      "cached": false
    }
  }
  ```
  Mobile ignores `meta` in production; it's invaluable in debug builds
  and for ops dashboards.
- Errors share one new code: `AI_UNAVAILABLE` (502) — covers vendor
  timeouts, vendor 5xx, and circuit-breaker open. Mobile renders a
  graceful fallback (raw description, plain text search, etc.) when
  this fires.

## Cost guardrails

| Endpoint | Cost/call (est.) | Daily quota / worker | Cached |
|----------|------------------|----------------------|--------|
| `/ai/jobs/:id/summarize` | $0.0002 | unlimited (server cache by `job_id`) | Yes — 7 days |
| `/ai/search/parse` (text) | $0.0003 | 200 / day | No |
| `/ai/search/parse` (voice) | $0.006 | 60 / day | No |
| `/ai/profile/extract` | $0.0005 | 20 / day | No |
| `/uploads/liveness` GPT-4 V sidecar | $0.01 | 5 / day (existing limit) | No |
| `/ai/disputes/:id/mediate` | $0.015 | 5 / day | No |

Quotas are per `worker_id`, sliding 24h window. Over-quota returns
`429 RATE_LIMITED` with `Retry-After` seconds.

---

# 1. `POST /ai/jobs/:id/summarize`

**Job-description summarizer.** Long employer postings → one-line
scannable digest on the job card.

The card shown today renders the full `description` truncated with
`overflow: ellipsis`. For verbose postings this loses information
about pay, location nuance, and equipment. The AI summary fits in two
lines max and captures: *what to do, how long, where, headline pay*.

## Endpoint

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/ai/jobs/:id/summarize` | Protected |

⚡ Idempotent. ⚠️ Server-cached for 7 days keyed by `job_id` — every
worker hitting the same job pays the cache, not the model.

## Request

```json
POST /ai/jobs/job_a3f81c/summarize
Authorization: Bearer <access_token>
Content-Type: application/json
Idempotency-Key: <uuid>

{}
```

Empty body. The server has the full `Job` record by id. We deliberately
do **not** accept a custom prompt or override — that would turn this
into an LLM-on-tap surface and balloon cost.

## Response 200

```json
{
  "data": {
    "summary": "Load 5 tons of 12mm rebar onto a 911 truck. 4 hours, ₦5,000, Owode-Onirin. Gloves + boots required.",
    "highlights": [
      { "label": "Pay", "value": "₦5,000" },
      { "label": "Duration", "value": "4 hours" },
      { "label": "Equipment", "value": "gloves, boots" }
    ]
  },
  "meta": {
    "model": "claude-haiku-4-5",
    "provider": "anthropic",
    "elapsed_ms": 412,
    "cached": true
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `summary` | string | Max 140 chars. Always one or two sentences. Always Naija-English; never code-switches to formal English. |
| `highlights` | array (0–4) | Mobile renders these as inline chips on the card. Always English label, value as in `summary`. May be empty if the description is too sparse to extract. |

## Errors

| HTTP | Code | When |
|------|------|------|
| 404 | `NOT_FOUND` | `job_id` doesn't exist or is closed |
| 429 | `RATE_LIMITED` | n/a — endpoint has no per-worker quota |
| 502 | `AI_UNAVAILABLE` | Anthropic timeout or 5xx; mobile falls back to truncated `description` |

## Notes for backend

**Provider — Anthropic Haiku 4.5.**

Haiku is the right pick because (a) summarization is the easiest LLM
task and Haiku handles it indistinguishably from Sonnet, (b) it's the
cheapest production-tier Anthropic model, and (c) under prompt caching
the system prompt (which is identical for every call) is free after
the first request of the rolling 5-minute window. With our request
volume the cache hit rate sits well above 95%.

**Prompt (server-owned, version-controlled):**

```
System: You are summarizing labor jobs for Nigerian day workers on the
Forge marketplace. Output: ONE line, max 140 chars. Include: what to
do, duration, pay in Naira, location landmark. Use Naija-English
register ("Pay ₦5k", "4 hours", "Apapa"). Skip filler words. If pay
or duration is missing from the source, omit that part — never
fabricate. After the line, output a JSON array of 0–4 highlight chips:
[{"label":"Pay","value":"₦5,000"}, ...]. Wrap the response in:
<summary>...</summary><highlights>[...]</highlights>.

User: <full Job.description, type, pay_amount, duration_hours,
location.address verbatim>
```

**Caching.**

- Server cache keyed by `job_id` only, 7-day TTL. Job descriptions are
  immutable post-publish (per `02_jobs_feed.md`) — if an employer
  edits, bump the cache key.
- Use **Anthropic prompt caching** (`cache_control: {type:
  "ephemeral"}`) on the system prompt. ~90% cost reduction on the
  cached portion. See `claude-api` skill for setup.
- Mobile-side: render the summary in the `JobCard` widget below the
  title. Show the un-summarized description on tap (job detail screen)
  — the summary is *augmentation*, never a replacement.

**Fallback when the AI is down:**

Return `502 AI_UNAVAILABLE` after a 3-second vendor timeout. Mobile
already renders the raw description; the summary chip just won't
appear. No retry loop in the mobile — the cache fills on the next
worker's request anyway.

**When to invalidate the cache:**

- Employer edits the job (rare — most jobs are immutable).
- An ops user manually flags the summary as wrong (admin endpoint).
- Schema version bump (we changed the prompt). Bump a global salt in
  the cache key.

---

# 2. `POST /ai/search/parse`

**Voice + text search to structured filters.** Single endpoint, two
modes — accepts a text query OR an audio clip; returns the same
shaped result.

Today the search screen does substring filtering over the cached jobs
list (`jobs_search_screen.dart`). Workers type fragments like
`"driver lagos morning"` and get whatever happens to contain all
three words. That's brittle and inaccessible to low-literacy users.

This endpoint takes either form — text or a short voice clip — and
returns the same structured filter envelope. The mobile then applies
that envelope client-side to the cached jobs feed (no new jobs call).

## Endpoint

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/ai/search/parse` | Protected |

⚡ Idempotent. Voice mode: `multipart/form-data`. Text mode:
`application/json`.

## Request — text mode

```json
POST /ai/search/parse
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "text": "I dey find driver job near Ikeja for tomorrow morning",
  "context": {
    "worker_lat": 6.5895,
    "worker_lng": 3.3719,
    "now": "2026-05-12T08:30:00Z"
  }
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `text` | string | yes | 1–200 chars. Trim whitespace. |
| `context.worker_lat` / `worker_lng` | double | no | Anchor for relative locations ("near me"). |
| `context.now` | ISO 8601 | no | Anchor for relative time ("tomorrow morning"). Defaults to server time. |

## Request — voice mode

```
POST /ai/search/parse
Authorization: Bearer <access_token>
Content-Type: multipart/form-data; boundary=----formboundary

------formboundary
Content-Disposition: form-data; name="audio"; filename="search.m4a"
Content-Type: audio/m4a

<binary, ≤ 30s, ≤ 4 MB>
------formboundary
Content-Disposition: form-data; name="context"

{"worker_lat":6.5895,"worker_lng":3.3719,"now":"2026-05-12T08:30:00Z"}
------formboundary--
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `audio` | binary | yes | M4A/AAC/MP3/WAV/OGG. Max 30 s, max 4 MB. |
| `context` | string (JSON) | no | Same shape as text-mode `context`. |

## Constraints

| Property | Value |
|----------|-------|
| Audio MIME allow-list | `audio/m4a`, `audio/aac`, `audio/mpeg`, `audio/wav`, `audio/ogg` |
| Max audio duration | 30 seconds |
| Max audio file size | 4 MB |
| Max text length | 200 chars |

## Response 200

Both modes return the same envelope:

```json
{
  "data": {
    "transcript": "I dey find driver job near Ikeja for tomorrow morning",
    "filters": {
      "types": ["driver"],
      "near": {
        "lat": 6.6018,
        "lng": 3.3515,
        "label": "Ikeja, Lagos",
        "radius_km": 5
      },
      "start_after": "2026-05-13T05:00:00Z",
      "start_before": "2026-05-13T11:00:00Z",
      "min_pay": null,
      "max_pay": null,
      "keywords": []
    },
    "confidence": 0.92,
    "unresolved": []
  },
  "meta": {
    "model": "claude-haiku-4-5",
    "provider": "anthropic",
    "transcription_provider": "whisper",
    "elapsed_ms": 1140,
    "cached": false
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `transcript` | string | The interpreted text. For text mode, equals the input. For voice mode, the Whisper transcript verbatim. |
| `filters.types` | array of `JobType` | Empty if no type was implied. |
| `filters.near` | object \| null | `{ lat, lng, label, radius_km }`. `radius_km` defaults to 5 if a place is named but no distance specified. |
| `filters.start_after` / `start_before` | ISO 8601 \| null | Resolved against `context.now`. "Tomorrow morning" → 05:00–11:00 local of next day, both in UTC. |
| `filters.min_pay` / `max_pay` | int \| null | Whole Naira. |
| `filters.keywords` | array of string | Free-text terms that didn't map to a structured filter ("port", "diesel"). Mobile uses these for client-side substring match on top of the structured filters. |
| `confidence` | float 0–1 | Overall parse confidence. Mobile shows a "did you mean?" chip when `< 0.6`. |
| `unresolved` | array of string | Phrases the parser couldn't interpret. Mobile surfaces these so the worker can refine. Example: `["urgent"]`. |

## Errors

| HTTP | Code | When | Message (verbatim) |
|------|------|------|--------------------|
| 400 | `MISSING_INPUT` | Neither `text` nor `audio` provided | "Type or speak what you're looking for." |
| 400 | `TEXT_TOO_LONG` | Text > 200 chars | "Make it shorter — say what kind of job you want." |
| 400 | `AUDIO_TOO_LONG` | Audio > 30 s | "That recording is too long. Try a shorter one." |
| 413 | `FILE_TOO_LARGE` | Audio > 4 MB | "That recording is too large. Try a shorter one." |
| 415 | `UNSUPPORTED_TYPE` | Audio MIME not in allow-list | "We couldn't read that recording. Try again." |
| 422 | `UNINTELLIGIBLE` | Whisper returned empty or `confidence < 0.3` | "We didn't catch that. Try again somewhere quieter." |
| 429 | `RATE_LIMITED` | Over daily quota | "You've made too many searches. Try again in a few minutes." |
| 502 | `AI_UNAVAILABLE` | Vendor 5xx or timeout | "Search is having a moment — please try typing instead." |

## Notes for backend

**Two providers — Whisper + Anthropic Haiku 4.5.**

1. **Whisper** (`whisper-1` via OpenAI, or `whisper-large-v3` on a
   managed inference host like Replicate / Modal) for transcription.
   Voice-mode only. Whisper handles Nigerian English / Pidgin
   acceptably above ~12 kHz audio; the mobile records at 16 kHz mono.
2. **Anthropic Haiku 4.5** for structured extraction. The model
   receives the transcript + JSON schema for `filters`, returns the
   filled-in JSON. Use **structured outputs** (Anthropic's tool-use
   API) — this gives back a guaranteed-valid JSON envelope instead of
   string parsing.

**Pipeline:**

```
Voice mode:                       Text mode:
  audio  ─►  Whisper  ─► text       text  ─►  Haiku 4.5  ─► filters
                       │                                      ▲
                       └──────────────────────────────────────┘
```

**Place resolution.**

The model returns place names as strings. The backend resolves
`"Ikeja"` → `{ lat, lng, label }` using a server-side gazetteer of
Nigerian cities + neighborhoods. Don't ship this resolution to the LLM
— it hallucinates lat/lng. Common cases the gazetteer must cover:
Lagos neighborhoods (Apapa, Ikeja, Lekki, Surulere, Yaba…), Abuja
districts, the 6 geopolitical zones, and the top 30 cities by
population. Anything unresolved → omit `filters.near` and surface
the original phrase in `unresolved`.

**Time resolution.**

"Tomorrow" / "today" / "morning" / "evening" / "this weekend" must
resolve against `context.now` (or server time) using **WAT (UTC+1)**
as the worker's local time. The model gets the *resolved* anchor in
the prompt — don't ask Haiku to do timezone math.

**Prompt:**

```
System: You parse Nigerian day-worker job searches. Given a transcript
and the worker's local time (WAT) + GPS, return ONLY a structured
filter envelope matching the provided schema. Job types are exactly:
loader, driver, unloader, general_labor, welder. Locations are NAMES
(string) — the server resolves them. Pay is whole Naira (integers).
Time windows are anchored to the given local time. If a phrase is
ambiguous, leave the field null and put the raw phrase in
"unresolved". Confidence reflects your overall certainty.

User: Transcript: "<text>"
Worker time (WAT): "<now in WAT>"
Worker GPS: <lat>,<lng>
```

The schema is provided as an Anthropic tool definition — the model is
forced to return a valid `SearchFilters` JSON object. No string
parsing on the server.

**Rate limiting.**

- Text mode: 200 / day / worker.
- Voice mode: 60 / day / worker.
- Burst: 10 / minute, regardless of mode.
- Voice quota is tighter because Whisper costs ~20× more per call than
  Haiku alone.

**Audio storage.**

Don't persist audio. Decode → stream to Whisper → discard. The
transcript and final filter envelope are logged for fraud analytics;
the audio is not. This keeps GDPR / NDPR exposure minimal.

**Whisper alternative.**

If we hit Whisper rate limits or pricing concerns, **Deepgram Nova-2**
is the swap. Same wire shape, drop-in. Worse on Pidgin but ~3× cheaper.

**Fallback when AI is down:**

Return `502 AI_UNAVAILABLE`. Mobile falls back to client-side
substring matching (the current behavior), so the search bar still
works — just less smart.

**What goes back into the cached jobs list:**

The mobile applies the returned `filters` to the cached
`allJobsProvider` list. No new `/jobs` call is fired by this endpoint.
That means: search feels instant (≤ 50 ms) after the AI parse
completes.

---

# 3. `POST /ai/profile/extract`

**Auto-fill profile from a single sentence.** Replaces the
four-field edit-profile form on first run with a single text box:
*"Tell us about yourself"*.

The current `EditProfileScreen` has separate fields for full name,
primary skill, work radius, etc. For a new worker, this is friction.
This endpoint takes one sentence and returns a partially-filled
profile draft the mobile pre-fills the form with. The worker confirms
or edits; the actual save still flows through `PATCH /me` per
`17_edit_profile.md`.

## Endpoint

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/ai/profile/extract` | Protected |

⚡ Idempotent.

## Request

```json
POST /ai/profile/extract
Authorization: Bearer <access_token>
Content-Type: application/json
Idempotency-Key: <uuid>

{
  "text": "I'm Tunde Adeola, 28, I drive trucks. I stay in Surulere and I'm willing to travel up to 10km."
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `text` | string | yes | 1–500 chars. |

## Response 200

```json
{
  "data": {
    "draft": {
      "name": "Tunde Adeola",
      "primary_skill": "driver",
      "preferred_radius_km": 10,
      "neighborhood": "Surulere"
    },
    "confidence": {
      "name": 0.98,
      "primary_skill": 0.94,
      "preferred_radius_km": 0.91,
      "neighborhood": 0.95
    },
    "unresolved": ["age: 28"]
  },
  "meta": {
    "model": "claude-haiku-4-5",
    "provider": "anthropic",
    "elapsed_ms": 540,
    "cached": false
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `draft.name` | string \| null | Title-cased. |
| `draft.primary_skill` | `JobType` \| null | One of `loader, driver, unloader, general_labor, welder`. Null if the worker named a skill we don't support (welder, painter, plumber → keep going + log; mason, electrician → null + `unresolved`). |
| `draft.preferred_radius_km` | int \| null | Whole km, clamped 1–20 (mirrors the slider's range in `17_edit_profile.md`). |
| `draft.neighborhood` | string \| null | Free-form. **NOT** saved by `PATCH /me` today — it's a hint for the UI to label "Surulele Lagos" in the confirmation step. Future-proofing for an optional `home_neighborhood` field. |
| `confidence.*` | float 0–1 per field | Mobile renders a small ❗ icon next to any field below 0.7 to prompt the worker to double-check. |
| `unresolved` | array of string | Things the worker said that we couldn't map. Surfaced as a one-liner so the worker can edit manually if it matters. |

## Errors

| HTTP | Code | When | Message |
|------|------|------|---------|
| 400 | `TEXT_TOO_LONG` | > 500 chars | "Keep it short — one or two sentences." |
| 400 | `TEXT_TOO_SHORT` | < 10 chars or no extractable signal | "Tell us a bit more — your name, what you do, and where you live." |
| 429 | `RATE_LIMITED` | Over daily quota (20 / day / worker) | "You've tried too many times today. Try filling the form manually." |
| 502 | `AI_UNAVAILABLE` | Vendor 5xx / timeout | "Couldn't process that — fill the form below." |

## Notes for backend

**Provider — Anthropic Haiku 4.5 with structured outputs.**

Same model as `/ai/search/parse`. Same reasoning: cheap, fast,
indistinguishable from Sonnet for an extraction task. Use tool-use
API with a JSON schema matching the `draft` envelope so the model
can't return malformed JSON.

**Prompt:**

```
System: You extract worker profile fields from a single sentence of
self-description, for Nigerian day workers signing up for Forge. Map
their stated job to one of: loader, driver, unloader, general_labor,
welder. If they say a skill outside the list (e.g. "I'm a painter"),
pick the closest match and lower your confidence to 0.5–0.7 — never
fabricate a tighter match. Names: title-case but preserve apostrophes
("O'Neill"). Radius: whole km, clamped 1–20. Neighborhood: just the
neighborhood name, no city. Confidence per field 0–1, reflecting how
explicitly the text supports the value (not your prior). If something
in the text didn't map (age, family status, references), put the raw
phrase in `unresolved`.

User: "<text>"
```

**Why Haiku not Sonnet:**

Profile extraction is closed-domain (4 fields, 5 enum values for one
of them). Haiku scores within 0.5% of Sonnet on this kind of task in
internal evals while costing 1/8th. If a specific worker's draft is
visibly wrong, the user edits it manually — there's no downside to
the cheaper model.

**Quota.**

20 / day / worker. This screen is hit at most twice on a normal
account lifecycle (signup + maybe one edit). 20 covers everything
including the worker re-trying because they typo'd.

**Mobile flow.**

```
EditProfileScreen "First time" variant
   │
   ├── single text field "Tell us about yourself"
   ├── tap "Continue"
   ├── POST /ai/profile/extract
   │     │
   │     ├── 200 → pre-fill the form with the draft, scroll to confirm
   │     └── 4xx/5xx → switch to manual form, surface error message
   ▼
Worker reviews / edits the prefilled fields
   │
   └── tap "Save" → PATCH /me as usual (17_edit_profile.md)
```

The AI extract is a **convenience layer** — every value is editable
before save. The actual write contract is unchanged.

---

# 4. `POST /uploads/liveness` — v2 vision sidecar upgrade

This endpoint already exists (see `23_liveness.md`). This section
documents an **additive** upgrade: alongside Smile Identity's
liveness verdict, run a GPT-4 Vision pass to catch cases Smile's
classifier misses — printed photos held up to the camera, screen
replays, masks. Mobile contract is unchanged; the upgrade is purely
internal except for two new fields in the rejection `details` block.

## What changes

Server-side pipeline (revised):

```
1. Decode + MIME / dimension check         (existing)
2. Smile Identity Smart Selfie call        (existing)
   └─► if Smile rejects → 422 with mapped code (existing)
3. GPT-4 Vision sidecar                    (NEW)
   └─► prompt: "Is this a real person facing the camera, eyes open,
              single face, no screen / printed photo / mask?
              Answer JSON: { live: bool, reason?: string,
              confidence: 0-1 }"
   └─► if vision.live == false AND confidence > 0.85 → 422
            LIVENESS_SPOOF with details.reason from vision
4. Persist + return upload_id              (existing)
```

The order matters: Smile runs first (cheaper + faster + tuned to
African faces). Only its successes go to GPT-4 V. The vision pass is
purely a second opinion — it can downgrade a Smile pass to a reject,
never the reverse.

## Mobile contract delta

Only the rejection `details` block gains optional fields:

```json
{
  "error": {
    "code": "LIVENESS_SPOOF",
    "message": "Hold the phone up and look at the camera — don't take a photo of a photo.",
    "details": {
      "reason": "screen_replay",
      "confidence": 0.91,
      "reviewer": "vision"               // NEW — "smile" or "vision"
    }
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `details.reviewer` | enum string | `"smile"` for rejections caught by Smile Identity, `"vision"` for rejections caught by the GPT-4 V sidecar. Used for fraud analytics; mobile ignores. |

`details.reason` gains additional values when `reviewer == "vision"`:
`screen_replay`, `printed_photo`, `mask`, `obscured_face`, `eyes_closed`.

## Why a second pass

Smile's liveness model is excellent at detecting "this isn't a face"
or "there are 3 faces", and it's tuned for African faces. It's
weaker on high-quality screen replay attacks and on novel spoof
techniques (e.g. paper masks). GPT-4 V is a general visual reasoner —
it spots context Smile's narrower model doesn't (screen bezels, moiré
patterns, paper edges). Belt-and-suspenders. Cost is low because
Smile filters most images out before they reach the vision pass.

## Cost

GPT-4 Vision ~$0.01 per accepted-by-Smile image. Smile rejections
(~30% of attempts) cost zero vision dollars. Net: ~$0.007 per signup
liveness pass on top of Smile's ~$0.05.

## Fallback

If GPT-4 V times out or errors, **trust Smile's verdict and proceed**.
The vision sidecar is opt-in defensive depth — its outage is not a
production outage. Log the timeout for ops.

## Provider notes

- **GPT-4 Vision** via OpenAI Vision API. Pass the JPEG bytes
  directly; don't re-encode.
- Alternative: **Anthropic Claude with vision** (`claude-haiku-4-5`
  also handles images). Drop-in swap if OpenAI gets rate-limited;
  same prompt, same JSON output shape. Slightly cheaper.

Everything else (rate limits, mobile flow, Smile mapping, error copy,
EXIF stripping, audit bucket) is exactly as `23_liveness.md` already
specifies.

---

# 5. `POST /ai/disputes/:id/mediate`

**AI mediator for worker ↔ employer disputes.** Reads the dispute
thread + the underlying job, applies the Forge dispute policy, and
returns a suggested resolution plus pre-drafted messages for both
parties.

When a worker files a complaint (wrong pay, no-show employer, unsafe
site, photos rejected unfairly), an ops human resolves it today. This
endpoint gives ops a starting point: a recommended outcome and the
messages to send. The human still approves and clicks send — the AI
never auto-resolves.

## Endpoint

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/ai/disputes/:id/mediate` | Protected (ops scope) |

⚡ Idempotent. **Ops-only** — workers and employers cannot call this
directly. The dispute thread itself is fetched / created via a
separate `/disputes` API surface (TBD; not covered in this file).

## Request

```json
POST /ai/disputes/dsp_4f81c2/mediate
Authorization: Bearer <ops_token>
Content-Type: application/json
Idempotency-Key: <uuid>

{
  "additional_context": "Worker called support twice; both calls dropped."
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `additional_context` | string | no | Free-form notes from the ops agent — context not visible in the dispute thread. Max 500 chars. |

The server has the full dispute thread, job record, both parties'
history (completion rates, prior disputes), and the Forge policy doc.
None of that ships in the request body.

## Response 200

```json
{
  "data": {
    "verdict": "favor_worker",
    "verdict_confidence": 0.82,
    "rationale": "Employer confirmed the work happened (photos uploaded, geofence matched at clock-out) but underpaid by ₦2,000. Job listing said ₦8,000; payment was ₦6,000. No prior dispute pattern on either side. Standard underpayment resolution applies.",
    "recommended_action": {
      "type": "refund_difference",
      "amount_to_worker": 2000,
      "amount_from_employer": 2000,
      "notes": "Charge employer ₦2,000; credit worker wallet ₦2,000. Mark dispute resolved."
    },
    "draft_message_to_worker": "Hi Tunde — we've reviewed your dispute on the rebar loading job. The listing was ₦8,000 and you only received ₦6,000. We're crediting the ₦2,000 difference to your Forge wallet now. You'll see it within 5 minutes. Sorry for the trouble — thanks for showing up.",
    "draft_message_to_employer": "Hi Adeolu — your worker Tunde flagged that the agreed pay (₦8,000 per your posting) didn't match what was sent (₦6,000). We've refunded the ₦2,000 difference to him from your Forge balance. If this was a posting typo, you can edit pay before publishing next time.",
    "policy_references": [
      "ops_policy_v3#underpayment-clear-evidence",
      "ops_policy_v3#first-offense-no-fee"
    ]
  },
  "meta": {
    "model": "claude-sonnet-4-6",
    "provider": "anthropic",
    "elapsed_ms": 3120,
    "cached": false
  }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `verdict` | enum | `favor_worker` / `favor_employer` / `partial` / `insufficient_evidence`. |
| `verdict_confidence` | float 0–1 | If < 0.6, the UI shows a "human review required" banner. Ops still sees the suggestion. |
| `rationale` | string | One-paragraph explanation. Cites concrete evidence from the thread + records (geofence, clock-out time, prior disputes). |
| `recommended_action.type` | enum | `refund_difference` / `refund_full` / `charge_no_show_fee` / `no_action` / `escalate_to_human`. |
| `recommended_action.amount_to_worker` / `amount_from_employer` | int \| null | Whole Naira. Null if N/A. |
| `recommended_action.notes` | string | Ops instructions in plain language. |
| `draft_message_to_worker` / `draft_message_to_employer` | string \| null | Pre-written. Naija-English register, polite, specific to this case. Null if `type == escalate_to_human`. |
| `policy_references` | array of string | Stable anchors into the Forge ops policy doc. Lets ops verify the AI is applying the right rule. |

## Errors

| HTTP | Code | When |
|------|------|------|
| 403 | `FORBIDDEN` | Caller token doesn't have ops scope |
| 404 | `NOT_FOUND` | `dispute_id` doesn't exist |
| 409 | `CONFLICT` | Dispute already resolved — return the historical resolution, not a new one |
| 429 | `RATE_LIMITED` | 5 / day / dispute (re-mediation by an ops agent who wants a second take) |
| 502 | `AI_UNAVAILABLE` | Anthropic timeout |

## Notes for backend

**Provider — Anthropic Sonnet 4.6.**

This is the one endpoint where Sonnet earns its keep over Haiku:

- Multi-document reasoning (dispute thread + job record + party
  histories + policy doc).
- Stakes are higher — a wrong recommendation gets a worker shortchanged
  or an employer overcharged.
- Latency budget is wider (4 s p95 vs Haiku's 600 ms) because the ops
  agent is reading the suggestion, not the worker.

Use **prompt caching** on the policy doc — it's stable for weeks and
adds maybe 8 K tokens to every request. Cached, it's ~free. See the
`claude-api` skill for the exact `cache_control` block.

**Prompt structure:**

```
System: You are the Forge Disputes mediator. You review labor-marketplace
disputes between Nigerian day workers and small employers, and recommend
a resolution following the Forge ops policy (provided below). Your
recommendation is reviewed by a human ops agent before any action is
taken — be specific about evidence and cite the policy clause you're
applying. Tone in the drafted messages: polite, plain Naija-English,
brief. Don't apologize on behalf of the company unless we're wrong.
Don't promise refunds we won't deliver.

[POLICY DOC, prompt-cached]
Forge Ops Policy v3:
1. Underpayment with clear evidence → refund difference + no fee
   either side (first offense). See "underpayment-clear-evidence".
2. ... [rest of policy doc, ~8 K tokens]

User: Dispute thread:
   [full thread, oldest first]
Job record: [JSON]
Worker history: { completed: 47, disputes_filed: 1, disputes_lost: 0 }
Employer history: { jobs_posted: 142, disputes: 3, disputes_lost: 2 }
Additional ops context: "<additional_context>"
```

**Schema enforcement.**

Use Anthropic tool-use to enforce the response envelope. The verdict
enum is a finite set; never trust free-form output for it.

**Human in the loop — non-negotiable.**

This endpoint NEVER triggers a charge, refund, or message send. Ops
sees the suggestion in the admin dashboard, edits if needed, and
clicks Approve. The Approve action posts to a separate
`/disputes/:id/resolve` endpoint (not in this file). That separation
is on purpose — it keeps the AI on a leash and gives ops auditability.

**Logging.**

For every call log: `dispute_id`, `verdict`, `verdict_confidence`,
`recommended_action`, the human's eventual decision (resolved via
`/disputes/:id/resolve`). Diff between AI recommendation and human
final → feedback loop for prompt iteration.

**When to escalate to human review.**

The model itself can return `verdict: insufficient_evidence` or
`recommended_action.type: escalate_to_human`. Mobile renders the
mediation card with a prominent "Human review needed" banner in those
cases — no drafted messages, just the rationale.

**Cost guardrail.**

5 calls / dispute / day. Most disputes need one mediation; the quota
exists so an ops agent can re-run after adding more `additional_context`
without blowing the budget.

---

## Mobile integration map

| Endpoint | Mobile file(s) it lights up |
|----------|----------------------------|
| `/ai/jobs/:id/summarize` | `lib/features/jobs/widgets/job_card.dart` — render `summary` + `highlights` chips beneath the title. `lib/features/jobs/presentation/job_detail_screen.dart` — show the summary as a hero callout. |
| `/ai/search/parse` (text) | `lib/features/jobs/presentation/jobs_search_screen.dart` — wire to the `onSubmitted` of the text field. |
| `/ai/search/parse` (voice) | `jobs_search_screen.dart` — add a mic IconButton; record m4a via `record` package; POST audio. |
| `/ai/profile/extract` | `lib/features/profile/presentation/edit_profile_screen.dart` — first-run variant with a single text field. |
| `/uploads/liveness` (v2) | `lib/features/auth/presentation/liveness_capture_screen.dart` — no change. New `details.reason` values surface as friendlier error coaching. |
| `/ai/disputes/:id/mediate` | Admin / ops dashboard — out of scope for the worker mobile app. |

## Why we use AI at all

Be honest with the team: every one of these surfaces could ship
without AI. Job cards survive without summaries. Search works as
substring filter. Edit profile is a form. Liveness has Smile.
Disputes have humans.

AI is here because:

1. **Search and onboarding** are accessibility wins for low-literacy
   workers — voice + natural-language extraction are real-world
   differences in who can use the app.
2. **Summaries** raise scan speed on the home tab where every worker
   spends their time. Small UX delta × huge usage = compound.
3. **Liveness vision sidecar** is fraud defense in depth on the one
   endpoint where being wrong costs money.
4. **Dispute mediation** is the only way to scale ops past the first
   thousand workers.

If a surface doesn't earn its cost (each one has telemetry — see
`meta.cached`, `meta.elapsed_ms`, the verdict log on disputes), turn
it off. The mobile contract is built so every AI call has a non-AI
fallback (raw description, substring search, manual form, Smile-only,
fully-human dispute review).
