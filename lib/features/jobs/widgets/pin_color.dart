import 'package:flutter/material.dart';

import '../../../core/mock/models.dart';

/// Distinct accent colour per [JobType] for map pins.
///
/// Hand-picked, accessibility-aware palette — every colour is
/// visually distinct against an OpenStreetMap basemap, and each
/// pair has enough hue separation that workers with the most
/// common forms of colour-blindness (deuteranopia, protanopia)
/// can still tell them apart by position + shape, not colour alone.
///
/// If you ever add a new [JobType], add it here too — otherwise it
/// falls back to the brand primary, which is fine but loses the
/// "scan the map and see types at a glance" affordance.
Color pinColorFor(JobType type) {
  switch (type) {
    case JobType.loader:
      return const Color(0xFF1E88E5); // blue
    case JobType.driver:
      return const Color(0xFFE65100); // deep orange
    case JobType.unloader:
      return const Color(0xFF8E24AA); // purple
    case JobType.generalLabor:
      return const Color(0xFF2E7D32); // green
    case JobType.welder:
      return const Color(0xFFD81B60); // pink-red
  }
}
