# Earnings Home — Wallet & Stats

Covers `lib/features/earnings/presentation/earnings_screen.dart`.

The home screen shows: **wallet balance** (hero), **stats row** (this week / month / all time), **recent 10 transactions** (preview, tap "View all" → `09_transactions.md`).

The wallet balance and "all time" stat both come from the worker record (`16_profile.md`). The "this week" / "this month" tiles are computed client-side from the transactions list — no extra endpoint needed. The `transactions` endpoint must therefore include enough history to compute a month at minimum.

## Endpoints

This screen reuses:

- `GET /me` (see `16_profile.md`) — for `wallet_balance` and `total_earned`.
- `GET /transactions?limit=30` (see `09_transactions.md`) — first page is enough to populate "this week / this month" + the recent-10 preview.

No dedicated endpoint. **Do not** invent a `/earnings/summary` aggregate — the existing two calls are cached, fast, and the math is trivial on-device.

## Notes for backend

- Make sure `GET /me` returns `wallet_balance` consistently with the latest disbursement. If a clock-out just succeeded, `GET /me` called immediately after must reflect the new balance — don't return stale cache from a read replica.
