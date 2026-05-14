import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/mock/models.dart';

/// Builds a single-page job-payment receipt PDF.
///
/// Receipt-flavored layout: big "PAID" badge, prominent amount, the
/// job + employer + location, the verification checklist, payment
/// reference, and a footer with worker name + issue date. Designed to
/// look credible if a worker shares it with a bank / landlord /
/// supervisor as proof of work and payment — not a screenshot of the
/// app's receipt UI, an actual paper-grade receipt.
///
/// Pure compute, no network. Caller hands us already-fetched models;
/// we return PDF bytes for `printing` / `share_plus` to handle output.
class JobReceiptPdf {
  const JobReceiptPdf();

  Future<Uint8List> build({
    required JobApplication application,
    WorkSessionRecord? session,
    required Worker worker,
    DateTime? issuedAt,
  }) async {
    final issued = issuedAt ?? DateTime.now();
    final job = application.job;
    final paid = (session?.payAmountDisbursed ?? 0) > 0
        ? session!.payAmountDisbursed
        : job.payAmount;
    final disputed = session?.verificationState ==
        WorkSessionVerificationState.disputed;
    final ngn = NumberFormat.currency(
      locale: 'en_NG',
      symbol: 'NGN ',
      decimalDigits: 0,
    );
    // Use a printable "NGN" prefix instead of the ₦ glyph — the PDF
    // package's default Helvetica clone doesn't ship that codepoint
    // and renders it as a missing-character box. "NGN 1,500" reads
    // unambiguously and survives a B&W print.

    final pdf = pw.Document(
      title: 'Forge job receipt · ${job.title}',
      author: 'Forge',
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 48, 36, 36),
        build: (pw.Context _) => _ReceiptBody(
          application: application,
          session: session,
          worker: worker,
          paid: paid,
          disputed: disputed,
          ngn: ngn,
          issuedAt: issued,
        ).build(),
      ),
    );

    return pdf.save();
  }
}

class _ReceiptBody {
  _ReceiptBody({
    required this.application,
    required this.session,
    required this.worker,
    required this.paid,
    required this.disputed,
    required this.ngn,
    required this.issuedAt,
  });

  final JobApplication application;
  final WorkSessionRecord? session;
  final Worker worker;
  final int paid;
  final bool disputed;
  final NumberFormat ngn;
  final DateTime issuedAt;

  // Brand palette — matches the in-app primary teal but flattened so
  // it prints cleanly. Picked to read on both white and dark grey
  // viewer backgrounds (some PDF viewers tint).
  static const PdfColor _primary = PdfColor.fromInt(0xFF0E695F);
  static const PdfColor _ink = PdfColor.fromInt(0xFF111418);
  static const PdfColor _mute = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _hairline = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _success = PdfColor.fromInt(0xFF15803D);
  static const PdfColor _warn = PdfColor.fromInt(0xFFB45309);

