import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/ai/ai_models.dart';
import '../../../core/ai/ai_state.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../core/uploads/uploads_repository.dart';
import '../../../core/uploads/uploads_state.dart';
import '../state/profile_state.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/network_image_with_fallback.dart';
import '../../../shared/widgets/primary_button.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final TextEditingController _name = TextEditingController();
  JobType? _skill;
  double? _radius;
  bool _initialized = false;
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _hydrate(Worker w) {
    if (_initialized) return;
    _initialized = true;
    _name.text = w.name;
    final match = JobType.values.firstWhere(
      (JobType t) => t.label.toLowerCase() == w.primarySkill.toLowerCase(),
      orElse: () => JobType.generalLabor,
    );
    _skill = match;
    // Slider min/max is 1–20km. Backend can hand back `0.0` for
    // workers who never set a radius; treat that as "use the default".
    final raw = w.preferredRadiusKm;
    _radius = (raw <= 0) ? 5.0 : raw.clamp(1.0, 20.0).toDouble();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name can\'t be empty.');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    try {
      await ref.read(profileRepositoryProvider).patchMe(
            name: name,
            primarySkill: _skill?.label,
            preferredRadiusKm: _radius,
          );
      // Re-fetch /me so every screen that watches the worker sees the
      // new name / skill / radius without a manual refresh.
      ref.invalidate(currentWorkerProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameError = e.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final palette = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        backgroundColor: palette.surfaceContainerHigh,
        content: Text(
          'Profile saved.',
          style: TextStyle(color: palette.onSurface),
        ),
      ));
    context.pop();
  }

  /// Opens the AI auto-fill sheet. The worker types a one-line
  /// self-description; the server returns a structured [ProfileDraft]
  /// that we apply to the form. The worker still presses Save to
  /// commit — this is purely a typing shortcut, never a save shortcut.
  Future<void> _runAiExtract() async {
    final draft = await _showAiExtractSheet(context);
    if (!mounted || draft == null || draft.isEmpty) return;
    setState(() {
      if (draft.name != null && draft.name!.isNotEmpty) {
        _name.text = draft.name!;
        _name.selection = TextSelection.collapsed(offset: _name.text.length);
        _nameError = null;
      }
      if (draft.primarySkill != null) {
        _skill = draft.primarySkill;
      }
      if (draft.preferredRadiusKm != null) {
        _radius = draft.preferredRadiusKm!
            .clamp(1, 20)
            .toDouble();
      }
    });
    if (mounted) {
      final palette = context.palette;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.base),
          backgroundColor: palette.surfaceContainerHigh,
          content: Text(
            'Filled what we could — review and Save when ready.',
            style: TextStyle(color: palette.onSurface),
          ),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final asyncWorker = ref.watch(currentWorkerProvider);

    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: palette.surface,
      // Don't let Scaffold resize when the keyboard appears — we manage
      // the inset ourselves so the sticky button can ride above the
      // keyboard and the form stays scrollable behind it.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: asyncWorker.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object _, StackTrace _) => Column(
            children: <Widget>[
              const BackButtonHeader(),
              const Expanded(
                child: EmptyStateView(
                  title: 'Profile temporarily unavailable',
                  subtitle: 'Try again in a moment.',
                ),
              ),
            ],
          ),
          data: (Worker w) {
            _hydrate(w);
            final bool kbOpen = keyboardInset > 0;
            return Column(
              children: <Widget>[
                _TopBar(),
                // Form scrolls in the remaining vertical space. No
                // reserved padding for the button — it lives below as
                // the next sibling so empty space below the keyboard
                // never appears.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: AppSpacing.md),
                        Center(child: _AvatarEdit(worker: w)),
                        const SizedBox(height: AppSpacing.lg),
                        // Optional: describe yourself in one line and
                        // let AI fill the form. Soft-fails — any error
                        // keeps the manual form usable.
                        _AiAutofillCard(onTap: _runAiExtract),
                        const SizedBox(height: AppSpacing.xl),
                        _Label('Full name'),
                        const SizedBox(height: AppSpacing.sm),
                        AppTextField(
                          label: 'Your full name',
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
                        _Label('Phone number'),
                        const SizedBox(height: AppSpacing.sm),
                        _PhoneRow(phone: w.phoneNumber),
                        const SizedBox(height: AppSpacing.lg),
                        _Label('Primary skill'),
                        const SizedBox(height: AppSpacing.sm),
                        _SkillDropdown(
                          value: _skill ?? JobType.generalLabor,
                          onChanged: (JobType v) =>
                              setState(() => _skill = v),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _Label('Preferred work radius'),
                        const SizedBox(height: AppSpacing.xs),
                        _RadiusSlider(
                          value: (_radius ?? 5).clamp(1.0, 20.0).toDouble(),
                          onChanged: (double v) =>
                              setState(() => _radius = v),
                          accent: palette.primary,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
                // Sticky Save button. Padded by the keyboard inset so
                // it rides up above the keyboard when typing, and
                // respects the system bottom inset when dismissed.
                Padding(
                  padding: EdgeInsets.only(bottom: keyboardInset),
                  child: _StickyButton(
                    saving: _saving,
                    onPressed: _save,
                    applySafeArea: !kbOpen,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const BackButtonHeader(),
          Expanded(
            child: Text(
              'Edit profile',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
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

/// Editable avatar tile.
///
/// Tap → action sheet (Take photo / Choose from gallery) →
/// [ImagePicker] → `POST /uploads?purpose=worker_avatar` →
/// `PATCH /me { photo_upload_id }`. The trusted (non-liveness)
/// upload path is the right call here — the worker has already
/// passed liveness during signup; this is a routine self-edit.
///
/// While the upload is in-flight the camera badge swaps to a tiny
/// spinner and taps are ignored so the user can't fire a second
/// upload mid-flight.
class _AvatarEdit extends ConsumerStatefulWidget {
  const _AvatarEdit({required this.worker});
  final Worker worker;

  @override
  ConsumerState<_AvatarEdit> createState() => _AvatarEditState();
}

class _AvatarEditState extends ConsumerState<_AvatarEdit> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    final source = await _pickSource();
    if (source == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final XFile? shot = await _picker.pickImage(
        source: source,
        // Cap upload size up front — server still validates, but no
        // sense shipping a 4032×3024 photo over a flaky connection.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (shot == null) {
        // User backed out — leave state untouched.
        if (mounted) setState(() => _busy = false);
        return;
      }

      final file = File(shot.path);
      final bytes = await file.readAsBytes();
      final filename = file.uri.pathSegments.isEmpty
          ? 'avatar.jpg'
          : file.uri.pathSegments.last;
      final lower = filename.toLowerCase();
      final contentType = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.heic')
              ? 'image/heic'
              : 'image/jpeg';

      // 1. Generic upload (NOT liveness — that path runs AI checks
      //    synchronously and is reserved for the signup selfie). The
      //    edit path skips verification.
      final handle =
          await ref.read(uploadsRepositoryProvider).upload(
                purpose: UploadPurpose.workerAvatar,
                bytes: bytes,
                filename: filename,
                contentType: contentType,
              );

      // 2. Promote the uploaded file to the worker's avatar.
      await ref
          .read(profileRepositoryProvider)
          .patchMe(photoUploadId: handle.id);

      // 3. Refresh /me so the new photo flows back through the rest of
      //    the app (header avatar, profile screen, job-detail employer
      //    block — wherever `currentWorkerProvider` is read).
      ref.invalidate(currentWorkerProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.base),
          content: const Text('Profile photo updated.'),
        ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppSpacing.base),
          backgroundColor: context.palette.surfaceContainerHigh,
          content: Text(
            e.message,
            style: TextStyle(color: context.palette.error),
          ),
        ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(AppSpacing.base),
          content: Text("Couldn't read that image. Try again."),
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bottom-sheet source picker. Returning `null` means the user
  /// dismissed the sheet without choosing — caller leaves state alone.
  Future<ImageSource?> _pickSource() {
    final palette = context.palette;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheet) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.outline,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                leading:
                    Icon(Icons.camera_alt_rounded, color: palette.primary),
                title: const Text('Take photo'),
                onTap: () =>
                    Navigator.of(sheet).pop(ImageSource.camera),
              ),
              ListTile(
                leading:
                    Icon(Icons.photo_library_rounded, color: palette.primary),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.of(sheet).pop(ImageSource.gallery),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        NetworkImageWithFallback(
          imageUrl: widget.worker.photoUrl,
          size: 120,
          fallbackInitial: widget.worker.name,
        ),
        Material(
          color: palette.primary,
          shape:
              CircleBorder(side: BorderSide(color: palette.surface, width: 3)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _busy ? null : _onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: _busy
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          palette.onPrimary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_rounded,
                      size: 18,
                      color: palette.onPrimary,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md + 4,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              phone,
              style: AppTextStyles.bodyLarge.copyWith(
                color: palette.onSurface,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
          AppTextButton(
            label: 'Change',
            onPressed: () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.all(AppSpacing.base),
                  content: Text('Phone change requires re-verification.'),
                ));
            },
            dense: true,
          ),
        ],
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
        border: Border.all(color: palette.outline),
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
  const _RadiusSlider({
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${value.toStringAsFixed(0)} km',
          style: AppTextStyles.titleLarge.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: palette.outline,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.10),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: Slider(
            value: value,
            min: 1,
            max: 20,
            divisions: 19,
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

class _StickyButton extends StatelessWidget {
  const _StickyButton({
    required this.saving,
    required this.onPressed,
    this.applySafeArea = true,
  });
  final bool saving;
  final VoidCallback onPressed;

  /// When the keyboard is open we suppress the SafeArea bottom inset
  /// — the keyboard already separates the button from the device
  /// gesture pill, and adding the inset just shows blank space.
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: applySafeArea,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: PrimaryButton(
            label: 'Save changes',
            isLoading: saving,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// AI auto-fill — entry card + sheet
// ---------------------------------------------------------------------

/// Inline call-to-action above the form. Soft-fails: if the worker
/// taps it but the AI is down, the sheet shows an error and they
/// fall back to filling the form manually.
class _AiAutofillCard extends StatelessWidget {
  const _AiAutofillCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: palette.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Describe yourself in one line',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'We\'ll fill the form. You review and Save.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal sheet that takes a free-form description, calls the AI
/// extract endpoint, and returns a [ProfileDraft] (or null if the
/// worker dismissed).
Future<ProfileDraft?> _showAiExtractSheet(BuildContext context) {
  return showModalBottomSheet<ProfileDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext _) => const _AiExtractSheet(),
  );
}

class _AiExtractSheet extends ConsumerStatefulWidget {
  const _AiExtractSheet();

  @override
  ConsumerState<_AiExtractSheet> createState() => _AiExtractSheetState();
}

class _AiExtractSheetState extends ConsumerState<_AiExtractSheet> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _text.text.trim();
    if (t.length < 10) {
      setState(() => _error =
          'Tell us a bit more — your name, what you do, and where you live.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await ref.read(aiRepositoryProvider).extractProfile(t);
      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't process that — fill the form below.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mediaInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        // ScrollView absorbs the keyboard inset as bottom padding —
        // this keeps the sheet anchored to the bottom while letting
        // the input scroll into view above the keyboard.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg + mediaInset,
          ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: palette.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: palette.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Tell us about yourself',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'One or two sentences. Example: "I\'m Tunde, I drive trucks. '
                  'I live in Surulere, willing to travel up to 10km."',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Description',
                  controller: _text,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  errorText: _error,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: _busy ? 'Reading…' : 'Fill the form',
                  isLoading: _busy,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'I\'ll type it manually',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

