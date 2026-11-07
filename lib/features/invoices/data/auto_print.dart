import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/printing/thermal_printer_service.dart';
import 'package:buildstock/features/business/data/business_repository.dart';
import 'package:buildstock/features/invoices/data/invoice_exporter.dart';
import 'package:buildstock/features/invoices/domain/invoice_document.dart';
import 'package:buildstock/features/sales/data/sales_repository.dart';

/// Loads the saved printer settings.
Future<PrintSettings> loadPrintSettings(WidgetRef ref) async {
  final map = await ref.read(businessRepositoryProvider).watchSettings().first;
  return PrintSettings.fromMap(map);
}

/// Prints a freshly finalized bill when "Auto print" is switched on.
/// Returns an error message, or null when printing succeeded or is off.
Future<String?> autoPrintIfEnabled(WidgetRef ref, String saleId) async {
  try {
    final settings = await loadPrintSettings(ref);
    if (!settings.autoPrint) return null;
    final repository = ref.read(salesRepositoryProvider);
    final sale = await repository.saleById(saleId);
    if (sale == null) return null;
    final items = await repository.itemsForSale(saleId);
    final document = InvoiceDocument.fromRows(sale, items);
    if (document == null) return null;
    await const InvoiceExporter().printWithSettings(document, settings);
    return null;
  } catch (error) {
    return 'Auto print failed: $error';
  }
}
