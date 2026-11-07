import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/customers/data/parties_repository.dart';
import 'package:buildstock/features/orders/data/orders_repository.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';
import 'package:buildstock/features/sales/presentation/cart_controller.dart';

Color _statusColor(String status) => switch (status) {
  OrderStatus.open => AppColors.warning,
  OrderStatus.confirmed => AppColors.info,
  OrderStatus.ready => AppColors.accent,
  OrderStatus.delivered || OrderStatus.invoiced => AppColors.success,
  _ => AppColors.danger,
};

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersStreamProvider(_status));
    return Scaffold(
      appBar: AppBar(title: const Text('Customer orders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('New order'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _status.isEmpty,
                    onSelected: (_) => setState(() => _status = ''),
                  ),
                ),
                for (final status in OrderStatus.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(OrderStatus.label(status)),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: orders,
              builder: (rows) {
                if (rows.isEmpty) {
                  return EmptyState(
                    title: 'No orders yet',
                    message: 'Record what a customer asks for now and turn it into an invoice when you deliver.',
                    icon: Icons.assignment_outlined,
                    actionLabel: 'New order',
                    onAction: () => context.push('/orders/new'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = rows[index];
                    final lines = OrderLine.decode(order.itemsJson);
                    return SectionCard(
                      onTap: () => context.push('/orders/${order.id}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.orderNumber,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(order.customerName),
                                Text(
                                  '${lines.length} item(s)'
                                  '${order.expectedDate == null ? '' : ' · due ${AppDate.display(order.expectedDate!)}'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(order.totalPaise),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              StatusPill(
                                label: OrderStatus.label(order.status),
                                color: _statusColor(order.status),
                                background: _statusColor(order.status)
                                    .withValues(alpha: 0.12),
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

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Order')),
      body: AsyncView(
        value: order,
        builder: (row) {
          if (row == null) {
            return const EmptyState(
              title: 'Order not found',
              message: 'This order is not available on this device.',
              icon: Icons.assignment_outlined,
            );
          }
          final lines = OrderLine.decode(row.itemsJson);
          final active = OrderStatus.isActive(row.status);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.orderNumber,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusPill(
                          label: OrderStatus.label(row.status),
                          color: _statusColor(row.status),
                          background: _statusColor(row.status)
                              .withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(row.customerName),
                    if (row.expectedDate != null)
                      Text(
                        'Expected ${AppDate.displayLong(row.expectedDate!)}',
                      ),
                    if (row.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(row.notes),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.name),
                                  Text(
                                    '${Quantity.format(line.quantityMilli)} ${line.unit} × ${Money.format(line.unitPricePaise)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(Money.format(line.amountPaise)),
                          ],
                        ),
                      ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total (with GST)'),
                        Text(
                          Money.format(row.totalPaise),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (active) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _createInvoice(context, ref, row, lines),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Create invoice from order'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (row.status == OrderStatus.open)
                      OutlinedButton(
                        onPressed: () => _status(
                          context,
                          ref,
                          row.id,
                          OrderStatus.confirmed,
                        ),
                        child: const Text('Confirm'),
                      ),
                    if (row.status != OrderStatus.ready)
                      OutlinedButton(
                        onPressed: () =>
                            _status(context, ref, row.id, OrderStatus.ready),
                        child: const Text('Mark ready'),
                      ),
                    OutlinedButton(
                      onPressed: () =>
                          _status(context, ref, row.id, OrderStatus.delivered),
                      child: const Text('Mark delivered'),
                    ),
                    TextButton(
                      onPressed: () => _cancel(context, ref, row.id),
                      child: const Text(
                        'Cancel order',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _status(
    BuildContext context,
    WidgetRef ref,
    String id,
    String status,
  ) async {
    try {
      await ref.read(ordersRepositoryProvider).setStatus(id, status);
    } catch (error) {
      if (context.mounted) showActionMessage(context, error.toString());
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text('The order stays in the list as cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _status(context, ref, id, OrderStatus.cancelled);
    }
  }

  Future<void> _createInvoice(
    BuildContext context,
    WidgetRef ref,
    OrderRow order,
    List<OrderLine> lines,
  ) async {
    final catalog = ref.read(catalogRepositoryProvider);
    final cartLines = <CartLine>[];
    final missing = <String>[];
    for (final line in lines) {
      final product = await catalog.productById(line.productId);
      if (product == null) {
        missing.add(line.name);
        continue;
      }
      cartLines.add(
        CartLine(
          product: product,
          quantityMilli: line.quantityMilli,
          unitPricePaise: line.unitPricePaise,
        ),
      );
    }
    if (cartLines.isEmpty) {
      if (context.mounted) {
        showActionMessage(
          context,
          'None of the ordered products exist any more',
        );
      }
      return;
    }
    ref
        .read(cartProvider.notifier)
        .loadFromOrder(
          orderId: order.id,
          customerId: order.customerId,
          lines: cartLines,
        );
    if (!context.mounted) return;
    if (missing.isNotEmpty) {
      showActionMessage(
        context,
        'Skipped missing products: ${missing.join(', ')}',
      );
    }
    context.push('/sales/checkout');
  }
}

class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key});

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  String? _customerId;
  DateTime? _expected;
  final List<OrderLine> _lines = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addProduct() async {
    final product = await showModalBottomSheet<ProductRow>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _ProductPickerSheet(),
    );
    if (product == null) return;
    setState(() {
      final index = _lines.indexWhere((line) => line.productId == product.id);
      if (index >= 0) {
        _lines[index] = _lines[index].copyWith(
          quantityMilli: _lines[index].quantityMilli + 1000,
        );
      } else {
        _lines.add(
          OrderLine(
            productId: product.id,
            name: product.name,
            quantityMilli: 1000,
            unitPricePaise: product.retailPricePaise,
            sku: product.sku,
            hsnCode: product.hsnCode,
            unit: product.unitId ?? 'Nos',
            taxRateBps: product.gstRateBps,
          ),
        );
      }
    });
  }

  Future<void> _editLine(int index) async {
    final line = _lines[index];
    final quantity = TextEditingController(
      text: Quantity.format(line.quantityMilli),
    );
    final price = TextEditingController(
      text: (line.unitPricePaise / 100).toStringAsFixed(2),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Rate (₹)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final milli = Quantity.tryParseMilli(quantity.text);
    final paise = Money.tryParseRupees(price.text);
    quantity.dispose();
    price.dispose();
    if (saved != true || milli == null || paise == null) return;
    setState(() {
      if (milli <= 0) {
        _lines.removeAt(index);
      } else {
        _lines[index] = line.copyWith(
          quantityMilli: milli,
          unitPricePaise: paise,
        );
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(ordersRepositoryProvider)
          .createOrder(
            customerId: _customerId,
            customerName: _name.text,
            expectedDate: _expected,
            lines: _lines,
            notes: _notes.text,
          );
      if (mounted) context.pushReplacement('/orders/$id');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersStreamProvider(''));
    final total = OrdersRepository.totalFor(_lines);
    return Scaffold(
      appBar: AppBar(title: const Text('New customer order')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          SectionCard(
            child: Column(
              children: [
                AsyncView(
                  value: customers,
                  loading: const LinearProgressIndicator(),
                  builder: (rows) => DropdownButtonFormField<String?>(
                    initialValue: _customerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Walk-in customer'),
                      ),
                      for (final customer in rows)
                        DropdownMenuItem<String?>(
                          value: customer.id,
                          child: Text(customer.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _customerId = value),
                  ),
                ),
                if (_customerId == null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Customer name (optional)',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _expected ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) setState(() => _expected = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Expected delivery date',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(
                      _expected == null
                          ? 'Select date'
                          : AppDate.display(_expected!),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionHeader(
            title: 'Items',
            actionLabel: 'Add product',
            onAction: _addProduct,
          ),
          if (_lines.isEmpty)
            const EmptyState(
              title: 'No items yet',
              message: 'Add the products the customer has asked for.',
              icon: Icons.inventory_2_outlined,
              compact: true,
            )
          else
            SectionCard(
              child: Column(
                children: [
                  for (var i = 0; i < _lines.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_lines[i].name),
                      subtitle: Text(
                        '${Quantity.format(_lines[i].quantityMilli)} × ${Money.format(_lines[i].unitPricePaise)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(Money.format(_lines[i].amountPaise)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _lines.removeAt(i)),
                          ),
                        ],
                      ),
                      onTap: () => _editLine(i),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: _saving || _lines.isEmpty ? null : _save,
          child: Text('Save order · ${Money.format(total)}'),
        ),
      ),
    );
  }
}

class _ProductPickerSheet extends ConsumerStatefulWidget {
  const _ProductPickerSheet();

  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider(_query));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SearchField(
                  controller: _search,
                  hint: 'Search products',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: AsyncView(
                  value: products,
                  builder: (rows) => ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final product = rows[index];
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text(Money.format(product.retailPricePaise)),
                        onTap: () => Navigator.pop(context, product),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
