import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channels.
///
/// IDs match `android.notification.channel_id` in the FCM payloads
/// documented in `endpoint_resources/24_push_notifications.md`. The
/// server addresses these by id; the device must have created the
/// channel before the first push of that channel arrives, otherwise
/// Android falls back to the default channel and ignores `sound`.
///
/// Channels are user-mutable from system settings (sound, importance,
/// LED colour, vibration). We seed sensible defaults; the user owns
/// the override.
class NotificationChannels {
  const NotificationChannels._();

  /// Money events. Uses the bundled `opay_credit` custom sound.
  /// Triggered by:
  ///   - `application_update` (accepted)
  ///   - `payment` (wallet credited)
  static const AndroidNotificationChannel payments =
      AndroidNotificationChannel(
    'forge_payments',
    'Payments & approvals',
    description:
        'Money credited to your wallet, and employer approvals on jobs '
        "you've applied for.",
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('opay_credit'),
    enableVibration: true,
  );

  /// New jobs near the worker's location. Default sound — distinct
  /// from money events on purpose so the user can tell them apart.
  static const AndroidNotificationChannel jobs = AndroidNotificationChannel(
    'forge_jobs',
    'New jobs near you',
    description:
        'A new job was posted within your preferred radius and matches '
        'your skill.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// Catch-all: rejections, loan reminders, system messages.
  static const AndroidNotificationChannel defaultChannel =
      AndroidNotificationChannel(
    'forge_default',
    'General',
    description: 'Application updates, loan reminders, and account alerts.',
    importance: Importance.defaultImportance,
    playSound: true,
  );

  static const List<AndroidNotificationChannel> all =
      <AndroidNotificationChannel>[
    payments,
    jobs,
    defaultChannel,
  ];
}
