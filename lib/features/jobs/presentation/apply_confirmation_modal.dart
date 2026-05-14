import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/distance_text.dart';
import '../../../shared/widgets/primary_button.dart';
import '../state/jobs_state.dart';
import '../../work/state/applications_state.dart';

/// Opens the apply confirmation modal as a bottom sheet, returning
/// `true` when the user confirms.
///
/// Caller is responsible for any post-confirmation side effect — this
/// helper just shows the sheet and surfaces the success snackbar.
Future<bool?> showApplyConfirmation(BuildContext context, Job job) {
  final palette = context.palette;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: palette.surface,
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (BuildContext sheetContext) => _ApplyConfirmationSheet(job: job),
  ).then((bool? confirmed) {
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(AppSpacing.base),
            backgroundColor: palette.surfaceContainerHigh,
            content: Text(
              "Application sent. We'll let you know when "
              "${job.employer.name} responds.",
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.onSurface,
              ),
            ),
          ),
        );
    }
    return confirmed;
  });
}

class _ApplyConfirmationSheet extends ConsumerStatefulWidget {
  const _ApplyConfirmationSheet({required this.job});
  final Job job;

  @override
  ConsumerState<_ApplyConfirmationSheet> createState() =>
      _ApplyConfirmationSheetState();
}

class _ApplyConfirmationSheetState
    extends ConsumerState<_ApplyConfirmationSheet> {
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(jobsRepositoryProvider)
          .apply(jobId: widget.job.id);
      // Force the active-applications list to re-fetch on next read so
      // the new application shows up in /me/applications without a
      // cold start.
      ref.invalidate(activeApplicationsProvider);
      ref.invalidate(jobDetailProvider(widget.job.id));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.sm),
            // Drag handle.
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.outline,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Title.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Apply for this job?',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "By applying, you agree to arrive on time and "
                    "complete the work as described.",
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Recap card.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.base),
                background: palette.surfaceContainerHigh,
                borderColor: palette.outlineVariant,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: palette.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            widget.job.locationAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        CurrencyText(
                          amount: widget.job.payAmount,
                          size: CurrencySize.medium,
                        ),
                        const Spacer(),
                        DistanceText.travel(
                          meters: widget.job.distanceMeters,
                          travelMinutes: widget.job.distanceMeters > 1500
                              ? widget.job.travelTimeDrivingMinutes
                              : widget.job.travelTimeWalkingMinutes,
                          mode: widget.job.distanceMeters > 1500
                              ? TravelMode.driving
                              : TravelMode.walking,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Buttons.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  if (_error != null) ...<Widget>[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  PrimaryButton(
                    label: 'Apply',
                    isLoading: _submitting,
                    onPressed: _confirm,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextButton(
                    label: 'Cancel',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    color: palette.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
