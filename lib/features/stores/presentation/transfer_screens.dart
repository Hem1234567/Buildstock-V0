import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/deliveries/data/operations_repository.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';

String _locationLabel(
  String? storeId,
  String? godownId,
  List<StoreRow> stores,
  List<GodownRow> godowns,
) {
  if (godownId != null) {
    for (final godown in godowns) {
      if (godown.id == godownId) return 'Godown: ${godown.name}';
    }
  }
  if (storeId != null) {
    for (final store in stores) {
      if (store.id == storeId) return 'Store: ${store.name}';
    }
  }
  return 'Unspecified';
}

class TransferListScreen extends ConsumerWidget {
  const TransferListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersStreamProvider);
    final stores = ref.watch(storesStreamProvider).value ?? const <StoreRow>[];
    final godowns =
        ref.watch(godownsStreamProvider(null)).value ?? const <GodownRow>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Stock transfers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transfers/new'),
        icon: const Icon(Icons.add),
        label: const Text('New transfer'),
      ),
      body: AsyncView<List<TransferView>>(
        value: transfers,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No transfers yet',
              message: 'Move stock between stores and godowns. Stock leaves the source immediately and reaches the destination when it is received.',
              icon: Icons.swap_horiz,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final view = rows[index];
              final transfer = view.transfer;
              final inTransit = transfer.status == TransferStatus.inTransit;
              return SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            view.product.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          Quantity.format(view.item.quantityMilli),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${transfer.transferNumber} · ${transfer.status.replaceAll('_', ' ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${_locationLabel(transfer.sourceStoreId, transfer.sourceGodownId, stores, godowns)}'
                      '  →  '
                      '${_locationLabel(transfer.destinationStoreId, transfer.destinationGodownId, stores, godowns)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (inTransit) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _run(
                                context,
                                () => ref
                                    .read(transferRepositoryProvider)
                                    .cancelTransfer(transfer.id),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _run(
                                context,
                                () => ref
                                    .read(transferRepositoryProvider)
                                    .receiveTransfer(transfer.id),
                              ),
                              child: const Text('Mark received'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class TransferFormScreen extends ConsumerWidget {
  const TransferFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products =
        ref.watch(productsStreamProvider('')).value ?? const <ProductRow>[];
    final stores = ref.watch(storesStreamProvider).value ?? const <StoreRow>[];
    final godowns =
        ref.watch(godownsStreamProvider(null)).value ?? const <GodownRow>[];

    final locations = <AppFieldOption>[
      for (final store in stores)
        AppFieldOption(
          StockLocation(storeId: store.id).code,
          'Store: ${store.name}',
        ),
      for (final godown in godowns)
        AppFieldOption(
          StockLocation(storeId: godown.storeId, godownId: godown.id).code,
          'Godown: ${godown.name}',
        ),
    ];

    return AppFormScreen(
      title: 'New stock transfer',
      subtitle: 'Stock is removed from the source now and added to the destination when you mark the transfer received.',
      saveLabel: 'Start transfer',
      fields: [
        AppField(
          key: 'productId',
          label: 'Product',
          type: AppFieldType.dropdown,
          required: true,
          options: products
              .map((product) => AppFieldOption(product.id, product.name))
              .toList(),
        ),
        AppField(
          key: 'source',
          label: 'From',
          type: AppFieldType.dropdown,
          required: true,
          options: locations,
        ),
        AppField(
          key: 'destination',
          label: 'To',
          type: AppFieldType.dropdown,
          required: true,
          options: locations,
        ),
        const AppField(
          key: 'quantity',
          label: 'Quantity',
          type: AppFieldType.quantity,
          required: true,
        ),
        const AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(transferRepositoryProvider)
            .createTransfer(
              TransferInput(
                productId: values['productId'] as String? ?? '',
                quantityMilli: values['quantity'] as int? ?? 0,
                source: StockLocation.parse(values['source'] as String?),
                destination: StockLocation.parse(
                  values['destination'] as String?,
                ),
                notes: values['notes'] as String? ?? '',
              ),
            );
      },
    );
  }
}
