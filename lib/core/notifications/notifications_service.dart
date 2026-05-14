import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'device_repository.dart';
import 'notification_channels.dart';

/// Mobile-side push runtime.
///
/// Owns:
///   - First-launch channel registration (so the `forge_payments`
///     channel exists with the `opay_credit` custom sound before the
///     first push arrives).
///   - OS permission request (Android 13+ runtime POST_NOTIFICATIONS,
///     iOS UNUserNotificationCenter).
///   - FCM token lifecycle: fetch, register with backend, react to
///     `onTokenRefresh`, deregister on logout.
///   - Foreground display: FCM does NOT auto-show notifications when
///     the app is in the foreground on Android, and on iOS the system
///     banner is suppressed by default. We bridge via
///     `flutter_local_notifications` so the user sees the message
///     and hears the custom sound.
///   - Tap routing: exposes a stream of deeplink strings the app
///     listens on and routes via GoRouter.
///
/// Background / terminated delivery is handled by the top-level
/// `firebaseMessagingBackgroundHandler` registered in `main.dart`.
///
/// See `endpoint_resources/24_push_notifications.md` for the
/// server-side contract this class consumes.
class NotificationsService {
  NotificationsService({
    required DeviceRepository deviceRepository,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localPlugin,
  })  : _devices = deviceRepository,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _local = localPlugin ?? FlutterLocalNotificationsPlugin();

  final DeviceRepository _devices;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;

  final StreamController<String> _deeplinks =
      StreamController<String>.broadcast();
  final StreamController<RemoteMessage> _foreground =
      StreamController<RemoteMessage>.broadcast();

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  bool _initialised = false;

  /// Tap stream — every notification tap (foreground, background, or
  /// the cold-start "launched from notification" case) emits the
  /// `deeplink` from the FCM payload here. Consumers route via
  /// GoRouter; non-routable kinds (`system`) emit `null` and should
  /// be ignored.
  Stream<String> get onDeeplink => _deeplinks.stream;

  /// Foreground delivery stream. Useful for refreshing the in-app
  /// notifications feed (`notificationsPageProvider`) so the bell
  /// badge stays in sync without waiting for the screen to rebuild.
  Stream<RemoteMessage> get onForegroundMessage => _foreground.stream;

  // -------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------

  /// One-time setup. Called from `app.dart` after the first frame.
  /// Idempotent — second call is a no-op.
  ///
  /// Does NOT request OS permission (that's user-driven via the
  /// permission screen) and does NOT register the device (that
  /// requires an authenticated session). It just wires the listeners
  /// + creates the local channels.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    await _setupLocalNotifications();
    await _registerAndroidChannels();
    await _wireFcmListeners();
    await _drainInitialMessage();
  }

  /// Permission prompt + device registration in one call. Invoked
  /// from the notification permission screen's "Enable Notifications"
  /// CTA.
  ///
  /// Returns true if the user granted (or had previously granted)
  /// permission and the device was registered.
  Future<bool> requestPermissionAndRegister() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!granted) return false;

    await _registerCurrentToken();
    return true;
  }

  /// Best-effort registration for already-permissioned sessions on
  /// cold start. Skipped if the cached token already matches the
  /// current FCM token.
  Future<void> registerIfPermitted() async {
    final settings = await _messaging.getNotificationSettings();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return;
    await _registerCurrentToken();
  }

  Future<void> unregister() async {
    await _devices.unregisterDevice();
  }

  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _onTokenRefreshSub?.cancel();
    await _deeplinks.close();
    await _foreground.close();
  }

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  Future<void> _setupLocalNotifications() async {
    const android = AndroidInitializationSettings('ic_stat_forge');
    final ios = DarwinInitializationSettings(
      // FCM owns the iOS presentation request; we just need the
      // plugin initialised so foreground display works on Android.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );
  }

  Future<void> _registerAndroidChannels() async {
    if (!Platform.isAndroid) return;
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final channel in NotificationChannels.all) {
      await android.createNotificationChannel(channel);
    }
  }

  Future<void> _wireFcmListeners() async {
    // iOS-only: ensure the system shows the banner / plays the sound
    // for foreground messages too. Android we handle ourselves below.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _onMessageSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _onMessageOpenedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTapped);
    _onTokenRefreshSub =
        _messaging.onTokenRefresh.listen(_onTokenRefreshed);
  }

  /// Cold-start case: app was launched by tapping a notification while
  /// terminated. FCM stashes the message; we drain it once at startup
  /// and emit the deeplink.
  Future<void> _drainInitialMessage() async {
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _emitDeeplinkFrom(initial);
  }

  Future<void> _registerCurrentToken() async {
    try {
      // iOS: APNs token must be available before the FCM token is
      // valid. The Flutter plugin handles waiting, but on a cold
      // simulator it can return null — we just skip and try again
      // on the next session.
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      if (await _devices.isAlreadyRegistered(token)) return;
      await _devices.registerDevice(pushToken: token);
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push] registerCurrentToken failed: $e\n$st');
      }
      // Swallow — registration retries on next cold start. A failed
      // POST shouldn't block the user from finishing onboarding.
    }
  }

  Future<void> _onTokenRefreshed(String token) async {
    try {
      await _devices.registerDevice(pushToken: token);
    } catch (_) {
      // Same logic as above: best-effort.
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    _foreground.add(message);
    await _displayForeground(message);
  }

  /// Android foreground display. iOS already shows the banner via
  /// `setForegroundNotificationPresentationOptions` above; calling
  /// `_local.show` on iOS too would double-display.
  Future<void> _displayForeground(RemoteMessage message) async {
    if (!Platform.isAndroid) return;

    final notification = message.notification;
    if (notification == null) return;

    final channelId = message.data['channel_id'] as String? ??
        _channelIdForKind(message.data['kind'] as String?);
    final channel = _channelById(channelId);

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: Priority.high,
      icon: 'ic_stat_forge',
      sound: channel.sound,
      playSound: channel.playSound,
      enableVibration: channel.enableVibration,
    );

    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: androidDetails),
      payload: message.data['deeplink'] as String?,
    );
  }

  void _onMessageTapped(RemoteMessage message) => _emitDeeplinkFrom(message);

  void _onLocalNotificationTapped(NotificationResponse response) {
    final deeplink = response.payload;
    if (deeplink != null && deeplink.isNotEmpty) {
      _deeplinks.add(deeplink);
    }
  }

  void _emitDeeplinkFrom(RemoteMessage message) {
    final deeplink = message.data['deeplink'] as String?;
    if (deeplink == null || deeplink.isEmpty) return;
    _deeplinks.add(deeplink);
  }

  String _channelIdForKind(String? kind) {
    switch (kind) {
      case 'application_update':
      case 'payment':
        return NotificationChannels.payments.id;
      case 'new_job':
        return NotificationChannels.jobs.id;
      default:
        return NotificationChannels.defaultChannel.id;
    }
  }

  AndroidNotificationChannel _channelById(String id) {
    for (final c in NotificationChannels.all) {
      if (c.id == id) return c;
    }
    return NotificationChannels.defaultChannel;
  }
}
