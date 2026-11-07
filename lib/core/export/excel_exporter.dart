import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/utils/dates.dart';

/// One worksheet. Cell values may be `String`, `int`, `double`, `DateTime`,
/// `bool` or null. Money columns are passed as rupees (double).
class ExcelTableData {
  const ExcelTableData({
    required this.title,
    required this.headers,
    required this.rows,
  });

  final String title;
  final List<String> headers;
  final List<List<Object?>> rows;
}

/// Builds `.xlsx` workbooks with the `excel` package.
abstract final class ExcelWorkbook {
  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static String safeSheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (cleaned.isEmpty) return 'Sheet';
    return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
  }

  static CellValue _cell(Object? value) {
    if (value == null) return TextCellValue('');
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is DateTime) return TextCellValue(AppDate.display(value));
    if (value is bool) return TextCellValue(value ? 'Yes' : 'No');
    return TextCellValue(value.toString());
  }

  static Uint8List build(List<ExcelTableData> tables) {
    final excel = Excel.createExcel();
    final used = <String>{};
    for (final table in tables) {
      var name = safeSheetName(table.title);
      var suffix = 2;
      while (!used.add(name)) {
        name = '${safeSheetName(table.title)} $suffix';
        suffix++;
      }
      final sheet = excel[name];
      sheet.appendRow(<CellValue?>[
        for (final header in table.headers) TextCellValue(header),
      ]);
      for (var column = 0; column < table.headers.length; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
        );
        cell.cellStyle = CellStyle(bold: true);
        sheet.setColumnWidth(column, 18.0);
      }
      for (final row in table.rows) {
        sheet.appendRow(<CellValue?>[for (final value in row) _cell(value)]);
      }
    }
    if (!used.contains('Sheet1')) {
      excel.delete('Sheet1');
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('The Excel file could not be created');
    }
    return Uint8List.fromList(encoded);
  }

  /// Lets the user pick where to store the workbook.
  static Future<Uri?> save(String fileName, Uint8List bytes) {
    return FilePicker.saveFile(
      dialogTitle: 'Save Excel report',
      fileName: fileName.endsWith('.xlsx') ? fileName : '$fileName.xlsx',
      mimeType: mimeType,
      bytes: bytes,
    );
  }
}

enum ReportSheet {
  sales,
  purchases,
  stock,
  customerDues,
  supplierPayables,
  expenses,
  gstSummary,
  payments,
}

/// Reads report data straight from SQLite so exports include every record in
/// the chosen period, not only what a screen currently has loaded.
class ReportDataSource {
  ReportDataSource(this.db);

  final AppDatabase db;

  static double rupees(int paise) => (paise / 100 * 100).round() / 100;

