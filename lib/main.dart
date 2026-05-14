import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/notifications/push_background_handler.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Swallow noisy OSM tile fetch errors. The map already retries and
  // caches, so a single dropped tile isn't user-visible — but the
  // image resource service logs every socket reset, which floods the
  // debug console. We forward everything else to Flutter's default
  // handler.
  final FlutterExceptionHandler? defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String msg = details.exceptionAsString();
    if (msg.contains('tile.openstreetmap.org') &&
        (msg.contains('Connection reset') ||
            msg.contains('SocketException') ||
            msg.contains('ClientException'))) {
      return;
    }
    defaultOnError?.call(details);
  };

  // Firebase + FCM bootstrap. Order matters:
  //   1. `Firebase.initializeApp` must complete before any other
  //      firebase_* call (including the background-handler isolate's
  //      own re-init) and before `runApp` so `notificationsServiceProvider`
  //      can resolve cleanly during the first frame.
  //   2. The background message handler MUST be registered against a
  //      top-level function (see `push_background_handler.dart`),
  //      from the UI isolate, before any background message can be
  //      delivered. Registering after `runApp` would race against
  //      cold-start pushes.
  //
  // Wrapped in try/catch because, until `flutterfire configure` has
  // generated `firebase_options.dart` and dropped the platform configs
  // (google-services.json / GoogleService-Info.plist), `initializeApp`
  // throws. We don't want that to brick the rest of the app during
  // local UI work — push silently degrades instead. Setup steps are
  // documented in `endpoint_resources/24_push_notifications.md`.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[push] Firebase init skipped: $e\n$st');
    }
  }

  // Edge-to-edge so the splash background owns the full canvas.
  // Per-screen status / nav bar styling is applied via
  // `AnnotatedRegion<SystemUiOverlayStyle>` inside each screen.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Lock to portrait. Rotation can be re-enabled per-screen when a
  // landscape-friendly screen needs it (e.g. clock-out camera).
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ProviderScope(child: ForgeApp()));
}
