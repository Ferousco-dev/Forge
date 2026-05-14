import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Worker's current geo coordinate. The jobs feed query, clock-in
/// geofence, and any "near me" surface read from this provider.
@immutable
class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

/// Raised when the device location cannot be resolved (permission
/// denied, services disabled, or the platform call threw). Callers
/// — chiefly the jobs feed — should surface a "turn on location"
/// state instead of silently querying around a fake coordinate.
class LocationUnavailableException implements Exception {
  const LocationUnavailableException(this.reason);
  final String reason;

  @override
  String toString() => 'LocationUnavailableException: $reason';
}

/// Current device location.
///
/// Resolves real GPS coordinates only. If permission is denied or the
/// platform throws, this provider errors with [LocationUnavailableException]
/// — there is no Lagos (or any other) fallback. The jobs feed (and
/// anything else that watches this) must show an explicit "enable
/// location" state rather than fetching against a coordinate the user
/// is not actually at.
final FutureProvider<GeoPoint>
currentLocationProvider = FutureProvider<GeoPoint>((Ref ref) async {
  LocationPermission permission = await Geolocator.checkPermission();
  debugPrint('[Location] Permission status: $permission');

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    debugPrint('[Location] After request: $permission');
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    debugPrint('[Location] Permission denied — no fallback, surfacing error');
    throw const LocationUnavailableException('permission_denied');
  }

  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    debugPrint('[Location] Services disabled — no fallback, surfacing error');
    throw const LocationUnavailableException('services_disabled');
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    ),
  );

  debugPrint(
    '[Location] Got real position: ${position.latitude}, ${position.longitude}',
  );
  return GeoPoint(lat: position.latitude, lng: position.longitude);
});

// ---------------------------------------------------------------------
// City label
// ---------------------------------------------------------------------

/// Known Nigerian city centroids. The header label maps the worker's
/// `GeoPoint` to the nearest entry (great-circle distance) so it reads
/// as a real place, not as "Lagos · Nigeria" hardcoded.
///
/// Expanded coverage to include major cities across all regions of Nigeria
/// to ensure most locations are within 50 km of a known city.
const List<({String name, double lat, double lng})> _cities =
    <({String name, double lat, double lng})>[
      // Lagos & Southwest
      (name: 'Lagos', lat: 6.5244, lng: 3.3792),
      (name: 'Ikeja', lat: 6.5954, lng: 3.3370),
      (name: 'Lekki', lat: 6.4347, lng: 3.5419),
      (name: 'Apapa', lat: 6.4474, lng: 3.3611),
      (name: 'Surulere', lat: 6.4998, lng: 3.3553),
      (name: 'Abeokuta', lat: 6.7881, lng: 3.3435),
      (name: 'Ibadan', lat: 7.3775, lng: 3.9470),
      (name: 'Ilorin', lat: 8.4955, lng: 4.5478),
      (name: 'Ife', lat: 7.4945, lng: 4.5597),
      (name: 'Oshogbo', lat: 7.7700, lng: 4.5658),

      // South-South
      (name: 'Port Harcourt', lat: 4.8156, lng: 7.0498),
      (name: 'Warri', lat: 5.5142, lng: 5.7386),
      (name: 'Calabar', lat: 4.9526, lng: 8.3382),

      // South-East
      (name: 'Aba', lat: 5.1066, lng: 7.3667),
      (name: 'Onitsha', lat: 6.1450, lng: 6.7866),
      (name: 'Enugu', lat: 6.5244, lng: 7.5186),
      (name: 'Umuahia', lat: 5.5298, lng: 7.4965),

      // North-Central
      (name: 'Abuja', lat: 9.0765, lng: 7.3986),
      (name: 'Jos', lat: 9.8965, lng: 8.8583),
      (name: 'Makurdi', lat: 7.7325, lng: 8.5353),
      (name: 'Lokoja', lat: 7.8018, lng: 6.7349),

      // North-West
      (name: 'Kaduna', lat: 10.5222, lng: 7.4383),
      (name: 'Kano', lat: 12.0022, lng: 8.5920),
      (name: 'Katsina', lat: 13.1339, lng: 7.6299),
      (name: 'Sokoto', lat: 13.0068, lng: 5.2364),

      // North-East
      (name: 'Maiduguri', lat: 11.8433, lng: 13.1590),
      (name: 'Bauchi', lat: 10.3158, lng: 9.8058),
      (name: 'Gombe', lat: 10.3034, lng: 11.1667),
      (name: 'Yola', lat: 9.2077, lng: 12.4794),

      // Benin City & Edo
      (name: 'Benin City', lat: 6.3350, lng: 5.6037),
      (name: 'Asaba', lat: 6.1955, lng: 6.7369),
    ];

