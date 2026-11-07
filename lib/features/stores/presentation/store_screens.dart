import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/deliveries/data/operations_repository.dart';

class StoreListScreen extends ConsumerWidget {
  const StoreListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesStreamProvider);
    final godowns = ref.watch(godownsStreamProvider(null));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stores & godowns'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Stores'),
              Tab(text: 'Godowns'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StoreList(stores: stores),
            _GodownList(godowns: godowns, stores: stores.value ?? const []),
          ],
        ),
      ),
    );
  }
}

class _StoreList extends StatelessWidget {
  const _StoreList({required this.stores});

  final AsyncValue<List<StoreRow>> stores;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncView(
        value: stores,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No stores yet',
              message: 'Add each real shop location. Stock and staff can then be assigned per store.',
              icon: Icons.store_mall_directory_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final store = rows[index];
              return SectionCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            [
                              store.code,
                              store.phone,
                              store.city,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(store.status),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/stores/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add store'),
      ),
    );
  }
}

class _GodownList extends StatelessWidget {
  const _GodownList({required this.godowns, required this.stores});

  final AsyncValue<List<GodownRow>> godowns;
  final List<StoreRow> stores;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncView(
        value: godowns,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No godowns yet',
              message: 'Add storage locations under a store to track stock by godown.',
              icon: Icons.warehouse_outlined,
            );
          }
          final names = {for (final store in stores) store.id: store.name};
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final godown = rows[index];
              return SectionCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.warehouse_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            godown.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${names[godown.storeId] ?? 'Store'} · ${godown.code}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (godown.capacity.isNotEmpty) Text(godown.capacity),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: stores.isEmpty ? null : () => context.push('/godowns/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add godown'),
      ),
    );
  }
}

class StoreFormScreen extends ConsumerWidget {
  const StoreFormScreen({super.key, this.storeId});

  final String? storeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesStreamProvider).value ?? const [];
    final store = storeId == null
        ? null
        : stores.where((row) => row.id == storeId).firstOrNull;
    return AppFormScreen(
      title: storeId == null ? 'Add store' : 'Edit store',
      saveLabel: 'Save store',
      fields: [
        AppField(
          key: 'name',
          label: 'Store name',
          required: true,
          initial: store?.name,
        ),
        AppField(
          key: 'code',
          label: 'Store code',
          required: true,
          initial: store?.code,
        ),
        AppField(
          key: 'phone',
          label: 'Phone',
          type: AppFieldType.phone,
          initial: store?.phone,
        ),
        AppField(
          key: 'address',
          label: 'Address',
          type: AppFieldType.multiline,
          initial: store?.address,
        ),
        AppField(key: 'city', label: 'City', initial: store?.city),
        AppField(
          key: 'state',
          label: 'State',
          initial: store?.state ?? 'Tamil Nadu',
        ),
        AppField(key: 'pin', label: 'PIN code', initial: store?.pinCode),
        AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
          initial: store?.notes,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(operationsRepositoryProvider)
            .saveStore(
              StoreInput(
                name: values['name'] as String? ?? '',
                code: values['code'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                address: values['address'] as String? ?? '',
                city: values['city'] as String? ?? '',
                state: values['state'] as String? ?? 'Tamil Nadu',
                pinCode: values['pin'] as String? ?? '',
                notes: values['notes'] as String? ?? '',
              ),
              existingId: storeId,
            );
        ref.invalidate(storesStreamProvider);
      },
    );
  }
}

class GodownFormScreen extends ConsumerWidget {
  const GodownFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesStreamProvider).value ?? const [];
    return AppFormScreen(
      title: 'Add godown',
      saveLabel: 'Save godown',
      fields: [
        AppField(
          key: 'storeId',
          label: 'Store',
          type: AppFieldType.dropdown,
          required: true,
          initial: stores.isEmpty ? null : stores.first.id,
          options: stores
              .map((store) => AppFieldOption(store.id, store.name))
              .toList(),
        ),
        const AppField(key: 'name', label: 'Godown name', required: true),
        const AppField(key: 'code', label: 'Godown code', required: true),
        const AppField(
          key: 'address',
          label: 'Address',
          type: AppFieldType.multiline,
        ),
        const AppField(key: 'contact', label: 'Contact person'),
        const AppField(key: 'phone', label: 'Phone', type: AppFieldType.phone),
        const AppField(key: 'capacity', label: 'Capacity'),
        const AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(operationsRepositoryProvider)
            .saveGodown(
              GodownInput(
                storeId: values['storeId'] as String? ?? '',
                name: values['name'] as String? ?? '',
                code: values['code'] as String? ?? '',
                address: values['address'] as String? ?? '',
                contactPerson: values['contact'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                capacity: values['capacity'] as String? ?? '',
                notes: values['notes'] as String? ?? '',
              ),
            );
        ref.invalidate(godownsStreamProvider);
      },
    );
  }
}
