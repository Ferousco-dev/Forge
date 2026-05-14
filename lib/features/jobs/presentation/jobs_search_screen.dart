import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/ai/ai_models.dart';
import '../../../core/ai/ai_state.dart';
import '../../../core/location/current_location.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../widgets/job_card.dart';

/// Full-screen search over the entire jobs catalog.
///
/// Reads from [allJobsProvider] (unbounded radius) — search means
/// "find any job in the country", not just what's near me. The home
/// sheet still uses [nearbyJobsProvider] for the nearby feed; the two
/// are intentionally split so the home view stays focused on
/// commutable work while search lets workers discover anywhere.
///
/// Filtering is client-side over the in-memory list; once the backend
/// grows a dedicated `/jobs/search?q=...` endpoint we can swap the
/// body without changing this screen.
///
/// Matches against `title`, `description`, `employer.name`,
/// `locationAddress`, and the localised `JobType.label`.
class JobsSearchScreen extends ConsumerStatefulWidget {
  const JobsSearchScreen({super.key});

  @override
  ConsumerState<JobsSearchScreen> createState() => _JobsSearchScreenState();
}

/// Pre-computed lowercase haystack per job. Avoids repeating
/// `.toLowerCase()` on the same fields for every keystroke.
class _SearchIndex {
  _SearchIndex(this.job, this.haystack);
  final Job job;
  final String haystack;
}

