import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

/// Open turn-by-turn directions to [destLat], [destLng] in the user's
/// preferred maps app.
///
/// No API key required — we use the universal Google Maps directions
/// URL (`https://www.google.com/maps/dir/?api=1&...`). When no origin
/// is supplied, Google Maps automatically uses the device's current
/// GPS location as the starting point — same as it does when you tap
/// "Directions" from a place card in the Maps app itself.
///
/// Platform behaviour:
/// - **Android**: opens the Google Maps app if installed, otherwise
///   the browser falls back to maps.google.com.
/// - **iOS**: opens Google Maps if installed, otherwise Apple Maps
///   (via the `maps://` scheme) as a fallback so users without the
///   Google Maps app still get native navigation.
///
/// Returns `true` if a maps app was launched, `false` otherwise (e.g.
/// no maps app installed and no browser available — extremely rare).
Future<bool> launchDirections({
  required double destLat,
  required double destLng,
  String? destLabel,
}) async {
  // Universal Google Maps directions URL. `api=1` is the documented
  // stable contract — no key, no quota.
  // https://developers.google.com/maps/documentation/urls/get-started
  final googleUri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=$destLat,$destLng'
    '&travelmode=driving',
  );

  // Try Google Maps first. We **do not** gate on `canLaunchUrl` for
  // https URLs: on Android 11+ the check requires a `<queries>` block
  // in AndroidManifest.xml for the HTTP intent or it returns false,
  // even though every device can actually open https:// links. The
  // launch itself either succeeds or throws — catching the throw is
  // both simpler and correct.
  try {
    final ok = await launchUrl(
      googleUri,
      mode: LaunchMode.externalApplication,
    );
    if (ok) return true;
  } catch (_) {
    // Fall through to platform-specific fallback.
  }

  // iOS fallback: Apple Maps via maps.apple.com (which deep-links into
  // the native Apple Maps app on iOS). Useful when the iPhone has no
  // browser configured as default https handler.
  if (Platform.isIOS) {
    final appleUri = Uri.parse(
      'https://maps.apple.com/?daddr=$destLat,$destLng&dirflg=d',
    );
    try {
      return await launchUrl(appleUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  return false;
}
