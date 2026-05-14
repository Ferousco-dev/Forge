# Work History

Covers `lib/features/profile/presentation/work_history_screen.dart`. Read-only chronology of completed jobs — the worker's portfolio.

## Endpoints

This screen reuses `06_my_applications.md` with `bucket=history`. **No new endpoint needed.**

The mobile renders the same items differently — emphasizing pay total, employer, and date — but the data shape is identical.

## Notes for backend

- If the product team later wants per-job rating, photo proof, or earnings sub-breakdown shown on this screen, expose `GET /me/work-history` with a richer shape. Until then, don't fan out the API surface.
- Make sure `06_my_applications.md`'s history bucket sorts by `completed_at DESC` — mobile relies on this for the timeline.
