import 'package:flutter/material.dart';

import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';

/// Travel mode shown alongside a duration ("10 min walk", "5 min drive").
enum TravelMode { walking, driving }

/// Formats distance + travel time consistently across the app.
///
/// Two display styles:
/// - Default: distance as a chip-friendly badge (e.g., "850m", "1.2km").
/// - When [travelMinutes] + [mode] are passed: pairs the distance with a
///   small travel-mode icon and minutes (e.g., "🚶 10 min walk").
class DistanceText extends StatelessWidget {
  const DistanceText({
    super.key,
    required this.meters,
    this.style,
    this.color,
  })  : travelMinutes = null,
        mode = null;

  const DistanceText.travel({
    super.key,
    required this.meters,
    required int this.travelMinutes,
    required TravelMode this.mode,
    this.style,
    this.color,
  });

  final int meters;
  final int? travelMinutes;
  final TravelMode? mode;
  final TextStyle? style;
  final Color? color;

  String _formatDistance() {
    if (meters < 1000) return '${meters}m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  /// Travel time label. Sub-hour values render as "5 min", "55 min".
  /// At an hour or more we switch to "1 h 5 min" / "12 h" so a
  /// cross-state job (~750 km drive) doesn't render as "750 min".
  String _formatTravel(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolved = color ?? palette.onSurfaceVariant;
    final base =
        (style ?? AppTextStyles.labelLarge).copyWith(color: resolved);

    if (mode == null) {
      return Text(_formatDistance(), style: base);
    }

    final iconData = mode == TravelMode.walking
        ? Icons.directions_walk_rounded
        : Icons.directions_car_rounded;
    final label = mode == TravelMode.walking ? 'walk' : 'drive';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(iconData, size: 14, color: resolved),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${_formatTravel(travelMinutes!)} $label',
            style: base,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
