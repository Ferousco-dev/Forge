import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../work/data/applications_repository.dart';
import '../../work/state/applications_state.dart';
import '../data/job_receipt_pdf.dart';

/// Receipt-style detail for a completed job.
///
/// The work-history list used to deeplink each row into the live
/// `/jobs/:id` page, which 404s once the listing is no longer in the
/// active feed — the worker hit "Couldn't load this job". This screen
/// replaces that destination: it reads `applicationDetailProvider`
/// (which talks to `/applications/:id`, a stable endpoint that
/// survives job lifecycle changes) and renders a static receipt of
/// what the worker actually did, when, where, and what they were
/// paid.
///
/// AppBar carries a share button that builds a polished single-page
/// PDF receipt and routes it through the OS share sheet — for saving
/// to Files / Downloads or sending to a bank, supervisor, landlord
/// as proof of work + payment.
class CompletedJobScreen extends ConsumerStatefulWidget {
  const CompletedJobScreen({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<CompletedJobScreen> createState() =>
      _CompletedJobScreenState();
}

class _CompletedJobScreenState extends ConsumerState<CompletedJobScreen> {
  /// True while the share / preview is building the PDF. Disables the
  /// AppBar action so a double-tap can't fire two share sheets.
  bool _exporting = false;

  Future<({JobApplication application, WorkSessionRecord? session})?>
      _resolveCurrent() async {
    final detail =
        ref.read(applicationDetailProvider(widget.applicationId)).valueOrNull;
    if (detail != null) {
      return (application: detail.application, session: detail.session);
    }
    // Fall back to the cached history list if the detail fetch hasn't
    // resolved yet — we'd rather export a slim receipt than nothing.
    final cached = ref.read(applicationHistoryProvider).valueOrNull;
    if (cached == null) return null;
    for (final JobApplication a in cached) {
      if (a.id == widget.applicationId) {
        return (application: a, session: null);
      }
    }
    return null;
  }

  Future<({Uint8List bytes, String filename})?> _buildPdf({
    required JobApplication application,
    required WorkSessionRecord? session,
  }) async {
    try {
      final worker = await ref.read(currentWorkerProvider.future);
      final bytes = await const JobReceiptPdf().build(
        application: application,
        session: session,
        worker: worker,
      );
      final slug = application.job.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final filename =
          'forge-receipt-${slug.isEmpty ? application.id : slug}.pdf';
      return (bytes: bytes, filename: filename);
    } catch (_) {
      return null;
    }
  }

  Future<void> _share() async {
    if (_exporting) return;
    final current = await _resolveCurrent();
    if (current == null) {
      _snack("Couldn't load the receipt yet — try again in a moment.");
      return;
    }
    setState(() => _exporting = true);
    final result = await _buildPdf(
      application: current.application,
      session: current.session,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _exporting = false);
      _snack("Couldn't build the receipt — try again.");
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${result.filename}');
    await file.writeAsBytes(result.bytes, flush: true);
    if (!mounted) return;
    setState(() => _exporting = false);
    await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Forge receipt — ${current.application.job.title}',
    );
  }

  Future<void> _preview() async {
    if (_exporting) return;
    final current = await _resolveCurrent();
    if (current == null) {
      _snack("Couldn't load the receipt yet — try again in a moment.");
      return;
    }
    setState(() => _exporting = true);
    final result = await _buildPdf(
      application: current.application,
      session: current.session,
    );
    if (!mounted) return;
    setState(() => _exporting = false);
    if (result == null) {
      _snack("Couldn't build the receipt — try again.");
      return;
    }
    await Printing.layoutPdf(
      onLayout: (_) async => result.bytes,
      name: result.filename,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        content: Text(msg),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final detailAsync =
        ref.watch(applicationDetailProvider(widget.applicationId));

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Completed job'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Share receipt',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
            onPressed: _exporting ? null : _share,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: detailAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          // On error, try to render from whatever the work-history list
          // has cached locally. That way a worker who tapped a row a
          // second ago still sees something useful instead of an empty
          // error state.
          error: (Object _, StackTrace _) {
            final cached =
                ref.read(applicationHistoryProvider).valueOrNull;
            final fallback = cached?.firstWhere(
              (JobApplication a) => a.id == widget.applicationId,
              orElse: () =>
                  cached.isEmpty ? _missingPlaceholder() : cached.first,
            );
            if (fallback != null && fallback.id == widget.applicationId) {
              return _Receipt(
                application: fallback,
                session: null,
                exporting: _exporting,
                onPreview: _preview,
                onShare: _share,
              );
            }
            return _ErrorState(
              onRetry: () => ref.invalidate(
                applicationDetailProvider(widget.applicationId),
              ),
            );
          },
          data: (ApplicationDetail detail) => _Receipt(
            application: detail.application,
            session: detail.session,
            exporting: _exporting,
            onPreview: _preview,
            onShare: _share,
          ),
        ),
      ),
    );
  }
}

JobApplication _missingPlaceholder() => throw StateError(
      'completed_job_screen: fallback called with empty cache',
    );

class _Receipt extends StatelessWidget {
  const _Receipt({
    required this.application,
    required this.session,
    required this.exporting,
    required this.onPreview,
    required this.onShare,
  });

  final JobApplication application;
  final WorkSessionRecord? session;

