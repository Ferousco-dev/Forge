import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_paths.dart';
import '../../state/auth_state.dart';
import '_permission_scaffold.dart';
import 'permission_illustrations.dart';

/// Final permission step in the signup flow.
///
/// Both choices route to the home shell — notifications are
/// nice-to-have, not load-bearing. The "Enable Notifications" CTA
/// triggers the OS prompt and (on grant) registers the device with
/// the backend via `POST /me/devices`. "Skip" silently moves on; the
/// user can grant later from system settings, and the next cold
/// start's `registerIfPermitted` call will pick it up.
class NotificationPermissionScreen extends ConsumerWidget {
  const NotificationPermissionScreen({super.key});

  void _next(BuildContext context) => context.go(RoutePaths.jobs);

  /// Fire-and-forget so the scaffold's loading state stays in sync
  /// with its own internal animation. Whether the prompt is granted
  /// or denied, we still proceed — the user has crossed the gate
  /// either way. A failed call (no Firebase config, simulator without
  /// APNs) also falls through silently; push retries next cold start.
  void _enable(BuildContext context, WidgetRef ref) {
    ref
        .read(notificationsServiceProvider)
        .requestPermissionAndRegister()
        .catchError((_) => false)
        .whenComplete(() {
      if (context.mounted) _next(context);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionScaffold(
      illustration: const IllustrationBell(),
      title: 'Get notified about jobs',
      body:
          "We'll let you know when new jobs are posted near you and "
          "when employers respond to your applications.",
      primaryLabel: 'Enable Notifications',
      declineLabel: 'Skip',
      onPrimary: () => _enable(context, ref),
      onDecline: () => _next(context),
    );
  }
}
