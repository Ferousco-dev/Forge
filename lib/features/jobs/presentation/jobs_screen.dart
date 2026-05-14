import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/location/current_location.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_state_view.dart';
import '../../../shared/widgets/network_image_with_fallback.dart';
import '../../work/state/work_session_controller.dart';
import '../widgets/job_card.dart';
import '../widgets/map_view.dart';
import '../widgets/map_vignette.dart';

/// First letter of [name], uppercased, with a safe fallback when
/// the name is null or empty. `String.substring(0, 1)` throws on the
/// empty string, so a worker whose `/me` payload arrives with an empty
/// `name` (mid-onboarding, briefly) would otherwise crash the home
/// shell. `'W'` for "worker" is the catch-all.
String _initialOf(String? name) {
  if (name == null || name.isEmpty) return 'W';
  return name.characters.first.toUpperCase();
}

/// Human-readable "X mins" / "1h 12m" for the active-session and
/// scheduled-job countdowns. Returns "less than a minute" when the
/// remaining duration is below 60 s so the card doesn't flicker on
/// "0 minutes" right before the gate flips.
String _humanRemaining(Duration d) {
  if (d.isNegative || d == Duration.zero) return 'now';
  if (d.inMinutes < 1) return 'less than a minute';
  if (d.inHours < 1) {
    final m = d.inMinutes;
    return '$m ${m == 1 ? 'min' : 'mins'}';
  }
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (m == 0) return '$h ${h == 1 ? 'hour' : 'hours'}';
  return '${h}h ${m}m';
}

/// Active filter applied on top of the nearby-jobs feed.
enum _JobsFilter {
  all('All', null),
  loader('Loader', JobType.loader),
  driver('Driver', JobType.driver),
  unloader('Unloader', JobType.unloader),
  bestPay('Best pay', null);

  const _JobsFilter(this.label, this.type);
  final String label;
  final JobType? type;
}

