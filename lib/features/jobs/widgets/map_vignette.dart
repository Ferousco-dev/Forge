import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// Soft ambient gradient overlay placed *above* a [MapPlaceholder] on
/// the home screen. Fades the map's edges into the surface color so
/// neither the floating header nor the bottom sheet has a hard cut.
///
/// Designed as a separate layer (not part of `MapPlaceholder`) so the
/// detail / clock-in screens — which use `MapPlaceholder.snippet`
/// inside a clipped card — stay untouched.
class MapVignette extends StatelessWidget {
  const MapVignette({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final surface = palette.surface;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Top fade — softens the map under the frosted header.
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      surface.withValues(alpha: 0.72),
                      surface.withValues(alpha: 0.0),
                    ],
                    stops: const <double>[0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Bottom fade — softens the cut where the sheet's rounded
          // corner meets the map. The fade is short and very subtle.
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 96,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[
                      surface.withValues(alpha: 0.30),
                      surface.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
