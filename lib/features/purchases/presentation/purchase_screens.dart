import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';

import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/scanner/barcode_scanner_screen.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/widgets/photo_field.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';
import 'package:buildstock/features/stores/presentation/stock_location_picker.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/features/customers/data/parties_repository.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';
import 'package:buildstock/features/purchases/data/purchases_repository.dart';
import 'package:buildstock/features/sales/domain/invoice_calculator.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchases = ref.watch(purchasesStreamProvider(_query));
    final suppliers = ref.watch(suppliersStreamProvider('')).value ?? const [];
    final names = {
      for (final supplier in suppliers) supplier.id: supplier.name,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Purchases')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/purchases/new'),
        icon: const Icon(Icons.add),
        label: const Text('New purchase'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search purchase or supplier bill',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: purchases,
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    title: 'No purchases yet',
                    message: 'Record stock received from suppliers. Stock only increases through real purchase entries.',
                    icon: Icons.shopping_cart_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final purchase = rows[index];
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  purchase.purchaseNumber,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${names[purchase.supplierId] ?? 'Supplier'} · ${AppDate.display(purchase.purchaseDate)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(purchase.grandTotalPaise),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Paid ${Money.format(purchase.amountPaidPaise)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _supplierInvoice = TextEditingController();
  final _paid = TextEditingController();
  final _notes = TextEditingController();
  final List<InvoiceLine> _lines = [];
  String? _supplierId;
  StockLocation _location = const StockLocation();
  String? _billPhoto;
  String _method = PaymentMethods.cash;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _supplierInvoice.dispose();
    _paid.dispose();
    _notes.dispose();
    super.dispose();
  }

  InvoiceTotals get _totals => InvoiceCalculator.compute(
    lines: _lines.isEmpty
        ? const [
            InvoiceLine(
              productId: null,
              name: 'Empty',
              quantityMilli: 1000,
              unitPricePaise: 0,
            ),
          ]
        : _lines,
    isGst: true,
    amountPaidPaise: Money.tryParseRupees(_paid.text) ?? 0,
  );

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersStreamProvider('')).value ?? const [];
    final theme = Theme.of(context);
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          SectionCard(
            child: Column(
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Unregistered supplier'),
                    ),
                    for (final supplier in suppliers)
                      DropdownMenuItem<String?>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _supplierId = value),
                ),
                const SizedBox(height: 10),
                StockLocationDropdown(
                  value: _location,
                  label: 'Receive stock into',
                  autoLabel: 'No specific location',
                  onChanged: (value) => setState(() => _location = value),
                ),
                const SizedBox(height: 10),
                PhotoPickerField(
                  label: 'Supplier bill photo',
                  helper: 'Optional. Stored with the purchase.',
                  ownerType: 'purchase',
                  role: 'attachment',
                  initialRef: _billPhoto,
                  onChanged: (value) => _billPhoto = value,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supplierInvoice,
                  decoration: const InputDecoration(
                    labelText: 'Supplier invoice number',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionHeader(
            title: 'Items',
            actionLabel: 'Add item',
            onAction: _addItem,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: _scanItem,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan item barcode'),
              ),
            ),
          ),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _lines.isEmpty
                ? const EmptyState(
                    title: 'No items',
                    message: 'Add the materials received from this supplier.',
                    icon: Icons.inventory_2_outlined,
                    compact: true,
                  )
                : Column(
                    children: [
                      for (var index = 0; index < _lines.length; index++)
                        ListTile(
                          dense: true,
                          title: Text(_lines[index].name),
                          subtitle: Text(
                            '${Quantity.format(_lines[index].quantityMilli)} × ${Money.format(_lines[index].unitPricePaise)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Money.format(
                                  Money.roundDiv(
                                    _lines[index].quantityMilli *
                                        _lines[index].unitPricePaise,
                                    1000,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    setState(() => _lines.removeAt(index)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              children: [
                _row('Subtotal', Money.format(totals.subtotalPaise)),
                _row('Tax', Money.format(totals.taxPaise)),
                _row(
                  'Grand Total',
                  Money.format(totals.grandTotalPaise),
                  emphasize: true,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _paid,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount paid',
                    prefixText: '₹ ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'bank',
                      child: Text('Bank transfer'),
                    ),
                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    DropdownMenuItem(value: 'credit', child: Text('Credit')),
                  ],
                  onChanged: (value) =>
                      setState(() => _method = value ?? _method),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: _saving || _lines.isEmpty ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Save purchase · ${Money.format(totals.grandTotalPaise)}'),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              fontSize: emphasize ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Scans a product barcode and adds one unit at its last purchase price.
  Future<void> _scanItem() async {
    final code = await BarcodeScannerScreen.open(
      context,
      title: 'Scan item',
      hint: 'Scan the product barcode',
    );
    if (code == null || !mounted) return;
    final product = await ref
        .read(catalogRepositoryProvider)
        .productByCode(code);
    if (!mounted) return;
    if (product == null) {
      showActionMessage(context, 'No product found for $code');
      return;
    }
    setState(() {
      final index = _lines.indexWhere((line) => line.productId == product.id);
      if (index >= 0) {
        final line = _lines[index];
        _lines[index] = InvoiceLine(
          productId: line.productId,
          name: line.name,
          sku: line.sku,
          hsnCode: line.hsnCode,
          unit: line.unit,
          quantityMilli: line.quantityMilli + 1000,
          unitPricePaise: line.unitPricePaise,
          taxRateBps: line.taxRateBps,
        );
      } else {
        _lines.add(
          InvoiceLine(
            productId: product.id,
            name: product.name,
            sku: product.sku,
            hsnCode: product.hsnCode,
            unit: 'Nos',
            quantityMilli: 1000,
            unitPricePaise: product.purchasePricePaise,
            taxRateBps: product.gstRateBps,
          ),
        );
      }
    });
    showActionMessage(context, 'Added ${product.name}');
  }

  Future<void> _addItem() async {
    final products = ref.read(productsStreamProvider('')).value ?? const [];
    if (products.isEmpty) {
      if (mounted) {
        showActionMessage(context, 'Add a product first');
      }
      return;
    }
    var product = products.first;
    var quantity = '1';
    var rate = product.purchasePricePaise == 0
        ? ''
        : (product.purchasePricePaise / 100).toStringAsFixed(2);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add purchase item',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: product.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product'),
                items: products
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  final selected = products.firstWhere((p) => p.id == value);
                  setModalState(() {
                    product = selected;
                    rate = selected.purchasePricePaise == 0
                        ? ''
                        : (selected.purchasePricePaise / 100).toStringAsFixed(
                            2,
                          );
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantity'),
                controller: TextEditingController(text: quantity),
                onChanged: (value) => quantity = value,
              ),
              const SizedBox(height: 10),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Purchase rate',
                  prefixText: '₹ ',
                ),
                controller: TextEditingController(text: rate),
                onChanged: (value) => rate = value,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final milli = Quantity.tryParseMilli(quantity) ?? 0;
                  final paise = Money.tryParseRupees(rate) ?? 0;
                  if (milli <= 0) return;
                  setState(() {
                    _lines.add(
                      InvoiceLine(
                        productId: product.id,
                        name: product.name,
                        sku: product.sku,
                        hsnCode: product.hsnCode,
                        unit: 'Nos',
                        quantityMilli: milli,
                        unitPricePaise: paise,
                        taxRateBps: product.gstRateBps,
                      ),
                    );
                  });
                  Navigator.pop(context);
                },
                child: const Text('Add item'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(purchasesRepositoryProvider)
          .createPurchase(
            PurchaseInput(
              lines: _lines,
              supplierId: _supplierId,
              storeId: _location.storeId,
              godownId: _location.godownId,
              attachments: [if (_billPhoto != null) _billPhoto!],
              supplierInvoiceNumber: _supplierInvoice.text.trim(),
              amountPaidPaise: Money.tryParseRupees(_paid.text) ?? 0,
              paymentMethod: _method,
              notes: _notes.text.trim(),
            ),
          );
      ref.invalidate(purchasesStreamProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
