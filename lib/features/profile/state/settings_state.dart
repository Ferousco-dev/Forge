import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-controlled theme mode. Reads/writes from in-memory state for
/// the static-UI phase; production builds persist via
/// `shared_preferences` and load on app start.
final StateProvider<ThemeMode> themeModeProvider =
    StateProvider<ThemeMode>((Ref ref) => ThemeMode.system);

/// Notification preference toggles. Real builds drive both client-side
/// muting *and* server push registration.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.newJobAlerts = true,
    this.applicationUpdates = true,
    this.paymentConfirmations = true,
    this.loanReminders = true,
  });

  final bool newJobAlerts;
  final bool applicationUpdates;
  final bool paymentConfirmations;
  final bool loanReminders;

  NotificationPreferences copyWith({
    bool? newJobAlerts,
    bool? applicationUpdates,
    bool? paymentConfirmations,
    bool? loanReminders,
  }) {
    return NotificationPreferences(
      newJobAlerts: newJobAlerts ?? this.newJobAlerts,
      applicationUpdates: applicationUpdates ?? this.applicationUpdates,
      paymentConfirmations:
          paymentConfirmations ?? this.paymentConfirmations,
      loanReminders: loanReminders ?? this.loanReminders,
    );
  }
}

final StateProvider<NotificationPreferences> notificationPrefsProvider =
    StateProvider<NotificationPreferences>(
  (Ref ref) => const NotificationPreferences(),
);

/// Privacy settings the user controls.
@immutable
class PrivacyPreferences {
  const PrivacyPreferences({this.allowLocationTrackingDuringWork = true});

  final bool allowLocationTrackingDuringWork;

  PrivacyPreferences copyWith({bool? allowLocationTrackingDuringWork}) {
    return PrivacyPreferences(
      allowLocationTrackingDuringWork: allowLocationTrackingDuringWork ??
          this.allowLocationTrackingDuringWork,
    );
  }
}

final StateProvider<PrivacyPreferences> privacyPrefsProvider =
    StateProvider<PrivacyPreferences>(
  (Ref ref) => const PrivacyPreferences(),
);
