import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/media/image_service.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/features/invoices/data/invoice_pdf.dart';

/// Printable salary slip for one salary record. Built only from stored data.
class SalarySlipPdfBuilder {
  const SalarySlipPdfBuilder();

  static const PdfColor _ink = PdfColor.fromInt(0xFF111111);
  static const PdfColor _muted = PdfColor.fromInt(0xFF666666);
  static const PdfColor _line = PdfColor.fromInt(0xFF444444);
  static const PdfColor _soft = PdfColor.fromInt(0xFFF1EEE8);

  /// Earnings, deductions and net pay as plain numbers, so they can be tested.
  static ({int earnings, int deductions, int net}) totals({
    required int basic,
    int overtime = 0,
    int incentive = 0,
    int bonus = 0,
    int advance = 0,
    int attendance = 0,
    int other = 0,
  }) {
    final earnings = basic + overtime + incentive + bonus;
    final deductions = advance + attendance + other;
    return (
      earnings: earnings,
      deductions: deductions,
      net: earnings - deductions,
    );
  }

  Future<Uint8List> build({
    required SalaryRecordRow salary,
    required BusinessProfileRow? business,
    required List<SalaryPaymentRow> payments,
    String employeeCode = '',
    String designation = '',
  }) async {
    final (regular, bold) = await InvoiceFonts.load();
    final totalsValue = totals(
      basic: salary.basicSalaryPaise,
      overtime: salary.overtimePaise,
      incentive: salary.incentivePaise,
      bonus: salary.bonusPaise,
      advance: salary.advanceDeductionPaise,
      attendance: salary.attendanceDeductionPaise,
      other: salary.otherDeductionsPaise,
    );
    final logoBytes = await ImageService.loadBytes(business?.logoRef);
    final signatureBytes = await ImageService.loadBytes(business?.signatureRef);
    final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
    final signature = signatureBytes == null
        ? null
        : pw.MemoryImage(signatureBytes);

    final pdf = pw.Document(
      title: 'Salary slip ${salary.personName}',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pw.Widget row(String label, int paise, {bool strong = false}) {
      final style = pw.TextStyle(
        fontSize: 10,
        fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: style),
            pw.Text(Money.format(paise, symbol: false), style: style),
          ],
        ),
      );
    }

    pw.Widget box(String title, List<pw.Widget> children) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line, width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Divider(color: _line, height: 8),
            ...children,
          ],
        ),
      ),
    );

    final businessLines = <String>[
      if (business != null && business.address.trim().isNotEmpty)
        [
          business.address,
          business.city,
          business.state,
          business.pinCode,
        ].where((part) => part.trim().isNotEmpty).join(', '),
      if (business != null && business.phone.isNotEmpty)
        'Phone: ${business.phone}',
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 48,
                    height: 48,
                    margin: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        business?.name ?? '',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      for (final line in businessLines)
                        pw.Text(
                          line,
                          style: const pw.TextStyle(fontSize: 9, color: _muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              color: _soft,
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Center(
                child: pw.Text(
                  'SALARY SLIP',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        salary.personName,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (employeeCode.isNotEmpty)
                        pw.Text('Employee code: $employeeCode'),
                      if (designation.isNotEmpty)
                        pw.Text('Designation: $designation'),
                      pw.Text(
                        salary.personType == 'driver' ? 'Driver' : 'Staff',
                        style: const pw.TextStyle(color: _muted, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Period: ${AppDate.display(salary.periodStart)} to '
                      '${AppDate.display(salary.periodEnd)}',
                    ),
                    pw.Text(
                      'Status: ${salary.status.toUpperCase()}',
                      style: const pw.TextStyle(color: _muted, fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                box('Earnings (₹)', [
                  row('Basic salary', salary.basicSalaryPaise),
                  row('Overtime', salary.overtimePaise),
                  row('Incentive', salary.incentivePaise),
                  row('Bonus', salary.bonusPaise),
                  pw.Divider(color: _line, height: 8),
                  row('Gross earnings', totalsValue.earnings, strong: true),
                ]),
                pw.SizedBox(width: 12),
                box('Deductions (₹)', [
                  row('Advance recovered', salary.advanceDeductionPaise),
                  row('Attendance', salary.attendanceDeductionPaise),
                  row('Other', salary.otherDeductionsPaise),
                  pw.Divider(color: _line, height: 8),
                  row('Total deductions', totalsValue.deductions, strong: true),
                ]),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: _soft,
                border: pw.Border.all(color: _line, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  row('NET SALARY', salary.netSalaryPaise, strong: true),
                  row('Paid so far', salary.amountPaidPaise),
                  row('Balance due', salary.balanceDuePaise, strong: true),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'In words: ${Money.inWords(salary.netSalaryPaise)}',
                    style: const pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ],
              ),
            ),
            if (payments.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                'Payments',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: const ['Date', 'Method', 'Reference', 'Amount (₹)'],
                data: [
                  for (final payment in payments)
                    [
                      AppDate.display(payment.paidAt),
                      payment.method,
                      payment.reference,
                      Money.format(payment.amountPaise, symbol: false),
                    ],
                ],
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: _soft),
                cellAlignments: {3: pw.Alignment.centerRight},
              ),
            ],
            if (salary.notes.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text('Notes: ${salary.notes}'),
            ],
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  children: [
                    pw.SizedBox(height: 34),
                    pw.Container(width: 140, height: 0.7, color: _line),
                    pw.Text(
                      'Employee signature',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    if (signature != null)
                      pw.SizedBox(
                        height: 34,
                        child: pw.Image(signature, fit: pw.BoxFit.contain),
                      )
                    else
                      pw.SizedBox(height: 34),
                    pw.Container(width: 140, height: 0.7, color: _line),
                    pw.Text(
                      'Authorised signature',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'This is a computer generated salary slip.',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Future<void> share(Uint8List bytes, String personName, DateTime period) {
    final safe = personName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    return Printing.sharePdf(
      bytes: bytes,
      filename:
          'salary-slip-$safe-${AppDate.isoDate(period).substring(0, 7)}.pdf',
    );
  }

  Future<void> print(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
}
