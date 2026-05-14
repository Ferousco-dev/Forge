import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_state.dart';
import '../data/sessions_repository.dart';

final Provider<SessionsRepository> sessionsRepositoryProvider =
    Provider<SessionsRepository>((Ref ref) {
  return SessionsRepository(client: ref.watch(apiClientProvider));
});
