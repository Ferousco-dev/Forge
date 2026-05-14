import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/notifications/notifications_service.dart';
import 'features/auth/state/auth_state.dart';
import 'features/profile/state/notifications_state.dart';
import 'features/profile/state/settings_state.dart';

/// Root widget.
///
/// Mounts [MaterialApp.router] against [buildAppRouter] and binds the
/// design-system theme. Theme mode is driven by [themeModeProvider] so
/// the Settings screen can flip Light / Dark / System at runtime.
///
/// Also owns the **push wiring lifecycle**: starts the notifications
/// service after the first frame, listens to its deeplink stream, and
/// routes incoming taps via the GoRouter instance.
///
/// `ProviderScope` is mounted in `main()` so this widget itself doesn't
/// have to know about Riverpod beyond the watches below.
class ForgeApp extends ConsumerStatefulWidget {
  const ForgeApp({super.key});

  @override
  ConsumerState<ForgeApp> createState() => _ForgeAppState();
}

class _ForgeAppState extends ConsumerState<ForgeApp> {
  late final _router = buildAppRouter();
  StreamSubscription<String>? _deeplinkSub;
  StreamSubscription<void>? _foregroundSub;

  @override
  void initState() {
    super.initState();
    // Push setup runs after the first frame so providers are stable
    // and any startup-blocking exception (no Firebase config yet) is
    // confined to a microtask, not a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootPush());
  }

  Future<void> _bootPush() async {
    final NotificationsService svc =
        ref.read(notificationsServiceProvider);
    try {
      await svc.init();
    } catch (_) {
      // If Firebase wasn't configured yet (see main.dart), init throws.
      // Push silently degrades; the rest of the app still runs.
      return;
    }

    _deeplinkSub = svc.onDeeplink.listen(_onDeeplink);

    // Refresh the in-app feed whenever a foreground push arrives, so
    // the bell badge stays in sync the moment the message lands.
    _foregroundSub = svc.onForegroundMessage.listen((_) {
      ref.invalidate(notificationsPageProvider);
    });

    // Cold-start guard: if the worker is already authenticated and
    // had previously granted permission, refresh the FCM token with
    // the backend. No-op if cached + current token match.
    await svc.registerIfPermitted();
  }

  /// Translate a `forge://...` deeplink to a GoRouter path and push it.
  /// Stable mapping mirrors the table in
  /// `endpoint_resources/24_push_notifications.md` + `19_notifications.md`.
  void _onDeeplink(String deeplink) {
    final uri = Uri.tryParse(deeplink);
    if (uri == null || uri.scheme != 'forge') return;

    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    String? target;
    switch (uri.host) {
      case 'jobs':
        // forge://jobs/:id              -> /jobs/:id
        // forge://jobs/:id/clock-in     -> /jobs/:id/clock-in
        // forge://jobs/:id/status       -> /jobs/:id/status
        if (segments.length == 1) {
          target = '/jobs/${segments[0]}';
        } else if (segments.length >= 2) {
          target = '/jobs/${segments[0]}/${segments[1]}';
        }
      case 'transactions':
        // forge://transactions/:id -> /earnings/transactions/:id
        if (segments.isNotEmpty) {
          target = '/earnings/transactions/${segments[0]}';
        }
      case 'loans':
        // forge://loans/approved | rejected | :id
        if (segments.isNotEmpty) {
          target = '/loans/${segments[0]}';
        }
      case 'notifications':
        target = '/profile/notifications';
    }

    if (target != null) _router.push(target);
  }

  @override
  void dispose() {
    _deeplinkSub?.cancel();
    _foregroundSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Forge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
      builder: (BuildContext context, Widget? child) {
        return _SystemUiOverlayWrapper(child: child);
      },
    );
  }
}

class _SystemUiOverlayWrapper extends StatelessWidget {
  const _SystemUiOverlayWrapper({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }
}
