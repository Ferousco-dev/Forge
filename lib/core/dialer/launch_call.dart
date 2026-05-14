import 'package:url_launcher/url_launcher.dart';

/// Hand the number off to the platform dialer.
///
/// Returns `false` when:
///   * [phoneNumber] is null or blank (no number on file for this
///     employer) — caller should show a "no number available" message.
///   * The launch genuinely fails (extremely rare — every Android /
///     iOS device ships with a dialer that registers for `tel:`).
///
/// We deliberately skip `canLaunchUrl` for `tel:` URLs for the same
/// reason we skip it for `https://` — on Android 11+ the check
/// requires a `<queries>` block in AndroidManifest.xml for the
/// `ACTION_DIAL` intent, even though the launch itself always works.
Future<bool> launchPhoneCall(String? phoneNumber) async {
  if (phoneNumber == null || phoneNumber.trim().isEmpty) return false;

  // Strip whitespace and common formatting characters so the dialer
  // sees a clean number. `tel:` tolerates `+`, digits, `*`, `#`, `,`,
  // `;`, and a few others — but spaces and parentheses cause some
  // dialers to choke. Keep only the meaningful chars.
  final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+#*,;]'), '');
  if (cleaned.isEmpty) return false;

  final uri = Uri.parse('tel:$cleaned');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