/// Human-readable label for the current location.
///
/// Resolution order (best → worst):
///   1. **Reverse geocode** the GPS point with the platform's native
///      geocoder (Android `Geocoder`, iOS `CLGeocoder`). Returns
///      a `Placemark` whose `subLocality` (neighbourhood) and
///      `locality` (city) build a label like "Yaba, Lagos". No API
///      key, no separate rate limit at a mobile-app's volume.
///   2. If the geocoder returns nothing useful (offline, simulator
///      without network, sparse coverage), fall back to the static
///      Nigerian-city table and the nearest-centroid heuristic.
///   3. If we're more than 100 km from every known city, "Nigeria".
///
/// Watch this provider in the header. It refreshes when
/// [currentLocationProvider] re-resolves.
final FutureProvider<String> currentLocationLabelProvider =
    FutureProvider<String>((Ref ref) async {
  final point = await ref.watch(currentLocationProvider.future);

  // 1. Try reverse geocoding first.
  try {
    final placemarks = await placemarkFromCoordinates(point.lat, point.lng);
    if (placemarks.isNotEmpty) {
      final label = _labelFromPlacemark(placemarks.first);
      if (label != null) {
        debugPrint('[Location Label] Reverse-geocoded: $label');
        return label;
      }
    }
  } catch (e) {
    // Native geocoder failed (no network, no Google Play Services
    // on this AVD, rate-limited, etc). Drop to the local fallback.
    debugPrint('[Location Label] Reverse-geocode failed: $e — falling back');
  }

  // 2. Nearest-known-city fallback.
  String? nearest;
  double bestKm = double.infinity;
  for (final c in _cities) {
    final km = _haversineKm(point.lat, point.lng, c.lat, c.lng);
    if (km < bestKm) {
      bestKm = km;
      nearest = c.name;
    }
  }

  // 3. Last resort.
  if (nearest == null || bestKm > 100) return 'Nigeria';
  return '$nearest · Nigeria';
});

/// Build a header label from a Placemark. Returns null when none of
/// the fields are populated enough to be useful (some devices return
/// blank Placemarks for sparsely-mapped areas).
///
/// Priority:
///   - `subLocality, locality`  →  "Yaba, Lagos"
///   - `locality, country`      →  "Lagos · Nigeria"
///   - `administrativeArea`     →  "Lagos State"
String? _labelFromPlacemark(Placemark p) {
  final sub = (p.subLocality ?? '').trim();
  final city = (p.locality ?? '').trim();
  final admin = (p.administrativeArea ?? '').trim();
  final country = (p.country ?? '').trim();

  if (sub.isNotEmpty && city.isNotEmpty) return '$sub, $city';
  if (city.isNotEmpty && country.isNotEmpty) return '$city · $country';
  if (city.isNotEmpty) return city;
  if (admin.isNotEmpty && country.isNotEmpty) return '$admin · $country';
  if (admin.isNotEmpty) return admin;
  return null;
}

/// Great-circle distance in metres between two coordinates. Public
/// wrapper around the haversine used by the clock-out geofence
/// (worker's GPS at capture vs job site centroid).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) =>
    _haversineKm(lat1, lng1, lat2, lng2) * 1000.0;

/// Great-circle distance in km. Standard haversine, no dependencies.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371; // Earth radius, km.
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double d) => d * math.pi / 180;