/// Home — Jobs.
///
/// Composition:
/// - Map runs ambient behind everything.
/// - A frosted [_FrostedHeader] floats at top, opacity adapts to sheet
///   position so it reads cleanly over both map and full sheet.
/// - A [DraggableScrollableSheet] holds the entire jobs experience.
///   No mode toggle — drag is the mode.
/// - Sheet content (peek → full):
///     1. Drag handle
///     2. Hero — "Good morning, Tunde" + total Naira value of jobs in
///        reach (the moment)
///     3. Active-session card *inside the sheet* when one exists
///     4. Pinned filter chips
///     5. Featured job card (full-rich JobCard variant) — best pay
///     6. The rest of the jobs as full JobCards
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen>
    with WidgetsBindingObserver {
  static const double _peek = 0.36;
  static const double _min = 0.20;
  static const double _max = 0.95;

  /// Cadence for the silent background refresh of the jobs feed.
  /// 40s is the sweet spot — frequent enough that a fresh posting lands
  /// before the worker scrolls away, infrequent enough that we're not
  /// hammering the backend or burning radio battery on a screen the
  /// user may be staring at for minutes.
  ///
  /// The refresh goes through `ref.invalidate(...)` rather than a
  /// dedicated polling provider so the AsyncValue keeps the previous
  /// list cached. With `AsyncValue.when`'s default
  /// `skipLoadingOnRefresh: true`, the data branch keeps rendering the
  /// previous jobs while the new fetch is in flight — no skeleton
  /// flash, no scroll position reset, no "loading…" badge.
  static const Duration _silentRefreshInterval = Duration(seconds: 40);

  /// Drives [_silentRefreshInterval] while the screen is mounted and
  /// the app is foregrounded. Cancelled on background to avoid
  /// network/CPU cost when the user isn't looking, and on dispose to
  /// avoid leaks. We never `await` the refresh — Riverpod handles the
  /// fetch lifecycle and we have no UI to update synchronously.
  Timer? _silentRefreshTicker;

  final DraggableScrollableController _sheet = DraggableScrollableController();

  // Owned by this state and shared with both [MapView] (so it can pan
  // around) and [_RecenterButton] (so tapping the button can snap the
  // camera back to the worker's current GPS). Disposed below.
  //
  // `AppMapController` is the provider-agnostic facade — internally
  // it wraps Google Maps' async controller or flutter_map's
  // synchronous one based on the `useGoogleMaps` flag in
  // `map_view.dart`.
  final AppMapController _mapController = AppMapController();

  _JobsFilter _filter = _JobsFilter.all;

  /// Worker-selected basemap appearance. Light by default; the user
  /// can switch to dark or satellite via the style picker overlaid
  /// on the map (see [_MapStyleButton]).
  MapStyle _mapStyle = MapStyle.light;

  // Sheet drag position is a ValueNotifier (not setState) so only the
  // two widgets that depend on it — the frosted header and the
  // recenter-button opacity — repaint during a drag. Using setState
  // here would rebuild the entire screen (including the map and the
  // sheet's child) on every drag pixel, which is the cause of the
  // visible lag while dragging the sheet up over the map.
  late final ValueNotifier<double> _sheetSize = ValueNotifier<double>(_peek);

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onSheetChanged);
    WidgetsBinding.instance.addObserver(this);
    _startSilentRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSilentRefresh();
    _sheet.removeListener(_onSheetChanged);
    _sheet.dispose();
    _sheetSize.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startSilentRefresh();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopSilentRefresh();
    }
  }

  void _startSilentRefresh() {
    _silentRefreshTicker?.cancel();
    _silentRefreshTicker =
        Timer.periodic(_silentRefreshInterval, (_) => _silentRefresh());
  }

  void _stopSilentRefresh() {
    _silentRefreshTicker?.cancel();
    _silentRefreshTicker = null;
  }

  /// Silent re-fetch of the two job feeds.
  ///
  /// Deliberately does NOT invalidate `currentLocationProvider` — that
  /// would force a GPS re-acquire on every tick, which both wakes the
  /// radio and (briefly) re-renders the map to the new fix. The
  /// 40s background refresh is for new postings, not for location
  /// drift; the user's pull-to-refresh and recenter button cover that.
  ///
  /// `ref.invalidate` is fire-and-forget: Riverpod re-runs the provider,
  /// the AsyncValue keeps its previous data exposed via `.value`, and
  /// `.when(skipLoadingOnRefresh: true)` (Riverpod 2.x default) means
  /// the data branch keeps rendering the old list while the new one
  /// fetches. No skeleton flash, no scroll reset.
  void _silentRefresh() {
    if (!mounted) return;
    ref.invalidate(nearbyJobsProvider);
    ref.invalidate(allJobsProvider);
  }

  void _onSheetChanged() {
    if (!mounted || !_sheet.isAttached) return;
    _sheetSize.value = _sheet.size;
  }

  /// Recenter button hides as the sheet covers the map.
  static double _recenterOpacityFor(double size) {
    final raw = (1 - (size - 0.55) / 0.20).clamp(0.0, 1.0);
    return Curves.easeOut.transform(raw);
  }

  List<Job> _applyFilter(List<Job> jobs) {
    Iterable<Job> source = jobs;
    if (_filter.type != null) {
      source = source.where((Job j) => j.type == _filter.type);
    }
    final list = source.toList();
    if (_filter == _JobsFilter.bestPay) {
      list.sort((Job a, Job b) => b.payAmount.compareTo(a.payAmount));
    }
    return list;
  }

  Future<void> _refresh() async {
    // Re-resolve GPS first so a moved worker (or a newly-granted
    // location permission) immediately gets jobs at their real
    // coordinates. Then invalidate both feeds — nearby drives the
    // sheet, allJobs drives the map.
    ref.invalidate(currentLocationProvider);
    ref.invalidate(nearbyJobsProvider);
    ref.invalidate(allJobsProvider);
    await Future.wait(<Future<Object?>>[
      ref.read(nearbyJobsProvider.future),
      ref.read(allJobsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mediaTopPadding = MediaQuery.paddingOf(context).top;
    // The sheet still shows commutable work — `nearbyJobsProvider` is
    // capped at the backend's 25 km radius.
    final jobsAsync = ref.watch(nearbyJobsProvider);
    // The MAP shows the full catalogue so workers can see every active
    // posting in the country (and tap one to open its detail). Far
    // pins just sit off-screen until the user pans / zooms out — no
    // visual clutter at city zoom.
    final mapJobsAsync = ref.watch(allJobsProvider);
    // The active-session card on the home sheet shows the most
    // attention-worthy in-flight session. The "View all active jobs"
    // link sits underneath when the worker has more than one job in
    // flight (e.g. one awaiting employer confirmation, another freshly
    // accepted).
    final session = ref.watch(primaryWorkSessionProvider);
    final allActive = ref.watch(activeWorkSessionsProvider);
    final activeCount = allActive.length;

    return Scaffold(
      backgroundColor: palette.surface,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: <Widget>[
          // 1. Map (ambient).
          //
          // We always render [LiveMap] — even during loading and even
          // when the unbounded `allJobsProvider` errors. Previously the
          // map fell through to a blank coloured container in those
          // states, which looked like "the map is broken." Now:
          //   * Loading → LiveMap with `jobs: []`. Tiles still render,
          //     basemap is fully visible, pins appear when data lands.
          //   * Error on `allJobsProvider` (e.g. backend tightens the
          //     `/jobs` validation) → fall back to nearby jobs so the
          //     map at least matches what the sheet already shows.
          //   * Both error → empty pin list. Still a real map.
          Positioned.fill(
            child: Builder(
              builder: (BuildContext _) {
                final List<Job> mapJobs = mapJobsAsync.maybeWhen(
                  data: (List<Job> j) => j,
                  orElse: () => jobsAsync.valueOrNull ?? const <Job>[],
                );
                // Pin the highest-paying job on the map. Best "where
                // should I head?" signal at a glance. Single O(n) pass
                // — no list copy, no sort.
                String? focusedId;
                if (mapJobs.isNotEmpty) {
                  Job best = mapJobs.first;
                  for (int i = 1; i < mapJobs.length; i++) {
                    final Job j = mapJobs[i];
                    if (j.payAmount > best.payAmount) best = j;
                  }
                  focusedId = best.id;
                }
                if (mapJobsAsync.hasError) {
                  // Surface the actual cause to the console so we can
                  // diagnose backend validation regressions without
                  // staring at a blank map.
                  debugPrint('[jobs_screen] allJobsProvider error: '
                      '${mapJobsAsync.error}');
                }
                return MapView(
                  jobs: mapJobs,
                  focusedJobId: focusedId,
                  controller: _mapController,
                  style: _mapStyle,
                  onJobTap: (Job j) =>
                      context.push(RoutePaths.jobDetail(j.id)),
                );
              },
            ),
          ),

          // 2. Vignette — softens the map's edges.
          const Positioned.fill(child: MapVignette()),

          // 3. The sheet.
          DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: _peek,
            minChildSize: _min,
            maxChildSize: _max,
            snap: true,
            snapSizes: const <double>[_min, _peek, _max],
            builder: (BuildContext context, ScrollController controller) {
              return _HomeSheet(
                scrollController: controller,
                jobsAsync: jobsAsync,
                applyFilter: _applyFilter,
                activeFilter: _filter,
                onFilterChanged: (_JobsFilter f) => setState(() => _filter = f),
                onRefresh: _refresh,
                onJobTap: (Job j) => context.push(RoutePaths.jobDetail(j.id)),
                session: session,
                activeSessionCount: activeCount,
              );
            },
          ),

          // 4. Recenter button + style picker — anchored top-right of
          //    visible map. Wrapped in a ValueListenableBuilder so
          //    dragging the sheet only repaints this small subtree,
          //    not the screen.
          Positioned(
            right: AppSpacing.lg,
            top: mediaTopPadding + 60 + AppSpacing.sm + 4,
            child: RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _sheetSize,
                builder: (BuildContext context, double size, Widget? child) {
                  final opacity = _recenterOpacityFor(size);
                  return IgnorePointer(
                    ignoring: opacity < 0.05,
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _RecenterButton(controller: _mapController),
                    const SizedBox(height: AppSpacing.sm),
                    _MapStyleButton(
                      current: _mapStyle,
                      onChanged: (MapStyle s) =>
                          setState(() => _mapStyle = s),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Sticky frosted header. The expensive parts (BackdropFilter,
          //    ref.watch, icon row) live in a stable child built ONCE;
          //    only the tint/hairline overlay rebuilds on drag.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FrostedHeader(sheetSize: _sheetSize),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Frosted header
// ---------------------------------------------------------------------

/// 0..1. Drives the frosted header's solidness. Eased so the
/// transition feels confident rather than linear-creeping.
double _solidnessFor(double size) {
  const double peek = _JobsScreenState._peek;
  const double max = _JobsScreenState._max;
  final raw = ((size - peek) / (max - peek)).clamp(0.0, 1.0);
  return Curves.easeInCubic.transform(raw);
}

class _FrostedHeader extends ConsumerWidget {
  const _FrostedHeader({required this.sheetSize});
  final ValueListenable<double> sheetSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);
    final hasActiveSession =
        ref.watch(primaryWorkSessionProvider) != null;

    // Built ONCE. The expensive bits live here and don't re-run on
    // sheet drag.
    final Widget rowContent = SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _LocationBadge(palette: palette),
                ),
              ),
              const _HeaderIcon(
                icon: Icons.search_rounded,
                tooltip: 'Search jobs',
                route: RoutePaths.jobsSearch,
              ),
              const SizedBox(width: AppSpacing.xs),
              const _HeaderIcon(
                icon: Icons.notifications_outlined,
                tooltip: 'Notifications',
                route: RoutePaths.profileNotifications,
              ),
              const SizedBox(width: AppSpacing.sm),
              _AvatarButton(
                workerAsync: workerAsync,
                hasActiveSession: hasActiveSession,
                onTap: () => context.go(RoutePaths.profile),
              ),
            ],
          ),
        ),
      ),
    );

    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          // Sigma 8 is perceptually indistinguishable from 10 here but
          // ~30% cheaper to rasterise per frame.
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: ValueListenableBuilder<double>(
            valueListenable: sheetSize,
            // Only this tiny builder runs on drag — the rowContent
            // child is reused via the `child` slot.
            builder: (BuildContext _, double size, Widget? child) {
              final double solidness = _solidnessFor(size);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface
                      .withValues(alpha: 0.55 + 0.40 * solidness),
                  border: Border(
                    bottom: BorderSide(
                      color:
                          palette.outline.withValues(alpha: solidness),
                      width: 0.5,
                    ),
                  ),
                ),
                child: child,
              );
            },
            child: rowContent,
          ),
        ),
      ),
    );
  }
}

