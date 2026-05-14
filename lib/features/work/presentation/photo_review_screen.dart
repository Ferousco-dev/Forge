import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../state/work_session_controller.dart';

/// Photo review.
///
/// Shows the captured "photo" (a placeholder block in static UI) plus
/// the two verification badges that the backend would compute server-
/// side: location verified (geofence match) and time verified (work
/// duration ≥ minimum). Submit advances to the upload screen; Retake
/// returns to the camera and clears the captured flag.
class PhotoReviewScreen extends ConsumerWidget {
  const PhotoReviewScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final session = ref.watch(workSessionForJobProvider(jobId));

    // No photo on this route is unreachable in the happy path — the
    // camera only pushes here AFTER a successful capture. But the
    // screen can still be landed on with no photo if:
    //   * the user retakes, comes back here, then back-navigates
    //     into history;
    //   * the OS killed and restored the app while sitting on /review
    //     before the photo was committed.
    // Either way the right recovery is "go back to the camera," not
    // a dead empty state. Schedule a pop on the next frame (can't
    // navigate during build).
    if (session == null || !session.photoCaptured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          // No camera in the back stack — fall back to the jobs root
          // so the user isn't stranded.
          context.go(RoutePaths.jobs);
        }
      });
      return Scaffold(
        backgroundColor: palette.surface,
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // Top bar.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () {
                      ref
                          .read(workSessionProvider.notifier)
                          .retakePhoto(jobId);
                      Navigator.of(context).maybePop();
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Review',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        child: session.photoPath != null
                            ? LayoutBuilder(
                                builder: (BuildContext _,
                                    BoxConstraints constraints) {
                                  // Decode the JPEG straight to the
                                  // pixel size we'll paint at instead
                                  // of the full 2048×2048 capture.
                                  // Skipping this caused a
                                  // ~16 MP → ~64 MB RGBA decode on the
                                  // UI thread, long enough to trip
                                  // Android's ANR watchdog. devicePixelRatio
                                  // keeps the result crisp on hi-DPI
                                  // screens; clamped so we never ask
                                  // for *more* than the source has.
                                  final dpr = MediaQuery.devicePixelRatioOf(
                                      context);
                                  final cacheW = (constraints.maxWidth *
                                          dpr)
                                      .round()
                                      .clamp(1, 2048);
                                  return Image.file(
                                    File(session.photoPath!),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    cacheWidth: cacheW,
                                    filterQuality: FilterQuality.medium,
                                    errorBuilder: (_, _, _) =>
                                        const _PhotoPlaceholder(),
                                  );
                                },
                              )
                            : const _PhotoPlaceholder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _VerificationRow(),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),

            // CTAs.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SecondaryButton(
                        label: 'Retake',
                        onPressed: () {
                          ref
                              .read(workSessionProvider.notifier)
                              .retakePhoto(jobId);
                          context.pop();
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Submit',
                        onPressed: () => context.pushReplacement(
                          RoutePaths.jobClockOutSubmitting(jobId),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            palette.surfaceContainerHigh,
            palette.outlineVariant,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.image_rounded,
            size: 56,
            color: palette.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Captured photo',
            style: AppTextStyles.labelMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationRow extends StatelessWidget {
  const _VerificationRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(
          child: _VerifyTile(
            icon: Icons.location_on_rounded,
            label: 'Location verified',
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: _VerifyTile(
            icon: Icons.schedule_rounded,
            label: 'Time verified',
          ),
        ),
      ],
    );
  }
}

class _VerifyTile extends StatelessWidget {
  const _VerifyTile({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: palette.success.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.check_circle_rounded,
                  size: 18, color: palette.success),
              const SizedBox(width: AppSpacing.xs),
              Icon(icon, size: 16, color: palette.success),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMedium.copyWith(
              color: palette.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