  static DateTime? _date(Object? seconds) {
    if (seconds is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  List<Variable> _range(DateTime? from, DateTime? to) => [
    Variable<int>((from ?? DateTime(2000)).millisecondsSinceEpoch ~/ 1000),
    Variable<int>((to ?? DateTime(2100)).millisecondsSinceEpoch ~/ 1000),
  ];

  Future<ExcelTableData> sales({DateTime? from, DateTime? to}) async {
    final rows = await db
        .customSelect(
          'SELECT invoice_number, invoice_date, document_status, '
          'buyer_snapshot_json, subtotal_paise, discount_paise, '
          'taxable_amount_paise, cgst_paise, sgst_paise, igst_paise, '
          'round_off_paise, grand_total_paise, amount_paid_paise, '
          'balance_due_paise, payment_method FROM sales '
          "WHERE document_type = 'invoice' "
          'AND invoice_date BETWEEN ? AND ? ORDER BY invoice_date',
          variables: _range(from, to),
        )
        .get();
    return ExcelTableData(
      title: 'Sales',
      headers: const [
        'Bill No',
        'Date',
        'Customer',
        'Status',
        'Subtotal',
        'Discount',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
        'Round off',
        'Grand total',
        'Paid',
        'Balance',
        'Payment',
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('invoice_number'),
            _date(row.data['invoice_date']),
            _buyerName(row.read<String>('buyer_snapshot_json')),
            row.read<String>('document_status'),
            rupees(row.read<int>('subtotal_paise')),
            rupees(row.read<int>('discount_paise')),
            rupees(row.read<int>('taxable_amount_paise')),
            rupees(row.read<int>('cgst_paise')),
            rupees(row.read<int>('sgst_paise')),
            rupees(row.read<int>('igst_paise')),
            rupees(row.read<int>('round_off_paise')),
            rupees(row.read<int>('grand_total_paise')),
            rupees(row.read<int>('amount_paid_paise')),
            rupees(row.read<int>('balance_due_paise')),
            row.read<String>('payment_method'),
          ],
      ],
    );
  }

  String _buyerName(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map && decoded['name'] != null) {
        return decoded['name'].toString();
      }
    } catch (_) {}
    return 'Walk-in Customer';
  }

  Future<ExcelTableData> purchases({DateTime? from, DateTime? to}) async {
    final rows = await db
        .customSelect(
          'SELECT p.purchase_number, p.purchase_date, s.name AS supplier, '
          'p.supplier_invoice_number, p.subtotal_paise, p.taxable_amount_paise, '
          'p.cgst_paise, p.sgst_paise, p.igst_paise, p.grand_total_paise, '
          'p.amount_paid_paise, p.balance_due_paise, p.status '
          'FROM purchases p LEFT JOIN suppliers s ON s.id = p.supplier_id '
          'WHERE p.purchase_date BETWEEN ? AND ? ORDER BY p.purchase_date',
          variables: _range(from, to),
        )
        .get();
    return ExcelTableData(
      title: 'Purchases',
      headers: const [
        'Purchase No',
        'Date',
        'Supplier',
        'Supplier invoice',
        'Subtotal',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
        'Grand total',
        'Paid',
        'Balance',
        'Status',
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('purchase_number'),
            _date(row.data['purchase_date']),
            row.read<String?>('supplier') ?? 'Unregistered',
            row.read<String>('supplier_invoice_number'),
            rupees(row.read<int>('subtotal_paise')),
            rupees(row.read<int>('taxable_amount_paise')),
            rupees(row.read<int>('cgst_paise')),
            rupees(row.read<int>('sgst_paise')),
            rupees(row.read<int>('igst_paise')),
            rupees(row.read<int>('grand_total_paise')),
            rupees(row.read<int>('amount_paid_paise')),
            rupees(row.read<int>('balance_due_paise')),
            row.read<String>('status'),
          ],
      ],
    );
  }

  Future<ExcelTableData> stock() async {
    final rows = await db
        .customSelect(
          'SELECT p.name, p.sku, p.barcode, c.name AS category, '
          'st.name AS store, g.name AS godown, i.quantity_milli, '
          'p.min_stock_milli, p.purchase_price_paise, p.retail_price_paise '
          'FROM inventories i '
          'JOIN products p ON p.id = i.product_id '
          'LEFT JOIN categories c ON c.id = p.category_id '
          'LEFT JOIN stores st ON st.id = i.store_id '
          'LEFT JOIN godowns g ON g.id = i.godown_id '
          'WHERE p.active = 1 ORDER BY p.name',
        )
        .get();
    return ExcelTableData(
      title: 'Stock',
      headers: const [
        'Product',
        'SKU',
        'Barcode',
        'Category',
        'Store',
        'Godown',
        'Quantity',
        'Minimum',
        'Purchase price',
        'Retail price',
        'Stock value',
      ],
      rows: [
        for (final row in rows)
          [
            row.read<String>('name'),
            row.read<String>('sku'),
            row.read<String>('barcode'),
            row.read<String?>('category') ?? '',
            row.read<String?>('store') ?? '',
            row.read<String?>('godown') ?? '',
            row.read<int>('quantity_milli') / 1000,
            row.read<int>('min_stock_milli') / 1000,
            rupees(row.read<int>('purchase_price_paise')),
            rupees(row.read<int>('retail_price_paise')),
            rupees(
              (row.read<int>('quantity_milli') *
                      row.read<int>('purchase_price_paise') /
                      1000)
                  .round(),
            ),
          ],
      ],
    );
  }

  Future<ExcelTableData> partyBalances({
    required bool customers,
    required Map<String, int> balances,
  }) async {
    final table = customers ? 'customers' : 'suppliers';
    final rows = await db
        .customSelect('SELECT id, name, phone FROM $table ORDER BY name')
        .get();
    return ExcelTableData(
      title: customers ? 'Customer dues' : 'Supplier payables',
      headers: [customers ? 'Customer' : 'Supplier', 'Phone', 'Balance'],
      rows: [
        for (final row in rows)
          if ((balances[row.read<String>('id')] ?? 0) != 0)
            [
              row.read<String>('name'),
              row.read<String>('phone'),
              rupees(balances[row.read<String>('id')] ?? 0),
            ],
      ],
    );
  }

  Future<ExcelTableData> expenses({DateTime? from, DateTime? to}) async {
    final rows = await db
        .customSelect(
          'SELECT category_name, paid_at, amount_paise, method, description '
          'FROM expenses WHERE paid_at BETWEEN ? AND ? ORDER BY paid_at',
          variables: _range(from, to),
        )
        .get();
    return ExcelTableData(
      title: 'Expenses',
      headers: const ['Category', 'Date', 'Amount', 'Method', 'Description'],
      rows: [
        for (final row in rows)
          [
            row.read<String>('category_name'),
            _date(row.data['paid_at']),
            rupees(row.read<int>('amount_paise')),
            row.read<String>('method'),
            row.read<String>('description'),
          ],
      ],
    );
  }

  Future<ExcelTableData> gstSummary({DateTime? from, DateTime? to}) async {
    final rows = await db
        .customSelect(
          'SELECT si.tax_rate_bps AS rate, '
          'SUM(si.line_total_paise - si.tax_amount_paise) AS taxable, '
          'SUM(si.tax_amount_paise) AS tax FROM sale_items si '
          'JOIN sales s ON s.id = si.sale_id '
          "WHERE s.document_type = 'invoice' "
          "AND s.document_status = 'finalized' "
          'AND s.invoice_date BETWEEN ? AND ? GROUP BY si.tax_rate_bps '
          'ORDER BY si.tax_rate_bps',
          variables: _range(from, to),
        )
        .get();
    return ExcelTableData(
      title: 'GST summary',
      headers: const ['GST rate %', 'Taxable value', 'Tax amount'],
      rows: [
        for (final row in rows)
          [
            row.read<int>('rate') / 100,
            rupees(row.read<int>('taxable')),
            rupees(row.read<int>('tax')),
          ],
      ],
    );
  }

  Future<ExcelTableData> payments({DateTime? from, DateTime? to}) async {
    final rows = await db
        .customSelect(
          'SELECT paid_at, party_type, party_name, direction, amount_paise, '
          'method, reference FROM payments '
          'WHERE paid_at BETWEEN ? AND ? ORDER BY paid_at',
          variables: _range(from, to),
        )
        .get();
    return ExcelTableData(
      title: 'Payments',
      headers: const [
        'Date',
        'Party type',
        'Party',
        'Direction',
        'Amount',
        'Method',
        'Reference',
      ],
      rows: [
        for (final row in rows)
          [
            _date(row.data['paid_at']),
            row.read<String>('party_type'),
            row.read<String>('party_name'),
            row.read<String>('direction') == 'in' ? 'Received' : 'Paid',
            rupees(row.read<int>('amount_paise')),
            row.read<String>('method'),
            row.read<String>('reference'),
          ],
      ],
    );
  }

  /// Builds the requested sheets. Balance maps come from the party ledgers.
  Future<Uint8List> workbook({
    required Set<ReportSheet> sheets,
    DateTime? from,
    DateTime? to,
    Map<String, int> customerBalances = const {},
    Map<String, int> supplierBalances = const {},
  }) async {
    final tables = <ExcelTableData>[];
    for (final sheet in ReportSheet.values) {
      if (!sheets.contains(sheet)) continue;
      switch (sheet) {
        case ReportSheet.sales:
          tables.add(await sales(from: from, to: to));
        case ReportSheet.purchases:
          tables.add(await purchases(from: from, to: to));
        case ReportSheet.stock:
          tables.add(await stock());
        case ReportSheet.customerDues:
          tables.add(
            await partyBalances(customers: true, balances: customerBalances),
          );
        case ReportSheet.supplierPayables:
          tables.add(
            await partyBalances(customers: false, balances: supplierBalances),
          );
        case ReportSheet.expenses:
          tables.add(await expenses(from: from, to: to));
        case ReportSheet.gstSummary:
          tables.add(await gstSummary(from: from, to: to));
        case ReportSheet.payments:
          tables.add(await payments(from: from, to: to));
      }
    }
    return ExcelWorkbook.build(tables);
  }
}