class _LocationBadge extends ConsumerWidget {
  const _LocationBadge({required this.palette});
  final dynamic palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelAsync = ref.watch(currentLocationLabelProvider);
    final label = labelAsync.when(
      data: (l) => l,
      loading: () => 'Loading...',
      error: (_, _) => 'Nigeria',
    );
    return RepaintBoundary(
      child: _LocationBadgeContent(label: label),
    );
  }
}

class _LocationBadgeContent extends StatelessWidget {
  const _LocationBadgeContent({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: palette.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderIcon extends ConsumerWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.route,
  });

  final IconData icon;
  final String tooltip;
  final String route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push(route),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22, color: palette.onSurface),
          ),
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.workerAsync,
    required this.hasActiveSession,
    required this.onTap,
  });

  final AsyncValue<Worker> workerAsync;
  final bool hasActiveSession;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          NetworkImageWithFallback(
            imageUrl: workerAsync.valueOrNull?.photoUrl,
            size: 36,
            // `?.name` short-circuits on null but NOT on empty string —
            // `"".substring(0, 1)` throws RangeError. Guard against
            // both null and empty so freshly-signed-up workers (whose
            // name is briefly empty before /me resolves) don't crash
            // the home shell.
            fallbackInitial: _initialOf(workerAsync.valueOrNull?.name),
          ),
          if (hasActiveSession)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: palette.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Recenter button
