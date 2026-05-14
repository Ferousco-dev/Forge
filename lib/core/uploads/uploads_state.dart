import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_state.dart';
import 'uploads_repository.dart';

final Provider<UploadsRepository> uploadsRepositoryProvider =
    Provider<UploadsRepository>((Ref ref) {
  return UploadsRepository(client: ref.watch(apiClientProvider));
});
