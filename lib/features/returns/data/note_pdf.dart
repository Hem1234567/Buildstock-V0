import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/features/invoices/data/invoice_pdf.dart';

/// Credit / debit note document. Generated from stored data, never edited.
class NotePdfBuilder {
  const NotePdfBuilder();

  static const PdfColor _line = PdfColor.fromInt(0xFF444444);
  static const PdfColor _muted = PdfColor.fromInt(0xFF666666);
  static const PdfColor _soft = PdfColor.fromInt(0xFFF1EEE8);

  static String heading(String type) => switch (type) {
    ReturnType.creditNote => 'CREDIT NOTE',
    ReturnType.debitNote => 'DEBIT NOTE',
    ReturnType.purchaseDebitNote => 'DEBIT NOTE (TO SUPPLIER)',
    ReturnType.purchaseCreditNote => 'CREDIT NOTE (FROM SUPPLIER)',
    ReturnType.purchaseReturn => 'PURCHASE RETURN',
    _ => 'SALES RETURN',
  };

  Future<Uint8List> build({
    required ReturnRow note,
    required BusinessProfileRow? business,
  }) async {
    final (regular, bold) = await InvoiceFonts.load();
    final pdf = pw.Document(
      title: '${heading(note.type)} ${note.returnNumber}',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final address = business == null
        ? ''
        : [
            business.address,
            business.city,
            business.state,
            business.pinCode,
          ].where((part) => part.trim().isNotEmpty).join(', ');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              business?.name ?? '',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            if (address.isNotEmpty)
              pw.Text(
                address,
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            if (business != null && business.gstin.isNotEmpty)
              pw.Text(
                'GSTIN: ${business.gstin}',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            pw.SizedBox(height: 16),
            pw.Container(
              color: _soft,
              padding: const pw.EdgeInsets.symmetric(vertical: 7),
              child: pw.Center(
                child: pw.Text(
                  heading(note.type),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Note No: ${note.returnNumber}'),
                pw.Text('Date: ${AppDate.display(note.createdAt)}'),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    ReturnType.isCustomerNote(note.type) ||
                            note.type == ReturnType.saleReturn
                        ? 'Customer'
                        : 'Supplier',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                  pw.Text(
                    note.partyName,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (note.originalDocumentNumber.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Against document: ${note.originalDocumentNumber}'),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
              headers: const ['Particulars', 'Amount (₹)'],
              data: [
                [
                  note.reason.isEmpty ? heading(note.type) : note.reason,
                  Money.format(note.amountPaise, symbol: false),
                ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(color: _soft),
              cellAlignments: {1: pw.Alignment.centerRight},
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1.4),
              },
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total  ${Money.format(note.amountPaise)}',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              Money.inWords(note.amountPaise),
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
            pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                children: [
                  pw.SizedBox(height: 34),
                  pw.Container(width: 150, height: 0.7, color: _line),
                  pw.Text(
                    'Authorised signature',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Future<void> share(Uint8List bytes, String number) =>
      Printing.sharePdf(bytes: bytes, filename: '$number.pdf');

  Future<void> print(Uint8List bytes, String number) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: '$number.pdf');
}
