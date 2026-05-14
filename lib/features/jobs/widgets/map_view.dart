import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/location/current_location.dart';
import '../../../core/mock/models.dart';
import 'live_map.dart';
import 'pin_bitmap.dart';

// ---------------------------------------------------------------------
// Map provider switch.
//
// Default: Google Maps (richer basemap, native tile cache, faster
// pan/zoom on mid-range Android). API key lives in the platform
// manifests (Android: AndroidManifest.xml meta-data; iOS:
// AppDelegate.swift via GMSServices.provideAPIKey). Flip this to
// `false` to fall back to the OpenStreetMap implementation if the
// key is revoked, quota is exceeded, or the worker is in an area
// where Google Maps has poor coverage. The OSM impl is a fully
// functional drop-in — the contract is the same.
// ---------------------------------------------------------------------
const bool useGoogleMaps = true;

// ---------------------------------------------------------------------
// Public controller. Wraps either Google Maps' async controller or
// flutter_map's synchronous one behind a tiny surface — `move()` and
// `currentZoom`. The home screen's recenter button uses these two
// methods, nothing else.
// ---------------------------------------------------------------------

abstract class AppMapController {
  /// Drop a pin (figuratively) at the given coords with the requested
  /// zoom. Returns immediately; the camera animates on its own
  /// (Google) or jumps (OSM) on the next frame.
  Future<void> move(double lat, double lng, double zoom);

  /// Current zoom level. Used by the recenter button to decide
  /// whether to snap to street zoom or preserve the user's current
  /// zoom if they've already zoomed in past it. Returns `null` when
  /// the controller hasn't been attached to a map yet.
  double? get currentZoom;

  /// Implementations must clean up any underlying controller they
  /// allocated themselves.
  void dispose();

  /// Factory. Returns whichever flavour matches [useGoogleMaps].
  factory AppMapController() =>
      useGoogleMaps ? _GoogleAppMapController() : _OsmAppMapController();
}

class _OsmAppMapController implements AppMapController {
  _OsmAppMapController() : controller = fm.MapController();
  final fm.MapController controller;

  @override
  Future<void> move(double lat, double lng, double zoom) async {
    controller.move(ll.LatLng(lat, lng), zoom);
  }

  @override
  double? get currentZoom {
    try {
      return controller.camera.zoom;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() => controller.dispose();
}

class _GoogleAppMapController implements AppMapController {
  final Completer<gmaps.GoogleMapController> _completer =
      Completer<gmaps.GoogleMapController>();
  double? _lastZoom;

  // The map widget calls this once on creation.
  void _attach(gmaps.GoogleMapController controller) {
    if (!_completer.isCompleted) _completer.complete(controller);
  }

  void _setZoom(double zoom) => _lastZoom = zoom;

  @override
  Future<void> move(double lat, double lng, double zoom) async {
    final c = await _completer.future;
    await c.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(lat, lng), zoom),
    );
    _lastZoom = zoom;
  }

  @override
  double? get currentZoom => _lastZoom;

  @override
  void dispose() {
    // Google's controller is owned by the platform view; we don't
    // call dispose on it. We only drop our local references.
  }
}

// ---------------------------------------------------------------------
// Map style toggle.
//
//   - `light`     → default Google basemap (roads + landmarks, warm
//                   neutral palette). On OSM: the canonical tile.
//   - `dark`      → muted dark basemap. On Google: applied via the
//                   `_kDarkMapStyle` JSON below. On OSM: CARTO's free
//                   "dark_all" tile server.
//   - `satellite` → photographic basemap. On Google: built-in
//                   `MapType.hybrid` (satellite + road labels). On
//                   OSM: Esri's free "World_Imagery" service.
// ---------------------------------------------------------------------

enum MapStyle { light, dark, satellite }

