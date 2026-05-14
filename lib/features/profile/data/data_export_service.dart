import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/mock/models.dart';

/// Builds the worker's "Download my data" PDF.
///
/// Pure compute — no network calls. The caller hands us snapshots
/// already fetched by their respective providers so the export
/// reflects what's currently visible in the app. We never paginate
/// off the server inside this service; if the caller hands us 30
/// transactions, those are the 30 we render.
///
/// Output is a single `Uint8List` containing the PDF bytes. The
/// caller (typically `ManageDataScreen`) is responsible for handing
/// the bytes to `printing` for preview/save or `share_plus` for
/// share-sheet output.
class DataExportService {
  const DataExportService();

  /// Generate the PDF bytes from the supplied snapshots. Everything is
  /// optional except [worker] — the export is built around the
  /// authenticated worker's identity.
  ///
  /// Nulls are rendered as a "—" placeholder so a sparse worker
  /// record (fresh signup) still produces a valid PDF.
  Future<Uint8List> buildExport({
    required Worker worker,
    List<JobApplication> workHistory = const <JobApplication>[],
    List<JobApplication> activeApplications = const <JobApplication>[],
    List<Transaction> transactions = const <Transaction>[],
    List<BankAccount> bankAccounts = const <BankAccount>[],
    CreditProfile? credit,
    DateTime? generatedAt,
  }) async {
    final generated = generatedAt ?? DateTime.now();

    // Inter at runtime (Google Fonts) is fetched on demand; the PDF
    // engine can't await a Flutter font widget tree, so we ship the
    // pdf with the package's bundled Helvetica clone. That's correct
    // for export — fonts shouldn't depend on a flaky network.
    final pdf = pw.Document(
      title: 'Forge — data export — ${worker.name}',
      author: 'Forge',
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 48, 36, 36),
        header: (pw.Context _) => _header(worker: worker, generatedAt: generated),
        footer: (pw.Context ctx) => _footer(ctx),
        build: (pw.Context _) => <pw.Widget>[
          _section(
            title: 'Account',
            child: _accountBlock(worker),
          ),
          _section(
            title: 'Stats',
            child: _statsBlock(worker, credit: credit),
          ),
          if (bankAccounts.isNotEmpty)
            _section(
              title: 'Linked bank accounts',
              child: _banksBlock(bankAccounts),
            ),
          if (workHistory.isNotEmpty)
            _section(
              title: 'Work history (${workHistory.length})',
              child: _workHistoryBlock(workHistory),
            ),
          if (activeApplications.isNotEmpty)
            _section(
              title: 'Active applications (${activeApplications.length})',
              child: _applicationsBlock(activeApplications),
            ),
          if (transactions.isNotEmpty)
            _section(
              title: 'Transactions (${transactions.length})',
              child: _transactionsBlock(transactions),
            ),
          if (credit != null && credit.riskFactors.isNotEmpty)
            _section(
              title: 'Credit risk factors',
              child: _riskFactorsBlock(credit.riskFactors),
            ),
          _section(
            title: 'How to read this document',
            child: pw.Text(
              'This is a snapshot of every record visible to your '
              'account on Forge as of the timestamp on each page header. '
              "It mirrors what you can see in the app. If anything looks "
              "wrong, contact support — your record is editable up to "
              "the point a job is paid out.",
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // -----------------------------------------------------------------
  // Layout helpers
  // -----------------------------------------------------------------

  pw.Widget _header({
    required Worker worker,
    required DateTime generatedAt,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'FORGE',
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Data export',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  worker.name,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey800,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                'GENERATED',
                style: pw.TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.5,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                DateFormat('MMM d, y · h:mm a').format(generatedAt.toLocal()),
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Worker ID: ${worker.id}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context ctx) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'Forge — your work, your record.',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _section({required String title, required pw.Widget child}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.7),
              ),
            ),
            child: pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  pw.Widget _accountBlock(Worker w) {
    return _keyValueTable(<List<String>>[
      ['Full name', w.name],
      ['Phone number', w.phoneNumber],
      ['Primary skill', w.primarySkill],
      ['Joined', DateFormat('MMM d, y').format(w.joinedAt.toLocal())],
      ['Preferred radius', '${w.preferredRadiusKm.toStringAsFixed(1)} km'],
      ['Worker ID', w.id],
    ]);
  }

  pw.Widget _statsBlock(Worker w, {CreditProfile? credit}) {
    final ngn = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    final rows = <List<String>>[
      ['Jobs completed', '${w.jobsCompleted}'],
      ['Total earned', ngn.format(w.totalEarned)],
      ['Wallet balance', ngn.format(w.walletBalance)],
      ['Average rating', w.averageRating.toStringAsFixed(2)],
      ['Reliability score', '${w.reliabilityScore} / 100'],
      ['Credit score', '${w.creditScore} / 100'],
    ];
    if (credit != null) {
      if (credit.subtitle.isNotEmpty) {
        rows.add(['Credit tier', credit.subtitle]);
      }
      if (credit.lastEvaluatedAt != null) {
        rows.add([
          'Credit last evaluated',
          DateFormat('MMM d, y · h:mm a')
              .format(credit.lastEvaluatedAt!.toLocal()),
        ]);
      }
      final modelVersion = credit.modelVersion;
      if (modelVersion != null && modelVersion.isNotEmpty) {
        rows.add(['Credit model', modelVersion]);
      }
    }
    return _keyValueTable(rows);
  }

  pw.Widget _banksBlock(List<BankAccount> accounts) {
    return _dataTable(
      headers: <String>['Bank', 'Account', 'Holder', 'Default'],
      rows: <List<String>>[
        for (final BankAccount b in accounts)
          <String>[
            b.bankName,
            '****${_last4(b.accountNumber)}',
            b.accountName,
            b.isDefault ? 'Yes' : 'No',
          ],
      ],
    );
  }

  pw.Widget _workHistoryBlock(List<JobApplication> apps) {
    final ngn = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('MMM d, y');
    final rows = <List<String>>[];
    for (final JobApplication a in apps) {
      rows.add(<String>[
        a.completedAt != null
            ? dateFmt.format(a.completedAt!.toLocal())
            : dateFmt.format(a.appliedAt.toLocal()),
        a.job.title,
        a.job.employer.name,
        a.job.locationAddress,
        ngn.format(a.job.payAmount),
      ]);
    }
    return _dataTable(
      headers: <String>['Date', 'Job', 'Employer', 'Location', 'Pay'],
      rows: rows,
      // Location strings are long — give it room.
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(70),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(2.4),
        4: pw.FixedColumnWidth(60),
      },
    );
  }

  pw.Widget _applicationsBlock(List<JobApplication> apps) {
    final dateFmt = DateFormat('MMM d, y');
    final rows = <List<String>>[];
    for (final JobApplication a in apps) {
      rows.add(<String>[
        dateFmt.format(a.appliedAt.toLocal()),
        a.job.title,
        a.job.employer.name,
        _applicationStatusLabel(a.status),
      ]);
    }
    return _dataTable(
      headers: <String>['Applied', 'Job', 'Employer', 'Status'],
      rows: rows,
    );
  }

  pw.Widget _transactionsBlock(List<Transaction> txs) {
    final ngn = NumberFormat.currency(
      locale: 'en_NG',
      symbol: '₦',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('MMM d, y · h:mm a');
    final rows = <List<String>>[];
    for (final Transaction t in txs) {
      final signed = t.amount >= 0
          ? '+${ngn.format(t.amount)}'
          : '-${ngn.format(t.amount.abs())}';
      rows.add(<String>[
        dateFmt.format(t.timestamp.toLocal()),
        t.kind.label,
        t.title,
        signed,
      ]);
    }
    return _dataTable(
      headers: <String>['When', 'Kind', 'Description', 'Amount'],
      rows: rows,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(110),
        1: pw.FixedColumnWidth(80),
        2: pw.FlexColumnWidth(),
        3: pw.FixedColumnWidth(70),
      },
    );
  }

  pw.Widget _riskFactorsBlock(List<CreditRiskFactor> factors) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        for (final CreditRiskFactor f in factors) ...<pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  '• ${f.copy}',
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
                ),
              ),
              if (f.scoreImpact != null) ...<pw.Widget>[
                pw.SizedBox(width: 8),
                pw.Text(
                  '${f.scoreImpact! < 0 ? '' : '-'}${f.scoreImpact}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.red700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 6),
        ],
      ],
    );
  }

  pw.Widget _keyValueTable(List<List<String>> rows) {
    return pw.Table(
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.IntrinsicColumnWidth(),
        1: pw.FlexColumnWidth(),
      },
      children: <pw.TableRow>[
        for (final List<String> r in rows)
          pw.TableRow(
            children: <pw.Widget>[
              pw.Padding(
                padding: const pw.EdgeInsets.only(
                  right: 18,
                  top: 3,
                  bottom: 3,
                ),
                child: pw.Text(
                  r[0],
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  r[1].isEmpty ? '—' : r[1],
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _dataTable({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
      ),
      columnWidths: columnWidths,
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: <pw.Widget>[
            for (final String h in headers)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 5,
                  horizontal: 6,
                ),
                child: pw.Text(
                  h.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
        for (final List<String> r in rows)
          pw.TableRow(
            children: <pw.Widget>[
              for (final String cell in r)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  child: pw.Text(
                    cell.isEmpty ? '—' : cell,
                    style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _last4(String accountNumber) {
    if (accountNumber.length <= 4) return accountNumber;
    return accountNumber.substring(accountNumber.length - 4);
  }

  String _applicationStatusLabel(ApplicationStatus s) {
    switch (s) {
      case ApplicationStatus.applied:
        return 'Applied';
      case ApplicationStatus.accepted:
        return 'Accepted';
      case ApplicationStatus.inProgress:
        return 'In progress';
      case ApplicationStatus.completed:
        return 'Completed';
      case ApplicationStatus.rejected:
        return 'Rejected';
      case ApplicationStatus.withdrawn:
        return 'Withdrawn';
    }
  }
}
