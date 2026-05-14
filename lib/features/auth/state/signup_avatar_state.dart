import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the verified `upload_id` returned by `POST /uploads/liveness`
/// during the signup flow. Read by the profile-setup screen on submit
/// so the avatar promotion happens server-side via
/// `POST /auth/profile-setup` `photo_upload_id`.
///
/// Lives only between the liveness capture step and the profile-setup
/// step. Cleared on successful profile-setup or on logout.
final StateProvider<String?> signupAvatarUploadIdProvider =
    StateProvider<String?>((Ref ref) => null);

/// On-disk path to the captured liveness selfie.
///
/// We persist the local path (not just the upload id) so the
/// profile-setup avatar can preview the captured photo immediately
/// via `Image.file`, with no network round trip and no dependence on
/// the upload's CDN URL having propagated yet. Set by
/// [LivenessCaptureScreen] right after `POST /uploads/liveness`
/// succeeds; read by profile-setup's `_AvatarUpload`.
///
/// Cleared alongside [signupAvatarUploadIdProvider] when profile-setup
/// finishes or the worker logs out.
final StateProvider<String?> signupAvatarLocalPathProvider =
    StateProvider<String?>((Ref ref) => null);
