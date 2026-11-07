import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';

import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/products/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search name, SKU or barcode',
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
                        ? 'No products yet'
                        : 'No matching products',
                    message: _query.isEmpty
                        ? 'Add the materials you actually sell. Nothing is pre-filled with demo inventory.'
                        : 'Try another name, SKU or barcode.',
                    icon: Icons.inventory_2_outlined,
                    actionLabel: _query.isEmpty ? 'Add product' : null,
                    onAction: _query.isEmpty
                        ? () => context.push('/products/new')
                        : null,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = items[index];
                    return SectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => context.push('/products/${product.id}'),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (product.sku.isNotEmpty) product.sku,
                                    if (product.hsnCode.isNotEmpty)
                                      'HSN ${product.hsnCode}',
                                    if (product.gstRateBps > 0)
                                      'GST ${(product.gstRateBps / 100).toStringAsFixed(1)}%',
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(product.retailPricePaise),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Retail',
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

class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final brands = ref.watch(brandsProvider).value ?? const [];
    final units = ref.watch(unitsProvider).value ?? const [];
    final product = productId == null
        ? null
        : ref.watch(productProvider(productId!)).value;

    if (productId != null && product == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AppFormScreen(
      title: productId == null ? 'Add product' : 'Edit product',
      subtitle:
          'Prices are stored in paise; quantities use up to three decimals.',
      saveLabel: productId == null ? 'Save product' : 'Update product',
      fields: [
        AppField(
          key: 'name',
          label: 'Product name',
          required: true,
          initial: product?.name,
        ),
        AppField(key: 'sku', label: 'SKU', initial: product?.sku),
        AppField(
          key: 'barcode',
          label: 'Barcode',
          initial: product?.barcode,
          scannable: true,
        ),
        AppField(
          key: 'categoryId',
          label: 'Category',
          type: AppFieldType.dropdown,
          initial: categories.any((c) => c.id == product?.categoryId)
              ? product?.categoryId
              : null,
          options: categories.map((c) => AppFieldOption(c.id, c.name)).toList(),
        ),
        AppField(
          key: 'brandId',
          label: 'Brand',
          type: AppFieldType.dropdown,
          initial: brands.any((b) => b.id == product?.brandId)
              ? product?.brandId
              : null,
          options: brands.map((b) => AppFieldOption(b.id, b.name)).toList(),
        ),
        AppField(
          key: 'unitId',
          label: 'Unit',
          type: AppFieldType.dropdown,
          required: true,
          initial: units.any((u) => u.id == product?.unitId)
              ? product?.unitId
              : null,
          options: units
              .map((u) => AppFieldOption(u.id, '${u.name} (${u.symbol})'))
              .toList(),
        ),
        AppField(key: 'hsnCode', label: 'HSN code', initial: product?.hsnCode),
        AppField(
          key: 'gstRate',
          label: 'GST rate',
          type: AppFieldType.percent,
          initial: product?.gstRateBps,
          helper: 'Use 0 for non-GST items.',
        ),
        AppField(
          key: 'purchasePrice',
          label: 'Purchase price',
          type: AppFieldType.money,
          initial: product?.purchasePricePaise,
        ),
        AppField(
          key: 'retailPrice',
          label: 'Retail price',
          type: AppFieldType.money,
          initial: product?.retailPricePaise,
        ),
        AppField(
          key: 'wholesalePrice',
          label: 'Wholesale price',
          type: AppFieldType.money,
          initial: product?.wholesalePricePaise,
        ),
        AppField(
          key: 'minStock',
          label: 'Minimum stock',
          type: AppFieldType.quantity,
          initial: product?.minStockMilli,
          helper: 'Used for low-stock alerts. Zero disables the alert.',
        ),
        AppField(
          key: 'photo',
          label: 'Product photo',
          type: AppFieldType.photo,
          photoOwner: 'product',
          initial: product?.mainImageRef,
        ),
        AppField(
          key: 'description',
          label: 'Description',
          type: AppFieldType.multiline,
          initial: product?.description,
        ),
        AppField(
          key: 'active',
          label: 'Active',
          type: AppFieldType.toggle,
          initial: product?.active ?? true,
        ),
      ],
      onSave: (values) async {
        final repository = ref.read(catalogRepositoryProvider);
        await repository.saveProduct(
          ProductInput(
            name: values['name'] as String? ?? '',
            sku: values['sku'] as String? ?? '',
            barcode: values['barcode'] as String? ?? '',
            categoryId: values['categoryId'] as String?,
            brandId: values['brandId'] as String?,
            unitId: values['unitId'] as String?,
            hsnCode: values['hsnCode'] as String? ?? '',
            gstRateBps: values['gstRate'] as int? ?? 0,
            purchasePricePaise: values['purchasePrice'] as int? ?? 0,
            retailPricePaise: values['retailPrice'] as int? ?? 0,
            wholesalePricePaise: values['wholesalePrice'] as int? ?? 0,
            minStockMilli: values['minStock'] as int? ?? 0,
            description: values['description'] as String? ?? '',
            imageRef: values['photo'] as String?,
            active: values['active'] as bool? ?? true,
          ),
          existingId: productId,
        );
        ref.invalidate(productsStreamProvider);
        ref.invalidate(productProvider(productId ?? ''));
      },
    );
  }
}

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          AsyncView(
            value: product,
            builder: (data) => IconButton(
              onPressed: data == null
                  ? null
                  : () => context.push('/products/${data.id}/edit'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        ],
      ),
      body: AsyncView(
        value: product,
        builder: (data) {
          if (data == null) {
            return const EmptyState(
              title: 'Product not found',
              message: 'This product may have been archived.',
              icon: Icons.inventory_2_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (data.sku.isNotEmpty) 'SKU ${data.sku}',
                        if (data.hsnCode.isNotEmpty) 'HSN ${data.hsnCode}',
                        if (!data.active) 'Archived',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledValue(
                            label: 'Retail',
                            value: Money.format(data.retailPricePaise),
                            emphasize: true,
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'Wholesale',
                            value: Money.format(data.wholesalePricePaise),
                            emphasize: true,
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'Purchase',
                            value: Money.format(data.purchasePricePaise),
                            emphasize: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledValue(
                            label: 'GST',
                            value:
                                '${(data.gstRateBps / 100).toStringAsFixed(1)}%',
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'Minimum stock',
                            value: Quantity.format(data.minStockMilli),
                          ),
                        ),
                      ],
                    ),
                    if (data.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(data.description),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final repository = ref.read(catalogRepositoryProvider);
                  await repository.archiveProduct(data.id);
                  ref.invalidate(productsStreamProvider);
                  if (context.mounted) context.pop();
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive product'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CatalogueSettingsScreen extends ConsumerWidget {
  const CatalogueSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final brands = ref.watch(brandsProvider);
    final units = ref.watch(unitsProvider);
    final repository = ref.read(catalogRepositoryProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catalogue settings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Categories'),
              Tab(text: 'Brands'),
              Tab(text: 'Units'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NamedList(
              value: categories,
              onAdd: (name) async {
                await repository.addCategory(name);
                ref.invalidate(categoriesProvider);
              },
            ),
            _NamedList(
              value: brands,
              onAdd: (name) async {
                await repository.addBrand(name);
                ref.invalidate(brandsProvider);
              },
            ),
            _NamedList(
              value: units,
              onAdd: null,
              emptyMessage: 'Units are seeded on first launch and can be extended in a future update. Standard units such as Bag, Ton, Cft and Nos are available.',
            ),
          ],
        ),
      ),
    );
  }
}

class _NamedList extends StatelessWidget {
  const _NamedList({
    required this.value,
    required this.onAdd,
    this.emptyMessage = 'No records yet.',
  });

  final AsyncValue<List<Object>> value;
  final Future<void> Function(String name)? onAdd;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return AsyncView(
      value: value,
      builder: (rows) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (onAdd != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final controller = TextEditingController();
                    final name = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Add'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(context, controller.text),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await onAdd!(name);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            if (rows.isEmpty)
              EmptyState(title: 'Nothing here yet', message: emptyMessage)
            else
              for (final row in rows)
                ListTile(
                  title: Text((row as dynamic).name as String? ?? ''),
                  dense: true,
                ),
          ],
        );
      },
    );
  }
}
