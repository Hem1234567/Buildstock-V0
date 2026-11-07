import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:printing/printing.dart';

import 'package:buildstock/core/printing/thermal_printer_service.dart';
import 'package:buildstock/features/invoices/data/invoice_pdf.dart';
import 'package:buildstock/features/invoices/domain/invoice_document.dart';

/// Generates and delivers invoice files from structured data only. No stored
/// PDF or image is used, so a document can always be regenerated on any device.
class InvoiceExporter {
  const InvoiceExporter();

  Future<Uint8List> pdf(InvoiceDocument document) =>
      InvoicePdfBuilder().buildA4(document);

  Future<Uint8List> thermal(InvoiceDocument document, ThermalWidth width) =>
      InvoicePdfBuilder().buildThermal(document, width);

  Future<void> printA4(InvoiceDocument document) async {
    final bytes = await pdf(document);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${document.number}.pdf',
    );
  }

  Future<void> printThermal(
    InvoiceDocument document,
    ThermalWidth width,
  ) async {
    final bytes = await thermal(document, width);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${document.number}-thermal.pdf',
    );
  }

  /// Prints through the saved printer choice: straight to a network,
  /// Bluetooth or USB thermal printer, or through the Android print dialog.
  Future<void> printWithSettings(
    InvoiceDocument document,
    PrintSettings settings,
  ) async {
    if (!settings.isThermalPaper) {
      await printA4(document);
      return;
    }
    final width = settings.paper == '58'
        ? ThermalWidth.mm58
        : ThermalWidth.mm80;
    if (settings.isDirect) {
      final bytes = await thermal(document, width);
      await const ThermalPrinterService().printPdf(settings, bytes);
      return;
    }
    await printThermal(document, width);
  }

  Future<void> sharePdf(InvoiceDocument document) async {
    final bytes = await pdf(document);
    await Printing.sharePdf(bytes: bytes, filename: '${document.number}.pdf');
  }

  Future<Uri?> savePdf(InvoiceDocument document) async {
    final bytes = await pdf(document);
    return FilePicker.saveFile(
      dialogTitle: 'Save invoice PDF',
      fileName: '${document.number}.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  Future<Uri?> saveThermal(InvoiceDocument document, ThermalWidth width) async {
    final bytes = await thermal(document, width);
    final suffix = width == ThermalWidth.mm58 ? '58mm' : '80mm';
    return FilePicker.saveFile(
      dialogTitle: 'Save thermal bill',
      fileName: '${document.number}-$suffix.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  Future<Uri?> savePng(String suggestedName, Uint8List bytes) {
    return FilePicker.saveFile(
      dialogTitle: 'Save invoice image',
      fileName: '$suggestedName.png',
      mimeType: 'image/png',
      bytes: bytes,
    );
  }
}
