import 'package:flutter/foundation.dart';

/// Performance monitoring utilities for tracking frame times and jank.
class PerformanceMonitor {
  static bool _initialized = false;

  /// Initialize performance monitoring. Call once in main().
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    if (kDebugMode) {
      // Monitor frame rendering in debug mode.
      // Uncomment to enable Dart DevTools timeline recording:
      // developer.Timeline.instantSync('app_start');
    }
  }

  /// Mark a named operation for timeline tracking.
  static void markStart(String label) {
    if (kDebugMode) {
      // Future: integrate with developer.Timeline or custom profiling
    }
  }

  /// End a named timeline operation.
  static void markEnd(String label) {
    if (kDebugMode) {
      // Future: finish timeline operation
    }
  }
}
