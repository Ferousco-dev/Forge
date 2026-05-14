import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/session_storage.dart';
import 'auth_state.dart';

/// Tracks whether the user has completed the onboarding carousel.
///
/// Persisted in [SessionStorage] (Keychain on iOS, encrypted shared
/// prefs on Android), so the carousel is shown exactly once per
/// install. The splash gate reads from here on cold start and chooses
/// between `/onboarding` and `/auth/login`.
///
/// **Hydration timing matters.** `build()` returns `false` synchronously,
/// then kicks `_hydrate()` to read the persisted flag from secure
/// storage. The splash gate MUST `await ensureLoaded()` before reading
/// `state`, otherwise a returning user lands on the onboarding carousel
/// again because the persisted "seen" flag hasn't been loaded yet.
class OnboardingSeenNotifier extends Notifier<bool> {
  late final SessionStorage _storage;
  late final Future<void> _hydration;

  @override
  bool build() {
    _storage = ref.watch(sessionStorageProvider);
    _hydration = _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final seen = await _storage.readOnboardingSeen();
    if (seen != state) state = seen;
  }

  /// Resolves once the persisted "seen" flag has been read into state.
  /// Splash gate awaits this so the route decision sees the real value,
  /// not the synchronous `false` default.
  Future<void> ensureLoaded() => _hydration;

  /// Mark onboarding as completed. Persisted immediately so the next
  /// cold start skips the carousel.
  Future<void> markSeen() async {
    state = true;
    await _storage.writeOnboardingSeen(true);
  }
}

final NotifierProvider<OnboardingSeenNotifier, bool>
    hasSeenOnboardingProvider =
    NotifierProvider<OnboardingSeenNotifier, bool>(
  OnboardingSeenNotifier.new,
);