class _JobsSearchScreenState extends ConsumerState<JobsSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  // Query lives in a ValueNotifier so the search bar (which contains
  // the keyboard target) and the results pane don't rebuild each
  // other on every keystroke.
  final ValueNotifier<String> _query = ValueNotifier<String>('');
  Timer? _debounce;

  /// AI-parsed structured filters layered on top of the substring
  /// query. Null when no AI parse has run for the current input.
  final ValueNotifier<SearchParseResult?> _aiResult =
      ValueNotifier<SearchParseResult?>(null);

  /// True while a text/voice parse is in flight. Drives a small
  /// shimmer / spinner on the search bar; never blocks typing.
  final ValueNotifier<bool> _aiBusy = ValueNotifier<bool>(false);

  // Memoised lowercase index. Rebuilt only when the underlying job
  // list identity changes.
  List<Job>? _indexedFor;
  List<_SearchIndex> _index = const <_SearchIndex>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _query.dispose();
    _aiResult.dispose();
    _aiBusy.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    // 120ms is below the perception threshold for "instant" but high
    // enough to skip mid-burst keystrokes during fast typing.
    _debounce = Timer(const Duration(milliseconds: 120), () {
      _query.value = v;
    });
    // Editing invalidates any prior AI parse — the structured filters
    // were derived from a different query.
    if (_aiResult.value != null) _aiResult.value = null;
  }

  void _onClear() {
    _debounce?.cancel();
    _controller.clear();
    _query.value = '';
    _aiResult.value = null;
    _focus.requestFocus();
  }

  /// Fired on the keyboard's "Search" action. Calls `/ai/search/parse`
  /// in text mode and applies the structured filters on top of the
  /// existing substring match. Soft-fails — on any error we leave the
  /// existing substring-only behavior in place.
  Future<void> _onSubmitted(String v) async {
    final query = v.trim();
    if (query.isEmpty) return;
    _aiBusy.value = true;
    try {
      final location = ref.read(currentLocationProvider).valueOrNull;
      final repo = ref.read(aiRepositoryProvider);
      final result = await repo.parseSearchText(
        text: query,
        workerLat: location?.lat,
        workerLng: location?.lng,
        now: DateTime.now(),
      );
      if (!mounted) return;
      _aiResult.value = result;
    } catch (_) {
      // 502 AI_UNAVAILABLE or any other error → keep the substring
      // search alive. The bar still works, just less smart.
    } finally {
      if (mounted) _aiBusy.value = false;
    }
  }

  Future<void> _openVoiceSearch() async {
    // Voice search is temporarily disabled while the `record` package's
    // platform-interface versions stabilize upstream. The text-mode AI
    // parse (Enter to submit) covers the same surface.
    final palette = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        backgroundColor: palette.surfaceContainerHigh,
        content: Text(
          'Voice search is coming soon. Type your search and press '
          'enter — it understands plain English.',
          style: TextStyle(color: palette.onSurface),
        ),
      ));
  }

  void _clearAiFilters() {
    _aiResult.value = null;
  }

  List<_SearchIndex> _indexFor(List<Job> jobs) {
    if (identical(_indexedFor, jobs)) return _index;
    _indexedFor = jobs;
    _index = List<_SearchIndex>.generate(jobs.length, (int i) {
      final Job j = jobs[i];
      final String h =
          '${j.title}${j.description}${j.employer.name}'
          '${j.locationAddress}${j.type.label}'
              .toLowerCase();
      return _SearchIndex(j, h);
    }, growable: false);
    return _index;
  }

  /// Apply (a) substring match (legacy behavior) plus (b) any AI-derived
  /// structured filters (types / pay / start window / near radius)
  /// layered on top. AI filters are AND-combined with the substring
  /// match — the worker explicitly asked for both. If [ai] is null, this
  /// behaves exactly like the pre-AI version.
  List<Job> _filter(List<_SearchIndex> idx, String q, SearchParseResult? ai) {
    final query = q.trim().toLowerCase();
    final SearchFilters? f = ai?.filters;
    final bool hasQuery = query.isNotEmpty;
    final bool hasAi = f != null && !f.isEmpty;
    if (!hasQuery && !hasAi) return const <Job>[];

    final List<Job> out = <Job>[];
    for (int i = 0; i < idx.length; i++) {
      final entry = idx[i];
      if (hasQuery && !entry.haystack.contains(query)) continue;
      if (hasAi && !_passesAiFilters(entry.job, f)) continue;
      out.add(entry.job);
    }
    return out;
  }

  bool _passesAiFilters(Job job, SearchFilters f) {
    if (f.types.isNotEmpty && !f.types.contains(job.type)) return false;
    if (f.minPay != null && job.payAmount < f.minPay!) return false;
    if (f.maxPay != null && job.payAmount > f.maxPay!) return false;
    if (f.startAfter != null &&
        job.startTime.isBefore(f.startAfter!.toUtc())) {
      return false;
    }
    if (f.startBefore != null &&
        job.startTime.isAfter(f.startBefore!.toUtc())) {
      return false;
    }
    final SearchNear? near = f.near;
    if (near != null) {
      final distKm = _haversineKm(
        job.locationLat,
        job.locationLng,
        near.lat,
        near.lng,
      );
      if (distKm > near.radiusKm) return false;
    }
    if (f.keywords.isNotEmpty) {
      final hay = '${job.title} ${job.description} ${job.locationAddress}'
          .toLowerCase();
      for (final kw in f.keywords) {
        if (!hay.contains(kw.toLowerCase())) return false;
      }
    }
    return true;
  }

  /// Quick & dirty great-circle distance in km. Used only for the
  /// AI-resolved "near X" radius filter — order-of-magnitude accuracy
  /// is plenty.
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadiusKm = 6371.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return earthRadiusKm * c;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final jobsAsync = ref.watch(allJobsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: palette.brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: palette.surface,
        // Let Scaffold resize naturally when the keyboard appears —
        // this gives the smoothest 1:1 animation between keyboard and
        // body. Manual viewInsets handling was producing two competing
        // animations that fought each other.
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _SearchBar(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
                onSubmitted: _onSubmitted,
                onClear: _onClear,
                onBack: () => context.pop(),
                onMic: _openVoiceSearch,
                busy: _aiBusy,
              ),
              // AI-resolved filter chips — only shown when an AI parse
              // has produced structured filters worth highlighting.
              ValueListenableBuilder<SearchParseResult?>(
                valueListenable: _aiResult,
                builder: (_, SearchParseResult? ai, _) {
                  if (ai == null || ai.filters.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _AiFilterChips(
                    result: ai,
                    onClear: _clearAiFilters,
                  );
                },
              ),
              Expanded(
                child: jobsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (Object err, StackTrace st) {
                    debugPrint('[jobs_search] allJobsProvider error: $err\n$st');
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              "Couldn't load jobs.",
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: palette.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (kDebugMode)
                              Text(
                                '$err',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: palette.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: AppSpacing.md),
                            TextButton(
                              onPressed: () =>
                                  ref.invalidate(allJobsProvider),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  data: (List<Job> jobs) {
                    final List<_SearchIndex> idx = _indexFor(jobs);
                    return ValueListenableBuilder<String>(
                      valueListenable: _query,
                      builder: (_, String q, _) {
                        if (q.trim().isEmpty) {
                          return _SearchHints(
                            onTypeTap: (String label) {
                              _controller.text = label;
                              _controller.selection =
                                  TextSelection.collapsed(
                                offset: label.length,
                              );
                              _query.value = label;
                            },
                          );
                        }
                        return ValueListenableBuilder<SearchParseResult?>(
                          valueListenable: _aiResult,
                          builder: (_, SearchParseResult? ai, _) {
                            final results = _filter(idx, q, ai);
                            if (results.isEmpty) {
                              return _NoResults(query: q);
                            }
                            return _Results(
                              jobs: results,
                              onTap: (Job j) => context.push(
                                RoutePaths.jobDetail(j.id),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onBack,
    required this.onMic,
    required this.busy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback onMic;
  final ValueListenable<bool> busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: palette.onSurface,
            tooltip: 'Back',
          ),
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: palette.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: palette.outline, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  // Search icon ↔ inline spinner while AI parse is in
                  // flight. ValueListenable so we don't rebuild the
                  // whole bar on every keystroke.
                  ValueListenableBuilder<bool>(
                    valueListenable: busy,
                    builder: (_, bool isBusy, _) {
                      if (isBusy) {
                        return SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.primary,
                          ),
                        );
                      }
                      return Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: palette.onSurfaceVariant,
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textInputAction: TextInputAction.search,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: palette.onSurface,
                      ),
                      cursorColor: palette.primary,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search or speak — try "driver near Ikeja"',
                        hintStyle: AppTextStyles.bodyLarge.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: onClear,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // Voice search trigger — AI mic. Always visible so
                  // the affordance is discoverable.
                  GestureDetector(
                    onTap: onMic,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.mic_rounded,
                        size: 20,
                        color: palette.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Empty (pre-typing) state — quick-pick chips for the 5 job types
// ---------------------------------------------------------------------

class _SearchHints extends StatelessWidget {
  const _SearchHints({required this.onTypeTap});
  final ValueChanged<String> onTypeTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: <Widget>[
        Text(
          'Browse by type',
          style: AppTextStyles.labelSmall.copyWith(
            color: palette.onSurfaceVariant,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: JobType.values.map((JobType t) {
            return _HintChip(
              label: '${t.emoji}  ${t.label}',
              onTap: () => onTypeTap(t.label),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: palette.outline, width: 1),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------

class _Results extends StatelessWidget {
  const _Results({required this.jobs, required this.onTap});
  final List<Job> jobs;
  final void Function(Job) onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, int i) => JobCard(
        job: jobs[i],
        onTap: () => onTap(jobs[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// No results
// ---------------------------------------------------------------------

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EmptyStateView(
      title: 'No jobs match "$query"',
      subtitle:
          'Try a shorter word, a different job type, or check back '
          'in a few minutes — new jobs are posted throughout the day.',
      illustration: Icon(
        Icons.search_off_rounded,
        size: 56,
        color: palette.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// AI filter chip row — surfaces the structured filters the parser
// extracted ("Driver", "near Ikeja · 5km", "tomorrow morning") so the
// worker can see WHY their results changed and dismiss with one tap.
// ---------------------------------------------------------------------

class _AiFilterChips extends StatelessWidget {
  const _AiFilterChips({required this.result, required this.onClear});

  final SearchParseResult result;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chips = _describe(result.filters);
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.auto_awesome_rounded,
            size: 14,
            color: palette.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      c,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: palette.onSurfaceVariant,
            tooltip: 'Clear smart filters',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  /// Pretty-print the structured filter into 1–4 short chip labels.
  /// Order is deliberate: type → place → time → pay → keywords.
  static List<String> _describe(SearchFilters f) {
    final List<String> out = <String>[];
    if (f.types.isNotEmpty) {
      out.add(f.types.map((t) => t.label).join(' · '));
    }
    if (f.near != null) {
      out.add('near ${f.near!.label} · ${f.near!.radiusKm.toInt()}km');
    }
    final start = f.startAfter;
    final end = f.startBefore;
    if (start != null || end != null) {
      out.add(_describeWindow(start, end));
    }
    if (f.minPay != null || f.maxPay != null) {
      final min = f.minPay;
      final max = f.maxPay;
      if (min != null && max != null) {
        out.add('₦$min–₦$max');
      } else if (min != null) {
        out.add('≥ ₦$min');
      } else if (max != null) {
        out.add('≤ ₦$max');
      }
    }
    for (final k in f.keywords) {
      if (k.trim().isEmpty) continue;
      out.add('"$k"');
    }
    return out;
  }

  static String _describeWindow(DateTime? start, DateTime? end) {
    String hhmm(DateTime d) {
      final local = d.toLocal();
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (start != null && end != null) return '${hhmm(start)}–${hhmm(end)}';
    if (start != null) return 'from ${hhmm(start)}';
    return 'by ${hhmm(end!)}';
  }
}
