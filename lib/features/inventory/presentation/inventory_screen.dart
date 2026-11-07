import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/scanner/barcode_scanner_screen.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';
import 'package:buildstock/features/stores/presentation/stock_location_picker.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  StockLocation _filter = const StockLocation();
  String? _productFilter;
  String _productFilterName = '';

  Future<void> _scanToFind() async {
    final code = await BarcodeScannerScreen.open(
      context,
      title: 'Find product',
      hint: 'Scan a product barcode to see its stock',
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
      _productFilter = product.id;
      _productFilterName = product.name;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stock = ref.watch(inventoryStreamProvider);
    final lowStock = ref.watch(lowStockProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Scan to find product',
            onPressed: _scanToFind,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Stock'),
            Tab(text: 'Stock ledger'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAdjustment,
        icon: const Icon(Icons.tune),
        label: const Text('Adjust'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          AsyncView(
            value: stock,
            builder: (allRows) {
              final rows = allRows.where((row) {
                final inv = row.inventory;
                if (_productFilter != null && inv.productId != _productFilter) {
                  return false;
                }
                if (_filter.storeId != null && inv.storeId != _filter.storeId) {
                  return false;
                }
                if (_filter.godownId != null &&
                    inv.godownId != _filter.godownId) {
                  return false;
                }
                return true;
              }).toList();
              final totalValue = rows.fold<int>(
                0,
                (sum, row) =>
                    sum +
                    Money.roundDiv(
                      row.inventory.quantityMilli *
                          row.product.purchasePricePaise,
                      1000,
                    ),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  SectionCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: LabeledValue(
                            label: 'Stock value',
                            value: Money.format(totalValue),
                            emphasize: true,
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'Low stock items',
                            value: '${lowStock.value?.length ?? 0}',
                            emphasize: true,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  StockLocationDropdown(
                    value: _filter,
                    label: 'Show stock in',
                    autoLabel: 'All locations',
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                  if (_productFilter != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          label: Text(_productFilterName),
                          onDeleted: () =>
                              setState(() => _productFilter = null),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    const EmptyState(
                      title: 'No stock records',
                      message: 'Stock appears here after opening stock, purchases or sales.',
                      icon: Icons.warehouse_outlined,
                    )
                  else
                    for (final row in rows) ...[
                      SectionCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.product.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Text(
                                    row.locationLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${Quantity.format(row.inventory.quantityMilli)} ${row.unitSymbol ?? ''}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  'Min ${Quantity.format(row.product.minStockMilli)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              );
            },
          ),
          _MovementList(),
        ],
      ),
    );
  }

  Future<void> _showAdjustment() async {
    final products = ref.read(productsStreamProvider('')).value ?? const [];
    if (products.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a product first')));
      return;
    }
    var productId = products.first.id;
    var quantity = '';
    var reason = '';
    var isDamage = false;
    var location = const StockLocation();
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
                'Adjust stock',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Positive receives stock, negative issues stock. Every change is '
                'recorded in the stock ledger.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: productId,
                items: products
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setModalState(() => productId = value ?? productId),
                decoration: const InputDecoration(labelText: 'Product'),
              ),
              const SizedBox(height: 10),
              StockLocationDropdown(
                value: location,
                label: 'Location',
                autoLabel: 'No specific location',
                onChanged: (value) => setModalState(() => location = value),
              ),
              const SizedBox(height: 10),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantity change',
                  hintText: 'Example: 10 or -2.5',
                ),
                onChanged: (value) => quantity = value,
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(labelText: 'Reason'),
                onChanged: (value) => reason = value,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Damaged goods'),
                value: isDamage,
                onChanged: (value) => setModalState(() => isDamage = value),
                activeTrackColor: AppColors.accent,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final milli = Quantity.tryParseMilli(quantity);
                  if (milli == null || milli == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a non-zero quantity'),
                      ),
                    );
                    return;
                  }
                  if (reason.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a reason')),
                    );
                    return;
                  }
                  try {
                    await ref
                        .read(catalogRepositoryProvider)
                        .adjustStock(
                          productId: productId,
                          storeId: location.storeId,
                          godownId: location.godownId,
                          deltaMilli: milli,
                          reason: reason.trim(),
                          isDamage: isDamage,
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }
                },
                child: const Text('Record adjustment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(stockMovementsProvider);
    final products = ref.watch(productsStreamProvider('')).value ?? const [];
    final names = {for (final p in products) p.id: p.name};
    return AsyncView(
      value: movements,
      builder: (rows) {
        if (rows.isEmpty) {
          return const EmptyState(
            title: 'No stock movements',
            message: 'Purchases, sales and adjustments appear here.',
            icon: Icons.swap_vert,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final movement = rows[index];
            final inbound = movement.quantityMilli > 0;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(names[movement.productId] ?? movement.productId),
              subtitle: Text(
                '${movement.type.replaceAll('_', ' ')} · ${AppDate.display(movement.occurredAt)}',
              ),
              trailing: Text(
                '${inbound ? '+' : ''}${Quantity.format(movement.quantityMilli)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: inbound ? AppColors.success : AppColors.danger,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

final stockMovementsProvider = StreamProvider<List<StockMovementRow>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchMovements(),
);