// ---------------------------------------------------------------------

class _RecenterButton extends ConsumerWidget {
  const _RecenterButton({required this.controller});

  /// Map controller owned by [_JobsScreenState]. We call `move()` on
  /// it so the camera snaps back to the worker's current GPS point.
  /// Backend-agnostic — works on both Google Maps and OSM.
  final AppMapController controller;

  /// Zoom level the camera snaps to on recenter. Matches the map's
  /// `initialZoom` so the recenter motion feels like "go home" rather
  /// than "zoom in further". If the user has already zoomed in past
  /// this level we preserve their zoom — see [_targetZoom].
  static const double _streetZoom = 15;

  double _targetZoom() {
    final current = controller.currentZoom;
    if (current == null) return _streetZoom;
    // If the user is already zoomed in further than street level,
    // respect that. If they're zoomed way out, snap to street level
    // so the recenter actually feels useful.
    return current > _streetZoom ? current : _streetZoom;
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final geo = await ref.read(currentLocationProvider.future);
      await controller.move(geo.lat, geo.lng, _targetZoom());
    } catch (e) {
      // GPS denied, GPS off, or location provider blew up.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Turn on location to recenter the map.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainer,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: palette.shadow.withValues(alpha: 0.10),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _onTap(context, ref),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Tooltip(
            message: 'Recenter',
            child: Icon(
              Icons.my_location_rounded,
              size: 18,
              color: palette.primary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Map style picker — small floating button under the recenter button.
// Tapping cycles through light → dark → satellite. Showing all three
// states as separate buttons would add too much visual weight to the
// map overlay; cycling keeps the affordance to a single round target.
// ---------------------------------------------------------------------

class _MapStyleButton extends StatelessWidget {
  const _MapStyleButton({required this.current, required this.onChanged});

  final MapStyle current;
  final ValueChanged<MapStyle> onChanged;

  IconData get _icon {
    switch (current) {
      case MapStyle.light:
        return Icons.light_mode_outlined;
      case MapStyle.dark:
        return Icons.dark_mode_outlined;
      case MapStyle.satellite:
        return Icons.public_outlined;
    }
  }

  String get _tooltip {
    switch (current) {
      case MapStyle.light:
        return 'Light map · tap for dark';
      case MapStyle.dark:
        return 'Dark map · tap for satellite';
      case MapStyle.satellite:
        return 'Satellite · tap for light';
    }
  }

  MapStyle get _next {
    switch (current) {
      case MapStyle.light:
        return MapStyle.dark;
      case MapStyle.dark:
        return MapStyle.satellite;
      case MapStyle.satellite:
        return MapStyle.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainer,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onChanged(_next),
        child: Tooltip(
          message: _tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              _icon,
              size: 20,
              color: palette.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------

class _HomeSheet extends ConsumerWidget {
  const _HomeSheet({
    required this.scrollController,
    required this.jobsAsync,
    required this.applyFilter,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onJobTap,
    required this.session,
    required this.activeSessionCount,
  });

  final ScrollController scrollController;
  final AsyncValue<List<Job>> jobsAsync;
  final List<Job> Function(List<Job>) applyFilter;
  final _JobsFilter activeFilter;
  final ValueChanged<_JobsFilter> onFilterChanged;
  final Future<void> Function() onRefresh;
  final void Function(Job) onJobTap;
  final WorkSession? session;

  /// Total number of in-flight sessions. Drives the "View all (N)"
  /// link that sits under [_ActiveSessionCard] when the worker has
  /// more than one job in flight.
  final int activeSessionCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final workerAsync = ref.watch(currentWorkerProvider);
    final firstName = workerAsync.valueOrNull?.name.split(' ').first ?? 'there';

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl + 4),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl + 4),
        ),
        child: jobsAsync.when(
          loading: () => _SheetScaffold(
            scrollController: scrollController,
            slivers: <Widget>[
              const SliverToBoxAdapter(child: _DragHandle()),
              SliverToBoxAdapter(
                child: _Hero(name: firstName, count: null, totalValue: null),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterDelegate(
                  active: activeFilter,
                  onChanged: onFilterChanged,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.md),
                      child: JobCardSkeleton(),
                    ),
                    childCount: 4,
                  ),
                ),
              ),
            ],
          ),
          error: (Object _, StackTrace _) => _SheetScaffold(
            scrollController: scrollController,
            slivers: <Widget>[
              const SliverToBoxAdapter(child: _DragHandle()),
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorStateView(
                  title: "Couldn't load jobs",
                  message: 'Pull down to try again, or tap retry below.',
                  onRetry: onRefresh,
                ),
              ),
            ],
          ),
          data: (List<Job> all) {
            final jobs = applyFilter(all);
            // Single pass: compute total pay AND best-paying job.
            int totalValue = 0;
            int bestIdx = 0;
            int bestPay = jobs.isEmpty ? 0 : jobs.first.payAmount;
            for (int i = 0; i < jobs.length; i++) {
              final int p = jobs[i].payAmount;
              totalValue += p;
              if (p > bestPay) {
                bestPay = p;
                bestIdx = i;
              }
            }
            if (jobs.isEmpty) {
              return _SheetScaffold(
                scrollController: scrollController,
                slivers: <Widget>[
                  const SliverToBoxAdapter(child: _DragHandle()),
                  SliverToBoxAdapter(
                    child: _Hero(name: firstName, count: 0, totalValue: 0),
                  ),
                  if (session != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _ActiveSessionStack(
                          primary: session!,
                          totalCount: activeSessionCount,
                        ),
                      ),
                    ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _FilterDelegate(
                      active: activeFilter,
                      onChanged: onFilterChanged,
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      filtered: activeFilter != _JobsFilter.all,
                      onRefresh: onRefresh,
                    ),
                  ),
                ],
              );
            }
            // Featured job: highest pay (whichever filter is active).
            // Already located via the single-pass scan above.
            final Job hero = jobs[bestIdx];
            final List<Job> rest = List<Job>.generate(
              jobs.length - 1,
              (int i) => i < bestIdx ? jobs[i] : jobs[i + 1],
              growable: false,
            );

            return _SheetScaffold(
              scrollController: scrollController,
              slivers: <Widget>[
                const SliverToBoxAdapter(child: _DragHandle()),
                SliverToBoxAdapter(
                  child: _Hero(
                    name: firstName,
                    count: jobs.length,
                    totalValue: totalValue,
                  ),
                ),
                if (session != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _ActiveSessionStack(
                        primary: session!,
                        totalCount: activeSessionCount,
                      ),
                    ),
                  ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FilterDelegate(
                    active: activeFilter,
                    onChanged: onFilterChanged,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      label: hero.payAmount > 8000
                          ? 'Best pay'
                          : 'Best match',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: JobCard(job: hero, onTap: () => onJobTap(hero)),
                  ),
                ),
                if (rest.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SectionHeader(label: 'More nearby'),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  sliver: SliverList.separated(
                    itemCount: rest.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (BuildContext context, int i) {
                      final j = rest[i];
                      return JobCard(job: j, onTap: () => onJobTap(j));
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SheetScaffold extends ConsumerWidget {
  const _SheetScaffold({required this.scrollController, required this.slivers});

  final ScrollController scrollController;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(currentLocationProvider);
        ref.invalidate(nearbyJobsProvider);
        ref.invalidate(allJobsProvider);
        await Future.wait(<Future<Object?>>[
          ref.read(nearbyJobsProvider.future),
          ref.read(allJobsProvider.future),
        ]);
      },
      edgeOffset: 12,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: slivers,
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm + 2),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: palette.outline,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Hero — greeting + total Naira value (the moment)
// ---------------------------------------------------------------------

class _Hero extends ConsumerStatefulWidget {
  const _Hero({
    required this.name,
    required this.count,
    required this.totalValue,
  });

  final String name;
  final int? count;
  final int? totalValue;

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  /// Hoisted to avoid re-parsing the en_NG currency ICU pattern on
  /// every Hero rebuild. The Hero rebuilds frequently (any update to
  /// the cached jobs feed or the worker session triggers a parent
  /// rebuild), so this saves real allocation churn.
  static final NumberFormat _ngnFormatter = NumberFormat.currency(
    locale: 'en_NG',
    symbol: '₦',
    decimalDigits: 0,
  );

  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      ref.invalidate(currentLocationProvider);
      ref.invalidate(nearbyJobsProvider);
      ref.invalidate(allJobsProvider);
      await Future.wait(<Future<Object?>>[
        ref.read(nearbyJobsProvider.future),
        ref.read(allJobsProvider.future),
      ]);
    } catch (_) {
      // The list-error state surfaces the actual reason; this button
      // just needs to stop spinning.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final greeting = _greetingPrefix();

    final headline = widget.totalValue == null
        ? 'Finding jobs near you…'
        : widget.count == 0
        ? 'No jobs near you right now'
        : '${_ngnFormatter.format(widget.totalValue)} in reach';

    final caption = widget.totalValue == null
        ? null
        : widget.count == 0
        ? 'Tap refresh to look again, or expand your work radius.'
        : '${widget.count} ${widget.count == 1 ? 'job' : 'jobs'} '
              'within your work radius today.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Greeting row — name on the left, refresh button on the
          // right. Refresh re-fetches `nearbyJobsProvider`; the rest
          // of the feed (and the map, and any AI summary cache) is
          // intentionally NOT invalidated — this button is the user's
          // "have any new jobs landed near me?" affordance, not a
          // nuclear reset.
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$greeting, ${widget.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _MyApplicationsIconButton(
                onTap: () =>
                    context.push(RoutePaths.profileApplications),
              ),
              const SizedBox(width: AppSpacing.xs),
              _RefreshIconButton(
                refreshing: _refreshing,
                onTap: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.displaySmall.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              caption,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _greetingPrefix() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// Compact round refresh button shown to the right of the greeting.
/// Spins while a refresh is in flight; ignores taps until done.
class _RefreshIconButton extends StatelessWidget {
  const _RefreshIconButton({
    required this.refreshing,
    required this.onTap,
  });

  final bool refreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainer,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: refreshing ? null : onTap,
        child: Tooltip(
          message: 'Refresh jobs',
          child: SizedBox(
            width: 36,
            height: 36,
            child: refreshing
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: palette.onSurface,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Round shortcut to the worker's applications list. Same shape and
/// surface as [_RefreshIconButton] so the two read as a paired control
/// next to the greeting.
class _MyApplicationsIconButton extends StatelessWidget {
  const _MyApplicationsIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceContainer,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: 'My applications',
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.assignment_outlined,
              size: 18,
              color: palette.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// In-sheet active-session card
// ---------------------------------------------------------------------

/// Renders the primary session card plus a "View all active jobs (N)"
/// link when the worker has more than one job in flight. Splitting
/// this out keeps `_ActiveSessionCard` focused on a single session.
class _ActiveSessionStack extends StatelessWidget {
  const _ActiveSessionStack({
    required this.primary,
    required this.totalCount,
  });

  final WorkSession primary;

  /// Total in-flight sessions, including [primary]. The link only
  /// renders when this is > 1.
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ActiveSessionCard(session: primary),
        if (totalCount > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton.icon(
              onPressed: () => context.push(RoutePaths.activeJobs),
              style: TextButton.styleFrom(
                foregroundColor: palette.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
              ),
              icon: const Icon(Icons.dynamic_feed_rounded, size: 16),
              label: Text(
                'View all active jobs ($totalCount)',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActiveSessionCard extends StatefulWidget {
  const _ActiveSessionCard({required this.session});
  final WorkSession session;

  @override
  State<_ActiveSessionCard> createState() => _ActiveSessionCardState();
}

class _ActiveSessionCardState extends State<_ActiveSessionCard>
    with WidgetsBindingObserver {
  Timer? _ticker;
  bool _isVisible = true;
  // Ticks once per second. Listened to ONLY by the elapsed-time Text,
  // so the rest of the card (icons, chip, employer name) doesn't
  // rebuild every second.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    if (widget.session.phase == WorkPhase.working &&
        widget.session.clockedInAt != null &&
        _isVisible) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) _tick.value++;
      });
    }
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isVisible = true;
        _startTimer();
      case AppLifecycleState.paused:
        _isVisible = false;
        _stopTimer();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _tick.dispose();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:${two(d.inMinutes.remainder(60))}'
          ':${two(d.inSeconds.remainder(60))}';
    }
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = widget.session;
    final job = session.job;

    // For not-yet-started jobs (accepted OR already moved to arriving)
    // the detail line and chip switch to a countdown so the worker
    // isn't told to "head to site" for a job that begins in an hour.
    final Duration timeToStart =
        job.startTime.toLocal().difference(DateTime.now());
    final bool scheduledAhead = timeToStart > const Duration(minutes: 10);

    final (String chip, String detail, Color tint) = switch (session.phase) {
      WorkPhase.accepted when scheduledAhead => (
        'Scheduled',
        'Starts in ${_humanRemaining(timeToStart)}',
        palette.info,
      ),
      WorkPhase.arriving when scheduledAhead => (
        'Scheduled',
        'Starts in ${_humanRemaining(timeToStart)}',
        palette.info,
      ),
      WorkPhase.accepted => (
        'Accepted',
        'Tap to head to the site',
        palette.info,
      ),
      WorkPhase.arriving => (
        'Heading to site',
        job.locationAddress,
        palette.info,
      ),
      WorkPhase.working => (
        'On the clock',
        // Placeholder — actual ticking text is rendered via
        // ValueListenableBuilder below so only the Text rebuilds,
        // not the whole card.
        '',
        palette.success,
      ),
      WorkPhase.reviewing => (
        'Reviewing photo',
        'Submit your work to get paid',
        palette.warning,
      ),
      WorkPhase.submitting => (
        'Submitting…',
        "Don't close the app",
        palette.warning,
      ),
      WorkPhase.pendingReview => (
        'Awaiting confirmation',
        'Payment lands automatically when the timer ends',
        palette.warning,
      ),
      WorkPhase.done => ('Job complete', 'Tap for receipt', palette.success),
    };

    // Phase-tinted *surface* card. Apple Calendar / Apple Mail status
    // pattern — calm, contextual, no aggressive contrast. The tint
    // reads as a state cue without shouting.
    return Material(
      color: tint.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: () => _resumeRoute(context, session),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: tint.withValues(alpha: 0.20), width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: _PulseDot(color: tint, size: 10),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            chip,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: tint,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      job.employer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (session.phase == WorkPhase.working &&
                        session.clockedInAt != null)
                      ValueListenableBuilder<int>(
                        valueListenable: _tick,
                        builder: (_, _, _) {
                          return Text(
                            _formatElapsed(
                              DateTime.now().difference(session.clockedInAt!),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.onSurfaceVariant,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          );
                        },
                      )
                    else
                      Text(
                        session.phase == WorkPhase.working
                            ? 'Working now'
                            : detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.onSurfaceVariant,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resumeRoute(BuildContext context, WorkSession s) {
    final id = s.job.id;
    switch (s.phase) {
      case WorkPhase.accepted:
        context.push(RoutePaths.jobStatus(id));
      case WorkPhase.arriving:
        context.push(RoutePaths.jobClockIn(id));
      case WorkPhase.working:
        context.push(RoutePaths.jobInProgress(id));
      case WorkPhase.reviewing:
        // If a photo was captured the worker should land back on the
        // review screen to confirm/submit. If they cancelled the camera
        // (photoCaptured == false but phase already advanced) send them
        // to the camera so they can actually take the shot — otherwise
        // they bounce straight back here.
        if (s.photoCaptured) {
          context.push(RoutePaths.jobClockOutReview(id));
        } else {
          context.push(RoutePaths.jobClockOutCamera(id));
        }
      case WorkPhase.submitting:
        context.push(RoutePaths.jobClockOutSubmitting(id));
      case WorkPhase.pendingReview:
        context.push(RoutePaths.jobClockOutPending(id));
      case WorkPhase.done:
        context.push(RoutePaths.jobClockOutComplete(id));
    }
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    // Inherited widgets (MediaQuery, Theme, etc.) are NOT safe to read
    // here — see `didChangeDependencies` below, where the framework
    // guarantees they're ready. Reading `MediaQuery.maybeOf(context)`
    // in initState throws an assertion (issue this fix addresses).
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pick up the user's "Reduce Motion" accessibility setting, and
    // react if it changes at runtime (toggle in Settings, system
    // accessibility shortcut, etc.).
    final reduce =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      _controller.stop();
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Don't fight the user's accessibility preference on resume.
        if (!_reduceMotion) _controller.repeat(reverse: true);
      case AppLifecycleState.paused:
        _controller.stop();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final t = _controller.value;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.65 + 0.35 * t),
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.30 * t),
                  blurRadius: 4,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: palette.onSurfaceVariant,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pinned filter chips
// ---------------------------------------------------------------------

class _FilterDelegate extends SliverPersistentHeaderDelegate {
  _FilterDelegate({required this.active, required this.onChanged});

  final _JobsFilter active;
  final ValueChanged<_JobsFilter> onChanged;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = context.palette;
    final scrolled = shrinkOffset > 0 || overlapsContent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(
            color: palette.outlineVariant.withValues(
              alpha: scrolled ? 1.0 : 0.0,
            ),
            width: 0.5,
          ),
        ),
      ),
      child: Center(
        child: SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: _JobsFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (BuildContext context, int i) {
              final f = _JobsFilter.values[i];
              return AppChip(
                label: f.label,
                selected: f == active,
                onTap: () => onChanged(f),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterDelegate old) => old.active != active;
}

// ---------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onRefresh});

  final bool filtered;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: EmptyStateView(
        title: filtered
            ? 'No jobs match this filter'
            : 'No jobs near you yet',
        subtitle: filtered
            ? 'Try a different filter or tap refresh.'
            : 'Tap refresh to look again, expand your work radius from '
                'your profile, or check back later — new jobs are posted '
                'throughout the day.',
        illustration: Icon(
          Icons.work_off_outlined,
          size: 56,
          color: palette.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        action: AppTextButton(label: 'Refresh', onPressed: onRefresh),
      ),
    );
  }
}
