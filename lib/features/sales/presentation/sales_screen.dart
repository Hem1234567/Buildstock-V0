import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/scanner/barcode_scanner_screen.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';
import 'package:buildstock/features/sales/presentation/cart_controller.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    await BarcodeScannerScreen.openContinuous(
      context,
      onScan: (code) async {
        final product = await ref
            .read(catalogRepositoryProvider)
            .productByCode(code);
        if (product == null) return 'No product found for $code';
        ref.read(cartProvider.notifier).addScanned(product);
        return 'Added ${product.name}';
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider(_query));
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            tooltip: 'Scan products',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Invoice history',
            onPressed: () => context.push('/invoices'),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'retail',
                        label: Text('Retail'),
                        icon: Icon(Icons.person_outline, size: 16),
                      ),
                      ButtonSegment(
                        value: 'wholesale',
                        label: Text('Wholesale'),
                        icon: Icon(Icons.storefront_outlined, size: 16),
                      ),
                    ],
                    selected: {cart.saleType},
                    onSelectionChanged: (value) => ref
                        .read(cartProvider.notifier)
                        .setSaleType(value.first),
                    showSelectedIcon: false,
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  label: const Text('GST'),
                  selected: cart.isGst,
                  onSelected: (value) =>
                      ref.read(cartProvider.notifier).setGst(value),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search products or scan barcode',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: products,
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    title: _query.isEmpty
                        ? 'No products to sell yet'
                        : 'No matching products',
                    message: _query.isEmpty
                        ? 'Add your real products first. Sales never shows sample items.'
                        : 'Try another name, SKU or barcode.',
                    icon: Icons.inventory_2_outlined,
                    actionLabel: _query.isEmpty ? 'Add product' : null,
                    onAction: _query.isEmpty
                        ? () => context.push('/products/new')
                        : null,
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: _ProductGrid(items: items)),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 380,
                            child: CartPanel(
                              cart: cart,
                              onCheckout: () => context.push('/sales/checkout'),
                            ),
                          ),
                        ],
                      );
                    }
                    return _ProductGrid(items: items);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton(
                  onPressed: () => _showCart(context, cart),
                  child: Row(
                    children: [
                      Text(
                        '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                      ),
                      const Spacer(),
                      Text(Money.format(cart.totals.grandTotalPaise)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _showCart(BuildContext context, CartState cart) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, controller) => CartPanel(
          cart: cart,
          scrollController: controller,
          onCheckout: () {
            Navigator.pop(context);
            context.push('/sales/checkout');
          },
        ),
      ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.items});

  final List<ProductRow> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1100
            ? 4
            : (constraints.maxWidth > 780 ? 3 : 2);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final product = items[index];
            final cart = ref.watch(cartProvider);
            final price = cart.saleType == 'wholesale'
                ? product.wholesalePricePaise
                : product.retailPricePaise;
            return SectionCard(
              padding: const EdgeInsets.all(12),
              onTap: () => ref.read(cartProvider.notifier).addProduct(product),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          size: 17,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.sku.isEmpty ? 'Tap to add' : product.sku,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    Money.format(price),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class CartPanel extends ConsumerWidget {
  const CartPanel({
    super.key,
    required this.cart,
    required this.onCheckout,
    this.scrollController,
  });

  final CartState cart;
  final VoidCallback onCheckout;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = cart.totals;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              Text('Cart', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (cart.lines.isNotEmpty)
                TextButton(
                  onPressed: () => ref.read(cartProvider.notifier).clear(),
                  child: const Text('Clear'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: cart.lines.isEmpty
              ? const EmptyState(
                  title: 'Cart is empty',
                  message: 'Tap a product to add it to this sale.',
                  icon: Icons.shopping_cart_outlined,
                  compact: true,
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final line = cart.lines[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  line.product.name,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => ref
                                    .read(cartProvider.notifier)
                                    .remove(line.product.id),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _QtyButton(
                                icon: Icons.remove,
                                onTap: () => ref
                                    .read(cartProvider.notifier)
                                    .updateQuantity(
                                      line.product.id,
                                      line.quantityMilli - 1000,
                                    ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  Quantity.format(line.quantityMilli),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              _QtyButton(
                                icon: Icons.add,
                                onTap: () => ref
                                    .read(cartProvider.notifier)
                                    .updateQuantity(
                                      line.product.id,
                                      line.quantityMilli + 1000,
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                '× ${Money.format(line.unitPricePaise)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Money.format(
                                  Money.roundDiv(
                                    line.quantityMilli * line.unitPricePaise,
                                    1000,
                                  ),
                                ),
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (cart.lines.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TotalRow(
                  label: 'Subtotal',
                  value: Money.format(totals.subtotalPaise),
                ),
                if (totals.taxPaise > 0)
                  _TotalRow(label: 'Tax', value: Money.format(totals.taxPaise)),
                const SizedBox(height: 6),
                _TotalRow(
                  label: 'Total',
                  value: Money.format(totals.grandTotalPaise),
                  emphasize: true,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onCheckout,
                    child: const Text('Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 15),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: emphasize
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodySmall,
          ),
          Text(
            value,
            style: emphasize
                ? theme.textTheme.titleLarge
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
