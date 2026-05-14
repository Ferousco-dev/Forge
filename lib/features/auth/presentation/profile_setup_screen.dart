import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/auth_state.dart';
import '../state/signup_avatar_state.dart';

/// Captures the basics needed before the user can be matched with work.
///
/// Brief calls for: profile photo upload (tap to capture), full name,
/// primary skill (Loader, Driver, Unloader, General Labor, Other), and
/// preferred work radius slider (1km – 20km). Continue routes to
/// `/auth/permissions/location`.
///
/// Photo capture is mocked — Phase D wires the camera. The avatar
/// affordance shows the "tap to add" overlay; tapping it shows a
/// snackbar acknowledging the deferred capability.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final TextEditingController _name = TextEditingController();
  String? _nameError;

  /// Top-of-form error banner — used for anything that isn't a
  /// name-field validation, e.g. a stale `photo_upload_id` rejected
  /// by the server. Showing it under the name input made the photo
  /// failure look like a name problem (see signup bug 2026-05-13).
  String? _formError;

  JobType _skill = JobType.loader;
  double _radiusKm = 5;

  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Escape hatch when profile-setup is blocked (e.g. server is
  /// returning `UPLOAD_NOT_FOUND` for the photo upload and we can't
  /// proceed). Clears the local session so the user can return to
  /// the login / signup screens and try again later. The worker
  /// record stays server-side — same phone number will resume the
  /// signup flow once the backend bug is resolved.
  Future<void> _signOutAndStartOver() async {
    setState(() {
      _submitting = true;
      _nameError = null;
      _formError = null;
    });
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // Server logout is best-effort; the local session is the
      // important part and the AuthRepository.logout call already
      // clears that even when the POST fails.
    }
    // Drop any cached worker / signup-flow state so the next launch
    // routes through login fresh.
    ref
      ..invalidate(authSessionProvider)
      ..read(signupAvatarUploadIdProvider.notifier).state = null
      ..read(signupAvatarLocalPathProvider.notifier).state = null;
    if (!mounted) return;
    context.go(RoutePaths.login);
  }

  Future<void> _continue() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Tell us your name');
      return;
    }
    if (name.length < 2) {
      setState(() => _nameError = 'That name looks too short');
      return;
    }
    setState(() {
      _submitting = true;
      _nameError = null;
      _formError = null;
    });
    // Upload id minted by the liveness screen, passed in via Riverpod
    // state so we don't have to thread it through go_router extras.
    // Null on the (unlikely) path where the user reached profile-setup
    // without going through the signup capture step — backend will
    // reject with VALIDATION_FAILED if so.
    final photoUploadId = ref.read(signupAvatarUploadIdProvider);
    try {
      await ref.read(authRepositoryProvider).completeProfileSetup(
            name: name,
            primarySkill: _skill.label,
            preferredRadiusKm: _radiusKm,
            photoUploadId: photoUploadId,
          );
      // Profile setup consumes the upload — drop the local copy so
      // a future re-entry into the flow can't reuse a stale id, and
      // drop the local file path so the avatar widget falls back to
      // the placeholder if the user re-enters signup later.
      ref.read(signupAvatarUploadIdProvider.notifier).state = null;
      ref.read(signupAvatarLocalPathProvider.notifier).state = null;
      ref.invalidate(authSessionProvider);
      if (!mounted) return;
      context.go(RoutePaths.permissionsLocation);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Route the error to the right surface based on its code.
        // Photo / upload failures (UPLOAD_NOT_FOUND, expired upload)
        // belong at the top of the form, not pinned under the name
        // input — otherwise the worker reads "photo upload not found"
        // attached to "Full name" and assumes their name is broken.
        switch (e.code) {
          case 'UPLOAD_NOT_FOUND':
          case 'PHOTO_REQUIRED':
            _formError = e.message;
          case 'VALIDATION_FAILED':
            // Backend's VALIDATION_FAILED can mention any field —
            // inspect details.field if available, otherwise show at
            // the form level so we don't mislabel.
            final field = e.details?['field'] as String?;
            if (field == 'name') {
              _nameError = e.message;
            } else {
              _formError = e.message;
            }
          default:
            _formError = e.message;
        }
      });
      return;
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: palette.surface,
      // We manage the keyboard inset ourselves so the form stays
      // scrollable without the shell's bottom nav (overlaid on
      // HomeShell) being pushed up. The scroll padding below adds the
      // inset so the focused field scrolls clear of the keyboard.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg + keyboardInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The previous step (`liveness_capture_screen`) routes
              // here via `context.go(...)`, which REPLACES the nav
              // stack — so `Navigator.maybePop()` is a no-op. Pass an
              // explicit handler that walks the wizard back one step.
              BackButtonHeader(
                onPressed: () => context.go(RoutePaths.livenessCapture),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Tell us about yourself',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A real photo and your name help employers recognize you.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              if (_formError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _FormErrorBanner(
                  message: _formError!,
                  onRetakePhoto: () =>
                      context.go(RoutePaths.livenessCapture),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),

              // Profile photo upload
              const Center(child: _AvatarUpload()),
              const SizedBox(height: AppSpacing.xl),

              // Name
              _FieldLabel('Full name'),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: 'e.g. Tunde Adeyemi',
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                errorText: _nameError,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // Primary skill
              _FieldLabel('Primary skill'),
              const SizedBox(height: AppSpacing.sm),
              _SkillDropdown(
                value: _skill,
                onChanged: (JobType v) => setState(() => _skill = v),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Preferred radius
              _FieldLabel('Preferred work radius'),
              const SizedBox(height: AppSpacing.xs),
              _RadiusSlider(
                value: _radiusKm,
                onChanged: (double v) => setState(() => _radiusKm = v),
              ),

              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Continue',
                isLoading: _submitting,
                onPressed: _continue,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Escape hatch — if profile-setup keeps failing (e.g.
              // backend is returning UPLOAD_NOT_FOUND on the photo
              // and the worker can't make progress), let them log
              // out and return to the login screen instead of being
              // trapped here.
              Center(
                child: AppTextButton(
                  label: 'Sign out and start over',
                  onPressed: _submitting ? null : _signOutAndStartOver,
                  dense: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(color: palette.onSurface),
    );
  }
}

/// Avatar tile on profile-setup.
///
/// Displays the verified liveness selfie captured in the previous
/// step (read from [signupAvatarLocalPathProvider]). Tap routes back
/// to [LivenessCaptureScreen] so the user can retake — the capture
/// flow is the single source of truth for "what photo represents
/// this worker", and we don't want a second un-verified picker on
/// this screen drifting from that.
class _AvatarUpload extends ConsumerWidget {
  const _AvatarUpload();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    const double size = 132;
    final localPath = ref.watch(signupAvatarLocalPathProvider);
    final hasPhoto = localPath != null && localPath.isNotEmpty;

    return Semantics(
      button: true,
      label: hasPhoto ? 'Retake profile photo' : 'Take profile photo',
      child: GestureDetector(
        onTap: () => context.go(RoutePaths.livenessCapture),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: palette.surfaceContainerHigh,
                shape: BoxShape.circle,
                border: Border.all(color: palette.outline, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasPhoto
                  ? Image.file(
                      File(localPath),
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                    )
                  : Icon(
                      Icons.person_rounded,
                      size: size * 0.5,
                      color: palette.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 3),
                ),
                child: Icon(
                  hasPhoto
                      ? Icons.refresh_rounded
                      : Icons.camera_alt_rounded,
                  size: 18,
                  color: palette.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillDropdown extends StatelessWidget {
  const _SkillDropdown({required this.value, required this.onChanged});

  final JobType value;
  final ValueChanged<JobType> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outline, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<JobType>(
          value: value,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.onSurfaceVariant,
          ),
          style: AppTextStyles.bodyLarge.copyWith(color: palette.onSurface),
          dropdownColor: palette.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onChanged: (JobType? v) {
            if (v != null) onChanged(v);
          },
          items: <DropdownMenuItem<JobType>>[
            for (final JobType t in JobType.values)
              DropdownMenuItem<JobType>(
                value: t,
                child: Row(
                  children: <Widget>[
                    Text(t.emoji),
                    const SizedBox(width: AppSpacing.md),
                    Text(t.label),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadiusSlider extends StatelessWidget {
  const _RadiusSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              '${value.toStringAsFixed(0)} km',
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                value <= 5
                    ? 'Tight radius — fewer jobs'
                    : value <= 12
                        ? 'Balanced'
                        : 'Wide net — longer travel',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: palette.primary,
            inactiveTrackColor: palette.outline,
            thumbColor: palette.primary,
            overlayColor: palette.primary.withValues(alpha: 0.10),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: Slider(
            value: value,
            min: 1,
            max: 20,
            divisions: 19,
            label: '${value.toStringAsFixed(0)} km',
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '1 km',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              Text(
                '20 km',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Top-of-form error pill. Used for failures that aren't about a
/// specific field — most commonly an expired or unrecognised
/// `photo_upload_id` returned by `POST /v1/auth/profile-setup`.
/// When the cause is photo-shaped we also show a "Retake photo" link
/// that bounces the worker back to the liveness capture screen so
/// the next attempt mints a fresh upload id.
class _FormErrorBanner extends StatelessWidget {
  const _FormErrorBanner({
    required this.message,
    required this.onRetakePhoto,
  });

  final String message;
  final VoidCallback onRetakePhoto;

  bool get _isPhotoError {
    final m = message.toLowerCase();
    return m.contains('photo') || m.contains('upload');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: palette.error.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: palette.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_isPhotoError) ...<Widget>[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onRetakePhoto,
                    child: Text(
                      'Retake photo',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.error,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
