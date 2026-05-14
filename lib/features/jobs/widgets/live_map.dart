// `latlong2` exports a generic `Path<LatLng>` that shadows `dart:ui`'s
// `Path` and breaks the canvas Path API in the marker painter. We
// import `dart:ui` with a prefix so the painter can use `ui.Path()`
// unambiguously.
import 'dart:ui' as ui show Path;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/location/current_location.dart';
import '../../../core/mock/models.dart';
import 'map_view.dart' show MapStyle;
import 'pin_color.dart';

/// Real map tiles via OpenStreetMap.
///
/// Why OSM and not Google Maps:
/// - Zero API-key setup. No vendor lock-in.
/// - Free at scale — no surprise bills as the user base grows.
/// - Production-tested: Komoot, Maps.me, OsmAnd all use OSM tiles.
///
/// Tile source is OSM's canonical tile server. Attribution is required
/// and rendered as a small pill in the bottom-right by flutter_map's
/// [RichAttributionWidget].
///
/// To upgrade the look later (e.g. Apple-Maps-style muted basemap),
/// swap the [_tileUrl] to a Stadia or MapTiler provider — both have
/// generous free tiers but require an API key.
class LiveMap extends ConsumerStatefulWidget {
  const LiveMap({
    super.key,
    required this.jobs,
    this.focusedJobId,
    this.interactive = true,
    this.controller,
    this.onJobTap,
    this.style = MapStyle.light,
  });

  final List<Job> jobs;
  final String? focusedJobId;

  /// When false, gestures are disabled — useful for inline previews
  /// (job-detail snippet) that should not steal scrolls from a parent
  /// list.
  final bool interactive;

  /// External map controller. When provided, the parent owns the
  /// controller and can drive `move()` / `fitCamera()` calls (used by
  /// the home screen's recenter button). When null, the widget owns a
  /// private controller — keeps existing call sites (job detail snippet)
  /// working without any change.
  final MapController? controller;

  /// Fired when a worker taps a job pin. When null, pins are
  /// non-interactive (used by the job-detail snippet where there's
  /// only one pin and tapping it shouldn't navigate anywhere). The
  /// home screen passes a callback that opens the job detail page.
  final ValueChanged<Job>? onJobTap;

  /// Basemap appearance. Switches the tile URL — light = OSM, dark =
  /// CARTO dark_all, satellite = Esri World Imagery. All three are
  /// free / no-key tile sources.
  final MapStyle style;

