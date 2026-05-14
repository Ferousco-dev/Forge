import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level background / terminated message handler.
///
/// FCM contract (non-negotiable):
///   - MUST be a top-level function or static method (not a closure
///     and not a class instance method) — it runs in a separate Dart
///     isolate that has no shared memory with the UI isolate.
///   - MUST be annotated `@pragma('vm:entry-point')` so tree-shaking
///     in release mode doesn't strip it.
///   - MUST call `Firebase.initializeApp` itself, since the new
///     isolate didn't run `main()`.
///
/// What we intentionally do NOT do here:
///   - Display a notification: when the FCM payload contains a
///     `notification` block (which ours always does — see
///     `endpoint_resources/24_push_notifications.md`), the system
///     tray draws the notification automatically. Re-displaying via
///     flutter_local_notifications would dupe it.
///   - Touch any provider / repository: providers live in the UI
///     isolate and are unreachable from here. Any state we want to
///     reflect (unread count, in-app feed) is re-fetched when the
///     user opens the app via the existing `notificationsPageProvider`.
///
/// We log in debug builds so the handler is observable while wiring
/// up — in release this is a near-no-op that exists purely to keep
/// FCM's contract.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) {
    // ignore: avoid_print
    print(
      '[push:bg] kind=${message.data['kind']} '
      'id=${message.data['notification_id']} '
      'deeplink=${message.data['deeplink']}',
    );
  }
}