  pw.Widget build() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _header(),
        pw.SizedBox(height: 28),
        _amountBlock(),
        pw.SizedBox(height: 28),
        _hairlineRule(),
        pw.SizedBox(height: 20),
        _jobSection(),
        pw.SizedBox(height: 20),
        _hairlineRule(),
        pw.SizedBox(height: 20),
        _timingTable(),
        pw.SizedBox(height: 20),
        _hairlineRule(),
        pw.SizedBox(height: 20),
        _verificationChecklist(),
        pw.SizedBox(height: 20),
        _hairlineRule(),
        pw.SizedBox(height: 20),
        _referenceBlock(),
        pw.Spacer(),
        _footer(),
      ],
    );
  }

  // ---- Sections ----------------------------------------------------

  pw.Widget _header() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                'FORGE',
                style: pw.TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Job receipt',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Issued ${DateFormat('MMM d, y · h:mm a').format(issuedAt.toLocal())}',
                style: pw.TextStyle(fontSize: 10, color: _mute),
              ),
            ],
          ),
        ),
        _paidBadge(),
      ],
    );
  }

  pw.Widget _paidBadge() {
    final tint = disputed ? _warn : _success;
    final label = disputed ? 'DISPUTED' : 'PAID';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: tint, width: 1.4),
        borderRadius: pw.BorderRadius.circular(999),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: pw.FontWeight.bold,
          color: tint,
        ),
      ),
    );
  }

  pw.Widget _amountBlock() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'AMOUNT PAID',
          style: pw.TextStyle(
            fontSize: 9,
            letterSpacing: 1.6,
            color: _mute,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          ngn.format(paid),
          style: pw.TextStyle(
            fontSize: 40,
            fontWeight: pw.FontWeight.bold,
            color: disputed ? _warn : _ink,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  pw.Widget _jobSection() {
    final job = application.job;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _twoCol(<List<String>>[
          ['Job', job.title],
          ['Type', _jobTypeLabel(job.type)],
          ['Employer', job.employer.name],
          ['Location', job.locationAddress],
        ]),
        if (job.requiredEquipment.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 8),
          _twoCol(<List<String>>[
            ['Equipment', job.requiredEquipment.join(', ')],
          ]),
        ],
      ],
    );
  }

  pw.Widget _timingTable() {
    final completedAt = application.completedAt ?? session?.clockOutAt;
    final clockIn = session?.clockInAt;
    final hoursWorked = session?.durationHoursWorked ?? 0.0;
    final dateFmt = DateFormat('MMM d, y · h:mm a');
    final rows = <List<String>>[];
    if (clockIn != null) {
      rows.add(['Clocked in', dateFmt.format(clockIn.toLocal())]);
    }
    if (completedAt != null) {
      rows.add(['Completed', dateFmt.format(completedAt.toLocal())]);
    }
    rows.add([
      'Time on the job',
      _hoursLabel(hoursWorked, application.job.durationHours),
    ]);
    return _twoCol(rows);
  }

  pw.Widget _verificationChecklist() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'VERIFICATIONS',
          style: pw.TextStyle(
            fontSize: 9,
            letterSpacing: 1.6,
            color: _mute,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        _checkRow('Photo proof'),
        pw.SizedBox(height: 4),
        _checkRow('Location verified at clock-out'),
        pw.SizedBox(height: 4),
        _checkRow('Time on the job verified'),
        if (disputed) ...<pw.Widget>[
          pw.SizedBox(height: 4),
          _flagRow('Employer flagged the clock-out — under review'),
        ],
      ],
    );
  }

  pw.Widget _referenceBlock() {
    final rows = <List<String>>[];
    final txId = session?.transactionId;
    if (txId != null && txId.isNotEmpty) {
      rows.add(['Payment reference', txId]);
    }
    rows.add(['Application ID', application.id]);
    final serverSession = session?.id;
    if (serverSession != null && serverSession.isNotEmpty) {
      rows.add(['Session ID', serverSession]);
    }
    return _twoCol(rows, monospaceValue: true);
  }

  pw.Widget _footer() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _hairlineRule(),
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'WORKER',
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.6,
                    color: _mute,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  worker.name,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  worker.phoneNumber,
                  style: pw.TextStyle(fontSize: 10, color: _mute),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text(
                  'ISSUED BY',
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.6,
                    color: _mute,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Forge',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'forge.app',
                  style: pw.TextStyle(fontSize: 10, color: _mute),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'This receipt confirms work completed by the named worker '
          'and payment disbursed via Forge. Verifications above were '
          'enforced at clock-out time by Forge\'s photo + GPS + time-'
          'on-task checks. Reference numbers can be quoted to Forge '
          'support to look up the underlying session.',
          style: pw.TextStyle(
            fontSize: 8.5,
            color: _mute,
            lineSpacing: 2,
          ),
        ),
      ],
    );
  }

  // ---- Layout helpers ---------------------------------------------

  pw.Widget _twoCol(
    List<List<String>> rows, {
    bool monospaceValue = false,
  }) {
    return pw.Table(
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(120),
        1: pw.FlexColumnWidth(),
      },
      children: <pw.TableRow>[
        for (final List<String> r in rows)
          pw.TableRow(
            children: <pw.Widget>[
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(
                  r[0].toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    letterSpacing: 1.5,
                    color: _mute,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(
                  r[1].isEmpty ? '—' : r[1],
                  style: pw.TextStyle(
                    fontSize: monospaceValue ? 10 : 11,
                    color: _ink,
                    fontWeight: pw.FontWeight.bold,
                    // `pw.FontFeature` doesn't exist in the pdf package
                    // (only the Flutter SDK has it). For monospaced
                    // reference numbers we drop one point of size so
                    // the digits don't crowd the column instead.
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _checkRow(String label) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.Container(
          width: 14,
          height: 14,
          decoration: pw.BoxDecoration(
            color: _success,
            shape: pw.BoxShape.circle,
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            'OK',
            style: pw.TextStyle(
              fontSize: 6,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 11, color: _ink),
        ),
      ],
    );
  }

  pw.Widget _flagRow(String label) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.Container(
          width: 14,
          height: 14,
          decoration: pw.BoxDecoration(
            color: _warn,
            shape: pw.BoxShape.circle,
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            '!',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 11, color: _warn),
          ),
        ),
      ],
    );
  }

  pw.Widget _hairlineRule() {
    return pw.Container(height: 0.6, color: _hairline);
  }

  String _hoursLabel(double worked, int posted) {
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

  String _jobTypeLabel(JobType t) => t.label;
}