  @override
  ConsumerState<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends ConsumerState<LiveMap> {
  // Default camera while the GPS round-trip is in flight — country
  // center of Nigeria. Per the location-freeform handoff the old
  // Lagos-bias is wrong now that jobs can be posted anywhere in NG.
  // The map re-centers as soon as `currentLocationProvider` resolves
  // to the worker's real point.
  static const LatLng _nigeriaCenter = LatLng(9.082, 8.6753);
  static const double _nigeriaZoom = 6;

  // Either the externally-supplied controller, or one we create
  // ourselves. `_ownsController` tells dispose whether to clean it up.
  late final MapController _controller =
      widget.controller ?? MapController();
  late final bool _ownsController = widget.controller == null;

  // Tile URLs per [MapStyle]. All three are free / no-key sources.
  //   - light     → canonical OSM tiles
  //   - dark      → CARTO "dark_all" basemap
  //   - satellite → Esri World Imagery photo tiles
  // CARTO and Esri both ask for attribution; we already render an
  // attribution pill at the bottom-right via [RichAttributionWidget].
  static String _tileUrlFor(MapStyle s) {
    switch (s) {
      case MapStyle.light:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapStyle.dark:
        return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
      case MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  /// True once the map has been auto-centered onto the worker's real
  /// location. Guards against repeated `move()` calls that would steal
  /// the camera away from the user's manual pan/zoom.
  bool _autoCentred = false;

  /// Memoised job-marker list. We allocate a fresh `Marker` + `_Pin`
  /// per job only when the underlying jobs list identity OR the
  /// focused id changes — otherwise we reuse the existing list, which
  /// short-circuits `MarkerLayer`'s rebuild path. Critical for jank-
  /// free pans/zooms on feeds with 30+ pins.
  List<Job>? _markersForJobs;
  String? _markersForFocus;
  ValueChanged<Job>? _markersForOnTap;
  List<Marker> _markers = const <Marker>[];

  List<Marker> _buildMarkers() {
    if (identical(_markersForJobs, widget.jobs) &&
        _markersForFocus == widget.focusedJobId &&
        identical(_markersForOnTap, widget.onJobTap)) {
      return _markers;
    }
    _markersForJobs = widget.jobs;
    _markersForFocus = widget.focusedJobId;
    _markersForOnTap = widget.onJobTap;
    _markers = List<Marker>.generate(widget.jobs.length, (int i) {
      final Job j = widget.jobs[i];
      final bool focused = j.id == widget.focusedJobId;
      final Widget pin = _Pin(type: j.type, focused: focused);
      return Marker(
        point: LatLng(j.locationLat, j.locationLng),
        width: 36,
        height: 44,
        alignment: Alignment.topCenter,
        child: widget.onJobTap == null
            ? pin
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onJobTap!(j),
                child: pin,
              ),
      );
    }, growable: false);
    return _markers;
  }

  @override
  void dispose() {
    // Only dispose the controller we created ourselves. If the parent
    // supplied one, the parent is responsible for its lifecycle —
    // disposing it here would crash the parent on its next move() call.
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Move the camera to [point] if we haven't already done so. Called
  /// once per provider resolution, then never again — the user is in
  /// charge of the camera after that.
  void _maybeRecenter(LatLng point) {
    if (_autoCentred) return;
    _autoCentred = true;
    // Defer until after this frame's build so the controller doesn't
    // chase its own rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.move(point, _controller.camera.zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Resolve once per build — when this transitions from null to a
    // real GeoPoint, `_maybeRecenter` snaps the camera over.
    final geoAsync = ref.watch(currentLocationProvider);
    final me = geoAsync.valueOrNull;
    if (me != null) {
      _maybeRecenter(LatLng(me.lat, me.lng));
    }

    return Container(
      // Sit on a flat surface tile so the brief moment before tiles
      // load is the warm surface color rather than stark white.
      color: palette.surfaceContainer,
      child: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          // GPS-null fallback: country center + zoomed-out view so
          // workers anywhere in Nigeria see their region while the
          // GPS round-trip resolves.
          initialCenter:
              me == null ? _nigeriaCenter : LatLng(me.lat, me.lng),
          initialZoom: me == null ? _nigeriaZoom : 14,
          // Lower floor so the user can zoom out to a metro / regional
          // view; ceiling at 18 (street level) — beyond that the OSM
          // tiles would be over-magnified.
          minZoom: 4,
          maxZoom: 18,
          interactionOptions: InteractionOptions(
            // Everything except rotation. `pinchMove` is critical:
            // without it, flutter_map can't track fingers *spreading*
            // properly and zoom-out gestures break.
            flags: widget.interactive
                ? InteractiveFlag.all & ~InteractiveFlag.rotate
                : InteractiveFlag.none,
          ),
          backgroundColor: palette.surfaceContainer,
        ),
        children: <Widget>[
          // 1. Tile layer.
          TileLayer(
            urlTemplate: _tileUrlFor(widget.style),
            // flutter_map's `keyName` is used to invalidate the tile
            // cache when the URL template changes — without it,
            // toggling style would keep the old tiles in memory.
            key: ValueKey<MapStyle>(widget.style),
            userAgentPackageName: 'app.forge.worker',
            // Cache tiles in-memory aggressively so panning feels smooth.
            tileProvider: NetworkTileProvider(),
            // OSM occasionally resets connections under load — swallow the
            // exception so it doesn't spam the debug console. The tile
            // layer auto-retries on the next pan/zoom.
            errorTileCallback: (_, _, _) {},
          ),

          // 2. Job markers. Each pin is colour-coded by job type
          //    (see [pinColorFor]) so workers can scan the map and
          //    spot the kind of work near them at a glance. When the
          //    parent provides [onJobTap], wrap the pin in a
          //    GestureDetector so tapping it opens job detail; when
          //    null the pin stays purely decorative (job-detail
          //    snippet).
          MarkerLayer(markers: _buildMarkers()),

          // 3. "You are here" — Apple-Maps-style blue dot with halo.
          //    Sits ABOVE the job pins so the worker can always
          //    locate themselves.
          if (me != null)
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: LatLng(me.lat, me.lng),
                  width: 28,
                  height: 28,
                  child: const _MeDot(),
                ),
              ],
            ),

          // 4. Attribution — required by OSM's tile usage policy.
          RichAttributionWidget(
            alignment: AttributionAlignment.bottomRight,
            popupBackgroundColor: palette.surface,
            attributions: <SourceAttribution>[
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// "You are here" — pulsing dot inside a translucent halo. Mirrors the
// Apple Maps current-location indicator so the worker has a constant
// visual anchor on the map.
// ---------------------------------------------------------------------

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Pure-blue dot (Apple-style) rather than the brand teal — `me`
    // markers need to read as "my location" universally, not as
    // another job pin.
    const Color blue = Color(0xFF1A73E8);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: blue.withValues(alpha: 0.20),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: blue,
            shape: BoxShape.circle,
            border: Border.all(color: palette.surface, width: 2.5),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Custom pin — matches the app's design language (no Material default
// red drop pin).
// ---------------------------------------------------------------------

class _Pin extends StatelessWidget {
  const _Pin({required this.type, this.focused = false});

  /// The job type this pin represents — drives the fill colour via
  /// [pinColorFor], so workers can scan the map and read "what kind
  /// of work is around me" without tapping each pin.
  final JobType type;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Focused pin keeps its type colour but renders a soft halo via
    // `_PinPainter`. The previous behaviour overrode focused pins to
    // `palette.secondary`, which collided with the per-type palette —
    // a focused loader and a focused driver looked identical.
    final fill = pinColorFor(type);
    return CustomPaint(
      painter: _PinPainter(
        fill: fill,
        outline: palette.surface,
        shadow: palette.shadow,
        focused: focused,
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({
    required this.fill,
    required this.outline,
    required this.shadow,
    required this.focused,
  });

  final Color fill;
  final Color outline;
  final Color shadow;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tip = Offset(w / 2, h);
    final headRadius = w * 0.42;
    final headCenter = Offset(w / 2, headRadius + 2);

    // Soft halo behind the focused pin so it reads as selected.
    if (focused) {
      canvas.drawCircle(
        headCenter,
        headRadius * 1.7,
        Paint()
          ..color = fill.withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, headRadius * 0.55),
      );
    }

    // Shadow under the tip.
    canvas.drawCircle(
      tip.translate(0, -2),
      headRadius * 0.36,
      Paint()
        ..color = shadow.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, headRadius * 0.30),
    );

    // Pin body — teardrop.
    final body = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx - headRadius * 1.15,
        tip.dy - h * 0.45,
        headCenter.dx - headRadius,
        headCenter.dy,
      )
      ..arcToPoint(
        Offset(headCenter.dx + headRadius, headCenter.dy),
        radius: Radius.circular(headRadius),
        clockwise: true,
      )
      ..quadraticBezierTo(
        tip.dx + headRadius * 1.15,
        tip.dy - h * 0.45,
        tip.dx,
        tip.dy,
      )
      ..close();

    // 1px white outline ring for crispness against the basemap.
    canvas.drawPath(
      body,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawPath(body, Paint()..color = fill);

    // Inner dot — gives the pin presence at small sizes.
    canvas.drawCircle(
      headCenter,
      headRadius * 0.34,
      Paint()..color = outline,
    );
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) =>
      old.fill != fill || old.focused != focused;
}

