/// Static content surfaced on the splash screen — rotating Naija
/// motivational quotes and trust-building featured stats.
///
/// Kept const so the lists live in code-segment memory; no allocation
/// per cold start. Pick functions are deterministic per UTC day for
/// the quote (so a returning user sees the same one until tomorrow)
/// and random per run for the stat (variety on each launch).
library;

import 'dart:math';

/// Short, encouraging, Naija-flavored lines. Keep each under ~50 chars
/// so they fit on small phones without truncation.
const List<String> kNaijaQuotes = <String>[
  'E go work — let\'s go.',
  'Today\'s hustle, tomorrow\'s house.',
  'No be by luck. Na by show up.',
  'Small small, na im dey reach far.',
  'Hard work pays. We see you.',
  'One job today, one step closer.',
  'You no come this far to come only this far.',
  'Wetin you dey find dey find you too.',
  'Steady. The bag dey come.',
  'Make today count.',
];

/// Trust-building stats. Numbers are demo-grade — wire to a real
/// `/stats` endpoint when the backend ships one. Keep each line
/// short and visually similar in length so the cross-fade lands
/// without layout jumps.
const List<String> kFeaturedStats = <String>[
  '₦127M paid out this month',
  '3,420 workers placed this week',
  '8,400 workers trust us across Nigeria',
  '94% of jobs filled within 24 hours',
  '₦2.4B paid out to workers all-time',
  'Average wait time: 6 minutes',
];

/// Loading status snippets. Cycled one-by-one while the splash dwells.
/// Order is deliberate — most-relevant first ("jobs") since that's the
/// landing tab.
const List<String> kLoadingStatus = <String>[
  'Finding jobs near you…',
  'Checking your wallet…',
  'Looking for matches…',
  'Tuning your feed…',
];

/// Pick today's quote — stable per UTC day so the same user sees the
/// same line on multiple cold starts in one day, then it changes.
/// Stable selection avoids the "I just opened the app twice and got
/// two different quotes" feeling, which reads as chaotic.
String quoteForToday([DateTime? now]) {
  final DateTime today = (now ?? DateTime.now()).toUtc();
  // Days since epoch — small int, wraps to a stable index.
  final int dayIndex =
      today.difference(DateTime.utc(2024, 1, 1)).inDays;
  return kNaijaQuotes[dayIndex.abs() % kNaijaQuotes.length];
}

/// Pick a random stat for this app run. We rotate per launch (not per
/// day) so frequent users still see variety.
String randomStat([Random? rng]) {
  final r = rng ?? Random();
  return kFeaturedStats[r.nextInt(kFeaturedStats.length)];
}

/// Time-aware greeting prefix. Localizable later via `intl`.
String greetingForHour(int hour24) {
  if (hour24 < 12) return 'Good morning';
  if (hour24 < 17) return 'Good afternoon';
  return 'Good evening';
}
