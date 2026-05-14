import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/uploads/uploads_state.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/signup_avatar_state.dart';

/// AI-verified selfie step for the signup flow.
///
/// Sits between OTP verify and profile-setup. The user takes a live
/// selfie (front camera, system camera UI), the bytes hit
/// `POST /uploads/liveness` (see `endpoint_resources/23_liveness.md`),
/// and the backend's AI verifies a single live face — anything else
/// (no face, multiple faces, photo-of-a-photo, low quality) comes
/// back as a 422 with a user-ready message.
///
/// On success the verified `upload_id` lands in
/// [signupAvatarUploadIdProvider]; profile-setup picks it up and
/// sends it as `photo_upload_id`.
class LivenessCaptureScreen extends ConsumerStatefulWidget {
  const LivenessCaptureScreen({super.key});

  @override
  ConsumerState<LivenessCaptureScreen> createState() =>
      _LivenessCaptureScreenState();
}

class _LivenessCaptureScreenState
    extends ConsumerState<LivenessCaptureScreen> {
  final ImagePicker _picker = ImagePicker();

  /// Local file of the most recent capture. Held so the user can
  /// review before submitting and so retake is one tap.
  File? _captured;

  bool _capturing = false;
  bool _verifying = false;
  String? _error;

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        // Front camera by default — selfie. The system UI lets the
        // user flip if their device exposes a toggle.
        preferredCameraDevice: CameraDevice.front,
        // Cap the upload size up front so we don't ship a 4032×3024
        // photo over a flaky 3G link. Server still validates max
        // bounds defensively.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (shot == null) {
        // User backed out of the camera UI — leave previous state.
        if (mounted) setState(() => _capturing = false);
        return;
      }
      if (!mounted) return;
      setState(() {
        _captured = File(shot.path);
        _capturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'Camera unavailable. Make sure camera permission is on.';
      });
    }
  }

  Future<void> _submit() async {
    final file = _captured;
    if (file == null || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final filename = file.uri.pathSegments.isEmpty
          ? 'selfie.jpg'
          : file.uri.pathSegments.last;
      // Trust the system-camera output; if the path doesn't end in
      // an obvious type we send jpeg (image_picker normalises to
      // JPEG on iOS/Android by default).
      final lower = filename.toLowerCase();
      final contentType = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.heic')
              ? 'image/heic'
              : 'image/jpeg';

      // Liveness verification + persistence in one call. The endpoint
      // runs synchronous AI checks (face count, anti-spoof, quality
      // via Smile Identity); on pass the image is persisted and the
      // returned `upload_id` is what `POST /v1/auth/profile-setup`
      // accepts in `photo_upload_id` (per the liveness spec —
      // signup-only verified flow, distinct from the generic
      // `POST /v1/uploads?purpose=worker_avatar` path used by
      // edit-profile later in the worker's lifecycle).
      //
      // Failures here throw a typed ApiException with a stable
      // details.reason enum (LIVENESS_NO_FACE, LIVENESS_SPOOF, etc.)
      // and a user-friendly message — surfaced verbatim below.
      final handle =
          await ref.read(uploadsRepositoryProvider).uploadLiveness(
                bytes: bytes,
                filename: filename,
                contentType: contentType,
                deviceMetadata: <String, String>{
                  'platform': Platform.isIOS ? 'ios' : 'android',
                  'camera': 'front',
                },
              );

      // Stash for the profile-setup step. Both the upload id (sent to
      // the backend in `POST /auth/profile-setup`) and the local file
      // path (so profile-setup's avatar widget can preview the photo
      // without a network round trip).
      ref.read(signupAvatarUploadIdProvider.notifier).state = handle.id;
      ref.read(signupAvatarLocalPathProvider.notifier).state = file.path;

      if (!mounted) return;
      context.go(RoutePaths.profileSetup);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        // Server returns user-friendly copy via `error.message` on the
        // typed liveness rejections — render it directly. Generic
        // network failures fall through to a calmer default.
        _error = e.isNetwork
            ? "Couldn't reach the server. Check your connection."
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = "Something went wrong reading the photo. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasShot = _captured != null;
    final cta = hasShot ? 'Use this photo' : 'Take selfie';

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Take a quick selfie',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A real photo helps employers recognise you on the job '
                "site. We check it's you and not a photo of a photo — "
                "this takes a second.",
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: Center(
                  child: _PreviewFrame(
                    file: _captured,
                    onTap: _capturing || _verifying ? null : _capture,
                  ),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (hasShot) ...<Widget>[
                AppTextButton(
                  label: 'Retake',
                  onPressed: _capturing || _verifying ? null : _capture,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              PrimaryButton(
                label: cta,
                isLoading: _verifying || _capturing,
                onPressed: hasShot ? _submit : _capture,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview window — empty placeholder before capture, then the photo
/// once taken. Whole frame is tappable so a tap anywhere recaptures.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.file, required this.onTap});
  final File? file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: palette.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: palette.outline, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: file == null
              ? _Placeholder(palette: palette)
              : Image.file(
                  file!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.palette});
  final dynamic palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.face_retouching_natural_rounded,
            size: 56,
            color: (palette.onSurfaceVariant as Color).withValues(
              alpha: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap to open camera',
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant as Color,
            ),
          ),
        ],
      ),
    );
  }
}