/// Public widget.
class MapView extends ConsumerStatefulWidget {
  const MapView({
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
  final bool interactive;
  final AppMapController? controller;
  final ValueChanged<Job>? onJobTap;
  final MapStyle style;

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  @override
  Widget build(BuildContext context) {
    if (useGoogleMaps) {
      return _GoogleMapView(
        jobs: widget.jobs,
        focusedJobId: widget.focusedJobId,
        interactive: widget.interactive,
        controller: widget.controller is _GoogleAppMapController
            ? widget.controller! as _GoogleAppMapController
            : null,
        onJobTap: widget.onJobTap,
        style: widget.style,
      );
    }
    // OSM fallback — reuses the existing, battle-tested LiveMap.
    return LiveMap(
      jobs: widget.jobs,
      focusedJobId: widget.focusedJobId,
      interactive: widget.interactive,
      controller: widget.controller is _OsmAppMapController
          ? (widget.controller! as _OsmAppMapController).controller
          : null,
      onJobTap: widget.onJobTap,
      style: widget.style,
    );
  }
}

// ---------------------------------------------------------------------
// Google Maps implementation.
// ---------------------------------------------------------------------

class _GoogleMapView extends ConsumerStatefulWidget {
  const _GoogleMapView({
    required this.jobs,
    required this.focusedJobId,
    required this.interactive,
    required this.controller,
    required this.onJobTap,
    required this.style,
  });

  final List<Job> jobs;
  final String? focusedJobId;
  final bool interactive;
  final _GoogleAppMapController? controller;
  final ValueChanged<Job>? onJobTap;
  final MapStyle style;

  @override
  ConsumerState<_GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends ConsumerState<_GoogleMapView> {
  /// Default camera target when GPS hasn't resolved yet (or the
  /// worker hasn't granted permission). Country center of Nigeria —
  /// per the location-freeform handoff, Lagos-bias is wrong now that
  /// jobs can be posted anywhere in NG. The wider initial zoom (6)
  /// lets an Abuja / Kano / Port-Harcourt worker see their region
  /// while GPS lights up.
  static const gmaps.LatLng _nigeriaCenter = gmaps.LatLng(9.082, 8.6753);
  static const double _nigeriaZoom = 6;

  bool _autoCentred = false;
  gmaps.GoogleMapController? _gmapsController;

  /// True once [warmPinCache] has finished for the current palette.
  /// Until then markers use Google's default red marker as a
  /// placeholder so the map never renders empty. As soon as the
  /// custom bitmaps land we invalidate the memoised marker set so
  /// they swap in on the next frame.
  bool _pinsReady = false;

  /// Last palette we warmed against. When the theme changes (light ↔
  /// dark) we re-warm so the white outline / shadow colour matches.
  Color? _warmedOutline;
  Color? _warmedShadow;

  // Memoised marker set — same pattern as the OSM impl. Allocate
  // Markers only when jobs identity OR focused id changes.
  List<Job>? _markersForJobs;
  String? _markersForFocus;
  bool _markersForPinsReady = false;
  Set<gmaps.Marker> _markers = const <gmaps.Marker>{};

  Future<void> _ensurePinCache(AppColors palette) async {
    if (_warmedOutline == palette.surface && _warmedShadow == palette.shadow) {
      return;
    }
    _warmedOutline = palette.surface;
    _warmedShadow = palette.shadow;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    await warmPinCache(
      outline: palette.surface,
      shadow: palette.shadow,
      devicePixelRatio: dpr,
    );
    if (!mounted) return;
    setState(() => _pinsReady = true);
  }

  Set<gmaps.Marker> _buildMarkers() {
    if (identical(_markersForJobs, widget.jobs) &&
        _markersForFocus == widget.focusedJobId &&
        _markersForPinsReady == _pinsReady) {
      return _markers;
    }
    _markersForJobs = widget.jobs;
    _markersForFocus = widget.focusedJobId;
    _markersForPinsReady = _pinsReady;
    final outline = _warmedOutline;
    final shadow = _warmedShadow;
    _markers = <gmaps.Marker>{
      for (final Job j in widget.jobs)
        () {
          final bool focused = j.id == widget.focusedJobId;
          // Custom bitmap if the cache is warm; default red marker
          // as a placeholder during the brief first-warm window.
          final gmaps.BitmapDescriptor icon = (outline != null && shadow != null)
              ? (getPinBitmap(
                    type: j.type,
                    focused: focused,
                    outline: outline,
                    shadow: shadow,
                  ) ??
                  gmaps.BitmapDescriptor.defaultMarker)
              : gmaps.BitmapDescriptor.defaultMarker;
          return gmaps.Marker(
            markerId: gmaps.MarkerId(j.id),
            position: gmaps.LatLng(j.locationLat, j.locationLng),
            icon: icon,
            anchor: pinAnchor,
            consumeTapEvents: widget.onJobTap != null,
            onTap: widget.onJobTap == null
                ? null
                : () => widget.onJobTap!(j),
          );
        }(),
    };
    return _markers;
  }

  void _onMapCreated(gmaps.GoogleMapController controller) {
    _gmapsController = controller;
    widget.controller?._attach(controller);
    // Diagnostic — should print exactly once per map mount. If you
    // never see this line, the platform view didn't initialize at
    // all (manifest issue). If you see it but the map stays white,
    // the SDK couldn't fetch tiles (billing / SDK enablement / key
    // restriction issue on the Google Cloud project).
    debugPrint('[map_view] GoogleMapController attached');
  }

  void _onCameraMove(gmaps.CameraPosition pos) {
    widget.controller?._setZoom(pos.zoom);
  }

  /// Google map type for the current style. Light & dark both use
  /// `normal` (dark differs only in the style JSON we pass down
  /// below); satellite uses `hybrid` (satellite tiles + road labels).
  gmaps.MapType get _mapType {
    switch (widget.style) {
      case MapStyle.light:
      case MapStyle.dark:
        return gmaps.MapType.normal;
      case MapStyle.satellite:
        return gmaps.MapType.hybrid;
    }
  }

  /// Style JSON for the current style. `null` for light & satellite
  /// (Google's defaults); a hand-tuned muted palette for dark.
  String? get _styleJson {
    switch (widget.style) {
      case MapStyle.light:
      case MapStyle.satellite:
        return null;
      case MapStyle.dark:
        return _kDarkMapStyle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Kick off the bitmap cache warm on the first build, and again
    // if the palette (light/dark) changes. The future is intentionally
    // unawaited — markers render with the default red pin until the
    // bitmaps land, then `setState(_pinsReady = true)` swaps them in.
    _ensurePinCache(palette);

    final geoAsync = ref.watch(currentLocationProvider);
    final me = geoAsync.valueOrNull;

    // First-time auto-recenter — once GPS resolves, jump the camera
    // to the worker's real location. After that the user is in
    // charge of the camera.
    if (me != null && !_autoCentred) {
      _autoCentred = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gmapsController?.animateCamera(
          gmaps.CameraUpdate.newLatLngZoom(
            gmaps.LatLng(me.lat, me.lng),
            14,
          ),
        );
      });
    }

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        // When GPS hasn't resolved we open zoomed out on Nigeria so
        // workers anywhere in the country see their region. Once
        // `currentLocationProvider` resolves, `_autoCentred` jumps
        // the camera to the worker's real point at street zoom.
        target: me == null ? _nigeriaCenter : gmaps.LatLng(me.lat, me.lng),
        zoom: me == null ? _nigeriaZoom : 14,
      ),
      onMapCreated: _onMapCreated,
      onCameraMove: _onCameraMove,
      markers: _buildMarkers(),
      mapType: _mapType,
      // Style JSON re-applied declaratively on every rebuild — the
      // plugin diffs internally, so switching styles is a single
      // PlatformView round-trip.
      style: _styleJson,
      // We render our own "me" affordance via the worker's GPS dot
      // elsewhere; keeping the default Google "my location" blue dot
      // on for visual parity with native maps.
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      // Hybrid traffic/POI density off — keeps the look closer to
      // the OSM impl's calm basemap.
      trafficEnabled: false,
      buildingsEnabled: false,
    );
  }
}

