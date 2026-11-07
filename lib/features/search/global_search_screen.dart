import 'dart:async';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/scanner/barcode_scanner_screen.dart';
import 'package:buildstock/core/scanner/invoice_qr.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/invoices/presentation/invoice_screens.dart';

class SearchHit {
  const SearchHit({
    required this.group,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
  });

  final String group;
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
}

/// Searches every kind of record on this device at once.
class GlobalSearchRepository {
  GlobalSearchRepository(this.db);

  final AppDatabase db;

  static const int perGroup = 6;

  static String likePattern(String query) {
    final escaped = query
        .trim()
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  Future<List<SearchHit>> search(String query) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final pattern = likePattern(text);
    final hits = <SearchHit>[];

    Future<void> run(
      String group,
      IconData icon,
      String sql,
      int variableCount,
      SearchHit Function(QueryRow row) build,
    ) async {
      try {
        final rows = await db
            .customSelect(
              '$sql LIMIT $perGroup',
              variables: [
                for (var i = 0; i < variableCount; i++)
                  Variable<String>(pattern),
              ],
            )
            .get();
        for (final row in rows) {
          hits.add(build(row));
        }
      } catch (_) {
        // One failing group must never hide the others.
      }
    }

    await run(
      'Products',
      Icons.inventory_2_outlined,
      "SELECT id, name, sku, barcode, retail_price_paise FROM products "
          "WHERE deleted_at IS NULL AND (name LIKE ?1 ESCAPE '\\' OR sku LIKE ?1 ESCAPE '\\' "
          "OR barcode LIKE ?1 ESCAPE '\\' OR hsn_code LIKE ?1 ESCAPE '\\') ORDER BY name",
      1,
      (row) => SearchHit(
        group: 'Products',
        title: row.read<String>('name'),
        subtitle: [
          if (row.read<String>('sku').isNotEmpty) row.read<String>('sku'),
          if (row.read<String>('barcode').isNotEmpty)
            row.read<String>('barcode'),
          Money.format(row.read<int>('retail_price_paise')),
        ].join(' · '),
        route: '/products/${row.read<String>('id')}',
        icon: Icons.inventory_2_outlined,
      ),
    );
    await run(
      'Customers',
      Icons.people_outline,
      "SELECT id, name, phone, business_name FROM customers "
          "WHERE deleted_at IS NULL AND (name LIKE ?1 ESCAPE '\\' OR phone LIKE ?1 ESCAPE '\\' "
          "OR business_name LIKE ?1 ESCAPE '\\' OR gstin LIKE ?1 ESCAPE '\\') ORDER BY name",
      1,
      (row) => SearchHit(
        group: 'Customers',
        title: row.read<String>('name'),
        subtitle: [
          row.read<String>('phone'),
          row.read<String>('business_name'),
        ].where((part) => part.isNotEmpty).join(' · '),
        route: '/customers/${row.read<String>('id')}',
        icon: Icons.people_outline,
      ),
    );
    await run(
      'Suppliers',
      Icons.local_shipping_outlined,
      "SELECT id, name, phone FROM suppliers "
          "WHERE deleted_at IS NULL AND (name LIKE ?1 ESCAPE '\\' OR phone LIKE ?1 ESCAPE '\\' "
          "OR gstin LIKE ?1 ESCAPE '\\') ORDER BY name",
      1,
      (row) => SearchHit(
        group: 'Suppliers',
        title: row.read<String>('name'),
        subtitle: row.read<String>('phone'),
        route: '/suppliers/${row.read<String>('id')}',
        icon: Icons.local_shipping_outlined,
      ),
    );
    await run(
      'Bills',
      Icons.receipt_long_outlined,
      "SELECT id, invoice_number, document_type, grand_total_paise, buyer_snapshot_json "
          "FROM sales WHERE invoice_number LIKE ?1 ESCAPE '\\' "
          "OR buyer_snapshot_json LIKE ?1 ESCAPE '\\' ORDER BY invoice_date DESC",
      1,
      (row) => SearchHit(
        group: 'Bills',
        title: row.read<String>('invoice_number'),
        subtitle:
            '${row.read<String>('document_type')} · ${Money.format(row.read<int>('grand_total_paise'))}',
        route: '/invoices/${row.read<String>('id')}',
        icon: Icons.receipt_long_outlined,
      ),
    );
    await run(
      'Orders',
      Icons.assignment_outlined,
      "SELECT id, order_number, customer_name, status FROM orders "
          "WHERE order_number LIKE ?1 ESCAPE '\\' OR customer_name LIKE ?1 ESCAPE '\\' "
          "ORDER BY created_at DESC",
      1,
      (row) => SearchHit(
        group: 'Orders',
        title: row.read<String>('order_number'),
        subtitle:
            '${row.read<String>('customer_name')} · ${row.read<String>('status')}',
        route: '/orders/${row.read<String>('id')}',
        icon: Icons.assignment_outlined,
      ),
    );
    await run(
      'Purchases',
      Icons.shopping_bag_outlined,
      "SELECT id, purchase_number, supplier_invoice_number, grand_total_paise "
          "FROM purchases WHERE purchase_number LIKE ?1 ESCAPE '\\' "
          "OR supplier_invoice_number LIKE ?1 ESCAPE '\\' ORDER BY purchase_date DESC",
      1,
      (row) => SearchHit(
        group: 'Purchases',
        title: row.read<String>('purchase_number'),
        subtitle:
            '${row.read<String>('supplier_invoice_number')} · ${Money.format(row.read<int>('grand_total_paise'))}',
        route: '/purchases',
        icon: Icons.shopping_bag_outlined,
      ),
    );
    await run(
      'Returns & notes',
      Icons.assignment_return_outlined,
      "SELECT id, return_number, party_name, type, amount_paise FROM returns "
          "WHERE return_number LIKE ?1 ESCAPE '\\' OR party_name LIKE ?1 ESCAPE '\\' "
          "ORDER BY created_at DESC",
      1,
      (row) => SearchHit(
        group: 'Returns & notes',
        title: row.read<String>('return_number'),
        subtitle:
            '${row.read<String>('party_name')} · ${Money.format(row.read<int>('amount_paise'))}',
        route: '/returns',
        icon: Icons.assignment_return_outlined,
      ),
    );
    await run(
      'Staff',
      Icons.badge_outlined,
      "SELECT id, full_name, employee_code, phone FROM staff_members "
          "WHERE deleted_at IS NULL AND (full_name LIKE ?1 ESCAPE '\\' OR employee_code LIKE ?1 ESCAPE '\\' "
          "OR phone LIKE ?1 ESCAPE '\\') ORDER BY full_name",
      1,
      (row) => SearchHit(
        group: 'Staff',
        title: row.read<String>('full_name'),
        subtitle:
            '${row.read<String>('employee_code')} · ${row.read<String>('phone')}',
        route: '/staff/${row.read<String>('id')}/edit',
        icon: Icons.badge_outlined,
      ),
    );
    await run(
      'Drivers',
      Icons.drive_eta_outlined,
      "SELECT id, full_name, driver_code, phone FROM drivers "
          "WHERE deleted_at IS NULL AND (full_name LIKE ?1 ESCAPE '\\' OR driver_code LIKE ?1 ESCAPE '\\' "
          "OR phone LIKE ?1 ESCAPE '\\') ORDER BY full_name",
      1,
      (row) => SearchHit(
        group: 'Drivers',
        title: row.read<String>('full_name'),
        subtitle:
            '${row.read<String>('driver_code')} · ${row.read<String>('phone')}',
        route: '/drivers/${row.read<String>('id')}/edit',
        icon: Icons.drive_eta_outlined,
      ),
    );
    await run(
      'Deliveries',
      Icons.local_shipping_outlined,
      "SELECT id, delivery_number, invoice_number, customer_name FROM deliveries "
          "WHERE delivery_number LIKE ?1 ESCAPE '\\' OR invoice_number LIKE ?1 ESCAPE '\\' "
          "OR customer_name LIKE ?1 ESCAPE '\\' ORDER BY created_at DESC",
      1,
      (row) => SearchHit(
        group: 'Deliveries',
        title: row.read<String>('delivery_number'),
        subtitle:
            '${row.read<String>('customer_name')} · ${row.read<String>('invoice_number')}',
        route: '/deliveries',
        icon: Icons.local_shipping_outlined,
      ),
    );
    await run(
      'Expenses',
      Icons.payments_outlined,
      "SELECT id, category_name, description, amount_paise FROM expenses "
          "WHERE category_name LIKE ?1 ESCAPE '\\' OR description LIKE ?1 ESCAPE '\\' "
          "ORDER BY paid_at DESC",
      1,
      (row) => SearchHit(
        group: 'Expenses',
        title: row.read<String>('category_name'),
        subtitle:
            '${row.read<String>('description')} · ${Money.format(row.read<int>('amount_paise'))}',
        route: '/expenses',
        icon: Icons.payments_outlined,
      ),
    );
    return hits;
  }
}

