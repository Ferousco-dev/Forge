/// Dev-time toggle for the offline banner.
///
/// What remains of the old mock harness — every other flag and the
/// seed-data fixtures have been removed now that the app talks to
/// the real backend. This single flag stays because it's still useful
/// for verifying the offline banner without dropping the device's
/// connection.
///
/// Set [forceOffline] = true in dev to render the app-wide offline
/// banner; live providers continue to serve their cached data so the
/// rest of the UI stays functional.
class MockConfig {
  const MockConfig._();

  /// When true, [isOfflineProvider] (in `mock_providers.dart`) reports
  /// the app as offline app-wide. Providers still return data — the
  /// banner is the only visible effect.
  static bool forceOffline = false;
}
