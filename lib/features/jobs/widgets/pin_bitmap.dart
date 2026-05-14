// `latlong2` re-exports a generic `Path<LatLng>` that shadows
// `dart:ui`'s `Path`. We import `dart:ui` with a prefix so the
// painter can use `ui.Path()` unambiguously — same trick as
// `live_map.dart`.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../core/mock/models.dart';
import 'pin_color.dart';

/// Logical pin size in dp — matches `MarkerLayer`'s marker dimensions
/// in `live_map.dart` (36 × 44) so OSM and Google Maps render pins
/// the same physical size.
const double _pinLogicalWidth = 36;
const double _pinLogicalHeight = 44;

/// Draw the app's custom teardrop pin onto an arbitrary [Canvas].
///
/// Single source of truth — used by `live_map.dart`'s `_PinPainter`
/// (via a thin wrapper) AND by [renderPinBitmap] below to produce the
/// `BitmapDescriptor` images Google Maps consumes. Keeping the
/// drawing code in one place means the two map backends are
/// pixel-identical.
void paintPinTo(
  Canvas canvas, {
  required Size size,
  required Color fill,
  required Color outline,
  required Color shadow,
  required bool focused,
}) {
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

  // White outline ring for crispness against the basemap.
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

/// Renders the pin to a [gmaps.BitmapDescriptor] sized for the device
/// pixel ratio. Result is suitable to pass directly into
/// `gmaps.Marker(icon:)`.
///
/// Anchor returned by [pinAnchor] aligns the tip of the teardrop with
/// the marker's geo coordinate — same alignment OSM gets via
/// `Marker.alignment: Alignment.topCenter` (tip at bottom-center of
/// the widget, which corresponds to anchor `(0.5, 1.0)`).
Future<gmaps.BitmapDescriptor> renderPinBitmap({
  required JobType type,
  required bool focused,
  required Color outline,
  required Color shadow,
  required double devicePixelRatio,
}) async {
  final fill = pinColorFor(type);
  // Render at the DPR so the pin is crisp on high-density screens.
  // Cap at 3 to avoid huge bitmaps on rare ultra-high-DPI panels.
  final dpr = devicePixelRatio.clamp(1.0, 3.0);
  final pxW = (_pinLogicalWidth * dpr).round();
  final pxH = (_pinLogicalHeight * dpr).round();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(dpr);
  paintPinTo(
    canvas,
    size: const Size(_pinLogicalWidth, _pinLogicalHeight),
    fill: fill,
    outline: outline,
    shadow: shadow,
    focused: focused,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(pxW, pxH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (byteData == null) {
    // Shouldn't happen in practice — toByteData on a valid ui.Image
    // always returns bytes. Fall back to Google's red default so the
    // pin is still visible.
    return gmaps.BitmapDescriptor.defaultMarker;
  }
  return gmaps.BitmapDescriptor.bytes(
    byteData.buffer.asUint8List(),
    width: _pinLogicalWidth,
    height: _pinLogicalHeight,
  );
}

/// Tip of the teardrop sits at bottom-center of the bitmap → anchor
/// (0.5, 1.0). Pass this to `gmaps.Marker(anchor:)`.
const ui.Offset pinAnchor = Offset(0.5, 1.0);

// ---------------------------------------------------------------------
// Cache.
//
// Five JobTypes × {focused, not} = 10 unique bitmaps for the whole
// app. We render them lazily once via [warmPinCache] and reuse across
// every marker on every screen. Keeps a 30-pin feed at ~5-10 bitmap
// renders TOTAL, not 30.
// ---------------------------------------------------------------------

class _CacheKey {
  const _CacheKey(this.type, this.focused, this.outline, this.shadow);
  final JobType type;
  final bool focused;
  final Color outline;
  final Color shadow;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.type == type &&
      other.focused == focused &&
      other.outline == outline &&
      other.shadow == shadow;

  @override
  int get hashCode => Object.hash(type, focused, outline, shadow);
}

final Map<_CacheKey, gmaps.BitmapDescriptor> _cache =
    <_CacheKey, gmaps.BitmapDescriptor>{};

/// Pre-renders every (type × focused) combination using the current
/// palette + device pixel ratio. Awaiting this once at map mount means
/// every subsequent `getPinBitmap` call is synchronous and instant —
/// no waterfall of bitmap renders interleaved with the first frame.
Future<void> warmPinCache({
  required Color outline,
  required Color shadow,
  required double devicePixelRatio,
}) async {
  final futures = <Future<void>>[];
  for (final type in JobType.values) {
    for (final focused in const <bool>[false, true]) {
      final key = _CacheKey(type, focused, outline, shadow);
      if (_cache.containsKey(key)) continue;
      futures.add(
        renderPinBitmap(
          type: type,
          focused: focused,
          outline: outline,
          shadow: shadow,
          devicePixelRatio: devicePixelRatio,
        ).then((b) => _cache[key] = b),
      );
    }
  }
  await Future.wait(futures);
}

/// Returns a cached bitmap or null if [warmPinCache] hasn't completed
/// yet for the requested palette. Callers should fall back to a
/// default marker in the null case so the map never renders blank.
gmaps.BitmapDescriptor? getPinBitmap({
  required JobType type,
  required bool focused,
  required Color outline,
  required Color shadow,
}) {
  return _cache[_CacheKey(type, focused, outline, shadow)];
}