final globalSearchRepositoryProvider = Provider<GlobalSearchRepository>(
  (ref) => GlobalSearchRepository(ref.watch(databaseProvider)),
);

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _loading = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(value));
  }

  Future<void> _run(String value) async {
    setState(() => _loading = true);
    final hits = await ref.read(globalSearchRepositoryProvider).search(value);
    if (!mounted || value != _query) return;
    setState(() {
      _hits = hits;
      _loading = false;
    });
  }

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.open(
      context,
      title: 'Scan',
      hint: 'Scan a product barcode or a bill QR code',
    );
    if (code == null || !mounted) return;
    final invoice = InvoiceQr.parse(code);
    if (invoice != null) {
      await openInvoiceByNumber(context, ref, invoice.invoiceNumber);
      return;
    }
    _controller.text = code;
    _onChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<SearchHit>>{};
    for (final hit in _hits) {
      groups.putIfAbsent(hit.group, () => []).add(hit);
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search products, bills, customers, staff…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Scan barcode or bill QR',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scan,
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _query.trim().length < 2
          ? const EmptyState(
              title: 'Search everything',
              message: 'Type at least two letters. Products, bills, customers, suppliers, orders, purchases, returns, staff, drivers, deliveries and expenses are all searched together.',
              icon: Icons.search,
            )
          : (_loading && _hits.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (_hits.isEmpty
                      ? EmptyState(
                          title: 'Nothing found',
                          message: 'No record matches "${_query.trim()}".',
                          icon: Icons.search_off,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: [
                            for (final entry in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                                child: Text(
                                  entry.key,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              SectionCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (final hit in entry.value)
                                      ListTile(
                                        leading: Icon(hit.icon),
                                        title: Text(hit.title),
                                        subtitle: hit.subtitle.isEmpty
                                            ? null
                                            : Text(hit.subtitle),
                                        onTap: () => context.push(hit.route),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ))),
    );
  }
}