  /// True while a PDF build/share is in flight — the buttons disable
  /// themselves so we don't kick off two share sheets in parallel.
  final bool exporting;
  final Future<void> Function() onPreview;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    final job = application.job;
    final completedAt = application.completedAt ?? session?.clockOutAt;
    final clockInAt = session?.clockInAt;
    final durationHoursWorked = session?.durationHoursWorked ?? 0.0;
    final paid =
        (session?.payAmountDisbursed ?? 0) > 0
            ? session!.payAmountDisbursed
            : job.payAmount;
    final transactionId = session?.transactionId;
    final disputed = session?.verificationState ==
        WorkSessionVerificationState.disputed;

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Hero(amountPaid: paid, disputed: disputed),
                const SizedBox(height: AppSpacing.xl),
                _JobSummaryCard(job: job),
                const SizedBox(height: AppSpacing.lg),
                _DetailsCard(
                  completedAt: completedAt,
                  clockInAt: clockInAt,
                  durationHoursWorked: durationHoursWorked,
                  postedDurationHours: job.durationHours,
                  paid: paid,
                  disputed: disputed,
                  applicationId: application.id,
                ),
                if (job.requiredEquipment.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  _EquipmentCard(equipment: job.requiredEquipment),
                ],
                const SizedBox(height: AppSpacing.lg),
                _EmployerRow(
                  employer: job.employer,
                ),
                const SizedBox(height: AppSpacing.lg),
                _ExportCard(
                  exporting: exporting,
                  onPreview: onPreview,
                  onShare: onShare,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              children: <Widget>[
                if (transactionId != null && transactionId.isNotEmpty)
                  PrimaryButton(
                    label: 'View payment',
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    onPressed: () => context.push(
                      RoutePaths.transactionDetail(transactionId),
                    ),
                  )
                else
                  PrimaryButton(
                    label: 'View earnings',
                    onPressed: () => context.go(RoutePaths.earnings),
                  ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'About the employer',
                  onPressed: () => context.push(
                    RoutePaths.employerDetail(job.employer.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.amountPaid, required this.disputed});
  final int amountPaid;
  final bool disputed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = disputed ? palette.warning : palette.success;
    final headline = disputed ? 'Disputed' : 'Job complete';
    final caption = disputed
        ? "Your employer flagged this clock-out. We're reviewing it."
        : "You did the work. Here's the record.";
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            disputed
                ? Icons.gavel_rounded
                : Icons.check_circle_rounded,
            size: 56,
            color: tint,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
        if (!disputed) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          CurrencyText(
            amount: amountPaid,
            size: CurrencySize.large,
            tone: CurrencyTone.credit,
          ),
        ],
      ],
    );
  }
}

class _JobSummaryCard extends StatelessWidget {
  const _JobSummaryCard({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            job.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            job.employer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: palette.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  job.locationAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.completedAt,
    required this.clockInAt,
    required this.durationHoursWorked,
    required this.postedDurationHours,
    required this.paid,
    required this.disputed,
    required this.applicationId,
  });

  final DateTime? completedAt;
  final DateTime? clockInAt;
  final double durationHoursWorked;
  final int postedDurationHours;

  final int paid;
  final bool disputed;
  final String applicationId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dateFmt = DateFormat('EEE, MMM d, y · h:mm a');
    final hoursLabel = _formatHours(durationHoursWorked, postedDurationHours);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Row(
            label: 'Status',
            value: disputed ? 'Disputed · under review' : 'Completed',
            valueColor: disputed ? palette.warning : palette.success,
          ),
          if (completedAt != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _Row(
              label: 'Completed',
              value: dateFmt.format(completedAt!.toLocal()),
            ),
          ],
          if (clockInAt != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _Row(
              label: 'Clocked in',
              value: dateFmt.format(clockInAt!.toLocal()),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _Row(label: 'Time on the job', value: hoursLabel),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          _Row(
            label: 'Paid',
            value: _ngn(paid),
            emphasised: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            label: 'Application',
            value: applicationId,
            monospaced: true,
          ),
        ],
      ),
    );
  }

  static String _formatHours(double worked, int posted) {
    if (worked > 0) {
      if (worked >= 1) {
        final h = worked.toInt();
        final m = ((worked - h) * 60).round();
        return m == 0 ? '${h}h' : '${h}h ${m}m';
      }
      final mins = (worked * 60).round();
      return '${mins}m';
    }
    if (posted > 0) return '${posted}h';
    return '—';
  }

  static String _ngn(int amount) {
    final fmt = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    return fmt.format(amount);
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.equipment});
  final List<String> equipment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Equipment used',
            style: AppTextStyles.labelMedium.copyWith(
              color: palette.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final String item in equipment)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    item,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: palette.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmployerRow extends StatelessWidget {
  const _EmployerRow({required this.employer});
  final Employer employer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.business_rounded,
              color: palette.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Worked for',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  employer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline export panel — "Save receipt" + "Preview" affordances. Sits
/// inside the scroll body so the worker can find them without hunting
/// for the small icon in the AppBar.
class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.exporting,
    required this.onPreview,
    required this.onShare,
  });

  final bool exporting;
  final Future<void> Function() onPreview;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      borderColor: palette.primary.withValues(alpha: 0.20),
      background: palette.primary.withValues(alpha: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: palette.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Save or share this receipt',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PDF · sized for printing, looks clean on phone',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Save or share',
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            isLoading: exporting,
            onPressed: exporting ? null : onShare,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Preview',
            onPressed: exporting ? null : onPreview,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasised = false,
    this.monospaced = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasised;
  final bool monospaced;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: (emphasised
                    ? AppTextStyles.titleSmall
                    : AppTextStyles.bodyMedium)
                .copyWith(
              color: valueColor ?? palette.onSurface,
              fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: monospaced
                  ? const <FontFeature>[FontFeature.tabularFigures()]
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      title: "Couldn't load this receipt",
      subtitle: 'Try again — your record is safe.',
      illustration: const Icon(Icons.error_outline_rounded, size: 56),
      action: SizedBox(
        width: 200,
        child: PrimaryButton(
          label: 'Try again',
          onPressed: onRetry,
        ),
      ),
    );
  }
}
