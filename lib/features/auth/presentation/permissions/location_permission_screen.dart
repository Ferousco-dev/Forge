import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_paths.dart';
import '_permission_scaffold.dart';
import 'permission_illustrations.dart';

/// Asks the user to enable location services.
///
/// Both "Enable Location" and "Maybe later" advance to the notifications
/// permission screen — the worker can recover later from Settings, but
/// the brief explicitly warns the app won't work well without location,
/// which the dimmed-decline + helper line conveys.
class LocationPermissionScreen extends StatelessWidget {
  const LocationPermissionScreen({super.key});

  void _next(BuildContext context) =>
      context.go(RoutePaths.permissionsNotifications);

  @override
  Widget build(BuildContext context) {
    return PermissionScaffold(
      illustration: const IllustrationLocationPin(),
      title: 'Find jobs near you',
      body:
          'We use your location to show the closest jobs and verify when '
          'you arrive at a work site.',
      primaryLabel: 'Enable Location',
      declineLabel: 'Maybe later',
      warnOnDecline: true,
      declineWarning:
          'Without location, you won\'t see jobs near you and employers '
          'can\'t verify your arrival.',
      onPrimary: () => _next(context),
      onDecline: () => _next(context),
    );
  }
}
