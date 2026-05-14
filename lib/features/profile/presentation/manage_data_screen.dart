import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../data/data_export_service.dart';

/// "Manage your data" — GDPR-style data hub.
///
/// Two affordances:
///   1. **Download my data.** Builds a PDF with every record the worker
///      has visible inside the app (profile, stats, work history,
///      transactions, linked banks, credit factors) and offers Save /
///      Share / Preview. Pure client-side compose; pulls from the
///      already-fetched providers so it works on a flaky connection.
///   2. **Request deletion.** Walks the worker through a confirmation
///      dialog and signals the backend (today: stubbed snackbar — the
///      real DELETE endpoint plugs in here when the backend ships it).
class ManageDataScreen extends ConsumerStatefulWidget {
  const ManageDataScreen({super.key});

  @override
  ConsumerState<ManageDataScreen> createState() => _ManageDataScreenState();
}

class _ManageDataScreenState extends ConsumerState<ManageDataScreen> {
  bool _generating = false;
  String? _error;

  Future<({Uint8List bytes, String filename})?> _buildPdf() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      // Resolve every provider that holds worker-scoped data. Each is
      // awaited so the PDF is built off the freshest snapshot rather
      // than whatever was cached at screen-open time. A worker who
      // taps Download right after completing a job sees that job in
      // the export.
      final worker = await ref.read(currentWorkerProvider.future);
      final history = await _safeList(
        () => ref.read(applicationHistoryProvider.future),
      );
      final active = await _safeList(
        () => ref.read(activeApplicationsProvider.future),
      );
      final transactions = await _safeList(
        () => ref.read(transactionsProvider.future),
      );
      final banks = await _safeList(
        () => ref.read(bankAccountsProvider.future),
      );
      final credit = await _safeOne(
        () => ref.read(creditProfileProvider.future),
      );

      final bytes = await const DataExportService().buildExport(
        worker: worker,
        workHistory: history,
        activeApplications: active,
        transactions: transactions,
        bankAccounts: banks,
        credit: credit,
      );

      final filename = _filenameFor(worker);
      setState(() => _generating = false);
      return (bytes: bytes, filename: filename);
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error =
              "Couldn't build the export. Try again — your record is safe.";
        });
      }
      return null;
    }
  }

  Future<void> _download() async {
    final result = await _buildPdf();
    if (result == null || !mounted) return;
    // Write to the app's temp dir first; share_plus needs a real path
    // on Android to attach to the share intent. The OS cleans temp
    // files when it's tight on space; we don't keep references.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${result.filename}');
    await file.writeAsBytes(result.bytes, flush: true);
    if (!mounted) return;
    await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Your Forge data export',
    );
  }

  Future<void> _preview() async {
    final result = await _buildPdf();
    if (result == null || !mounted) return;
    await Printing.layoutPdf(
      onLayout: (_) async => result.bytes,
      name: result.filename,
    );
  }

  Future<void> _confirmDelete() async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'Delete your account?',
          style: AppTextStyles.titleLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        content: Text(
          "This permanently removes your work record, transaction "
          "history, and credit profile from Forge. You can't undo "
          "it. Make sure you've downloaded your data first.",
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: palette.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: palette.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.base),
        backgroundColor: palette.surfaceContainerHigh,
        content: Text(
          'Account deletion is queued (backend integration pending).',
          style: TextStyle(color: palette.onSurface),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: const Text('Manage your data'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Your record, in your hands.',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Take a snapshot of every record we have on you. "
                "You can save it, share it, or just look it over.",
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Download card.
              _DownloadCard(
                generating: _generating,
                error: _error,
                onDownload: _generating ? null : _download,
                onPreview: _generating ? null : _preview,
              ),
              const SizedBox(height: AppSpacing.lg),

              // What's included.
              _IncludedCard(),
              const SizedBox(height: AppSpacing.lg),

              // Delete card.
              _DeleteCard(onTap: _generating ? null : _confirmDelete),
            ],
          ),
        ),
      ),
    );
  }

  /// Read a list provider but never surface its error to the export —
  /// a single dead provider shouldn't block the rest of the PDF. The
  /// worker just sees an empty section for whatever failed.
  Future<List<T>> _safeList<T>(Future<List<T>> Function() fetch) async {
    try {
      return await fetch();
    } catch (_) {
      return <T>[];
    }
  }

  Future<T?> _safeOne<T>(Future<T> Function() fetch) async {
    try {
      return await fetch();
    } catch (_) {
      return null;
    }
  }

  /// `forge-export-<worker-id>-<date>.pdf`. Slug the worker name in
  /// case a teammate is reviewing multiple downloads in one folder.
  String _filenameFor(Worker w) {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final slug = w.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'forge-export-${slug.isEmpty ? w.id : slug}-$date.pdf';
  }
}

// ---------------------------------------------------------------------
// Download card
// ---------------------------------------------------------------------

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.generating,
    required this.error,
    required this.onDownload,
    required this.onPreview,
  });

  final bool generating;
  final String? error;
  final VoidCallback? onDownload;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.primary.withValues(alpha: 0.25),
      background: palette.primary.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: palette.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Download my data',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PDF · usually under a second',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Generate & share',
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            isLoading: generating,
            onPressed: onDownload,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Preview',
            onPressed: onPreview,
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// What's included
// ---------------------------------------------------------------------

class _IncludedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "What's in your file",
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final String row in _kBullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: palette.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      row,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.onSurface,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const List<String> _kBullets = <String>[
    'Profile — full name, phone, primary skill, signup date, worker ID',
    'Stats — jobs completed, total earned, wallet balance, reliability, credit score',
    'Work history — every completed job with employer, location, pay',
    'Active applications — anything you have in flight right now',
    'Transactions — every payment, withdrawal, and loan movement',
    'Linked banks — masked account numbers (last 4 digits only)',
    'Credit risk factors — the AI inputs pulling your score down',
  ];
}

// ---------------------------------------------------------------------
// Delete card
// ---------------------------------------------------------------------

class _DeleteCard extends StatelessWidget {
  const _DeleteCard({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      borderColor: palette.error.withValues(alpha: 0.25),
      background: palette.error.withValues(alpha: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.delete_outline_rounded,
                color: palette.error,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Request deletion',
                style: AppTextStyles.titleSmall.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "Permanently remove your account and every record we hold on "
            "you. Make sure you've downloaded your data first — once it's "
            "gone, we can't recover it.",
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Request deletion',
            color: palette.error,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}