// ---------------------------------------------------------------------
// Dark map style JSON.
//
// Hand-tuned muted dark palette — charcoal land, deep teal-grey water,
// dimmed roads, low-contrast labels. Designed to feel on-brand rather
// than the harsh generic black-and-blue Google sometimes ships as the
// "Night" preset. Applied via `GoogleMap.style` so the plugin diffs
// internally and the switch is one PlatformView round-trip.
//
// JSON sourced from https://mapstyle.withgoogle.com/ "Night" preset
// with these adjustments: water → deeper teal-grey, road geometry
// brightened one step so navigation context isn't lost, POI/transit
// labels dimmed to reduce visual noise.
// ---------------------------------------------------------------------

const String _kDarkMapStyle = r'''
[
  {"elementType":"geometry","stylers":[{"color":"#1a1d22"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8f96"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1d22"}]},
  {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#3a3f47"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#a1a7af"}]},
  {"featureType":"administrative.neighborhood","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.province","elementType":"geometry.stroke","stylers":[{"color":"#2c3138"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#5e636b"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1f2a25"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#5a7a6a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c3138"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#34393f"}]},
  {"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#9aa0a8"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c4148"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#23272c"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b1b6bd"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#7a7f86"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#5e636b"}]},
  {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#272b30"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#2c3138"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1c24"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3a5a6a"}]}
]
''';
