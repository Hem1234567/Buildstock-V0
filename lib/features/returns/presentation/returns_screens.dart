import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/customers/data/parties_repository.dart';
import 'package:buildstock/features/deliveries/data/operations_repository.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';
import 'package:buildstock/features/business/data/business_repository.dart';
import 'package:buildstock/features/returns/data/note_pdf.dart';
import 'package:buildstock/features/returns/data/returns_repository.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';

class ReturnListScreen extends ConsumerWidget {
  const ReturnListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(returnsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Returns & notes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _chooseNew(context),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: AsyncView<List<ReturnRow>>(
        value: returns,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No returns or notes yet',
              message: 'Record goods returned by customers or sent back to suppliers, or issue a credit or debit note. Original invoices are never edited.',
              icon: Icons.assignment_return_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final row = rows[index];
              final isSale =
                  row.type == ReturnType.saleReturn ||
                  row.type == ReturnType.creditNote ||
                  row.type == ReturnType.debitNote;
              return SectionCard(
                onTap: ReturnType.isNote(row.type)
                    ? () => _noteActions(context, ref, row)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      isSale
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.returnNumber,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${ReturnType.shortLabel(row.type)}'
                            '${row.partyName.isEmpty ? '' : ' · ${row.partyName}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (row.reason.isNotEmpty)
                            Text(
                              row.reason,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      Money.format(row.amountPaise),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _chooseNew(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.assignment_return_outlined),
            title: const Text('Return goods'),
            subtitle: const Text('Adjusts stock and the party balance'),
            onTap: () => Navigator.pop(context, 'return'),
          ),
          ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: const Text('Credit / debit note'),
            subtitle: const Text('Adjusts the party balance only, no stock'),
            onTap: () => Navigator.pop(context, 'note'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  context.push(choice == 'note' ? '/notes/new' : '/returns/new');
}

Future<void> _noteActions(
  BuildContext context,
  WidgetRef ref,
  ReturnRow note,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Print'),
            onTap: () => Navigator.pop(context, 'print'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share PDF'),
            onTap: () => Navigator.pop(context, 'share'),
          ),
        ],
      ),
    ),
  );
  if (action == null) return;
  const builder = NotePdfBuilder();
  final profile = await ref.read(businessRepositoryProvider).profile();
  final bytes = await builder.build(note: note, business: profile);
  if (action == 'print') {
    await builder.print(bytes, note.returnNumber);
  } else {
    await builder.share(bytes, note.returnNumber);
  }
}

class NoteFormScreen extends ConsumerWidget {
  const NoteFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers =
        ref.watch(customersStreamProvider('')).value ?? const <CustomerRow>[];
    final suppliers =
        ref.watch(suppliersStreamProvider('')).value ?? const <SupplierRow>[];
    return AppFormScreen(
      title: 'New credit / debit note',
      subtitle: 'A note changes only the party balance. It never moves stock and never edits the original bill.',
      saveLabel: 'Save note',
      fields: [
        AppField(
          key: 'type',
          label: 'Note type',
          type: AppFieldType.dropdown,
          required: true,
          initial: ReturnType.creditNote,
          options: [
            for (final type in ReturnType.noteTypes)
              AppFieldOption(type, ReturnType.label(type)),
          ],
        ),
        AppField(
          key: 'customerId',
          label: 'Customer (for customer notes)',
          type: AppFieldType.dropdown,
          options: customers
              .map((customer) => AppFieldOption(customer.id, customer.name))
              .toList(),
        ),
        AppField(
          key: 'supplierId',
          label: 'Supplier (for supplier notes)',
          type: AppFieldType.dropdown,
          options: suppliers
              .map((supplier) => AppFieldOption(supplier.id, supplier.name))
              .toList(),
        ),
        const AppField(
          key: 'originalNumber',
          label: 'Original bill number (optional)',
        ),
        const AppField(
          key: 'amount',
          label: 'Note amount (including tax)',
          type: AppFieldType.money,
          required: true,
        ),
        const AppField(
          key: 'reason',
          label: 'Reason',
          type: AppFieldType.multiline,
          required: true,
          helper:
              'For example: rate difference, damaged goods settled in cash.',
        ),
      ],
      onSave: (values) async {
        final type = values['type'] as String? ?? ReturnType.creditNote;
        String? partyId;
        var partyName = '';
        if (ReturnType.isCustomerNote(type)) {
          partyId = values['customerId'] as String?;
          for (final customer in customers) {
            if (customer.id == partyId) partyName = customer.name;
          }
        } else {
          partyId = values['supplierId'] as String?;
          for (final supplier in suppliers) {
            if (supplier.id == partyId) partyName = supplier.name;
          }
        }
        await ref
            .read(returnsRepositoryProvider)
            .saveNote(
              NoteInput(
                type: type,
                partyId: partyId ?? '',
                partyName: partyName,
                amountPaise: values['amount'] as int? ?? 0,
                originalDocumentNumber:
                    values['originalNumber'] as String? ?? '',
                reason: values['reason'] as String? ?? '',
              ),
            );
      },
    );
  }
}

class ReturnFormScreen extends ConsumerWidget {
  const ReturnFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products =
        ref.watch(productsStreamProvider('')).value ?? const <ProductRow>[];
    final customers =
        ref.watch(customersStreamProvider('')).value ?? const <CustomerRow>[];
    final suppliers =
        ref.watch(suppliersStreamProvider('')).value ?? const <SupplierRow>[];
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
      title: 'New return',
      subtitle: 'A return is a separate document. It adjusts stock and the party balance without changing the original invoice.',
      saveLabel: 'Save return',
      fields: [
        const AppField(
          key: 'type',
          label: 'Return type',
          type: AppFieldType.dropdown,
          required: true,
          initial: ReturnType.saleReturn,
          options: [
            AppFieldOption(
              ReturnType.saleReturn,
              'Sales return (from customer)',
            ),
            AppFieldOption(
              ReturnType.purchaseReturn,
              'Purchase return (to supplier)',
            ),
          ],
        ),
        AppField(
          key: 'customerId',
          label: 'Customer (for sales return)',
          type: AppFieldType.dropdown,
          options: customers
              .map((customer) => AppFieldOption(customer.id, customer.name))
              .toList(),
        ),
        AppField(
          key: 'supplierId',
          label: 'Supplier (for purchase return)',
          type: AppFieldType.dropdown,
          options: suppliers
              .map((supplier) => AppFieldOption(supplier.id, supplier.name))
              .toList(),
        ),
        const AppField(
          key: 'originalNumber',
          label: 'Original bill number (optional)',
        ),
        AppField(
          key: 'productId',
          label: 'Product',
          type: AppFieldType.dropdown,
          required: true,
          options: products
              .map((product) => AppFieldOption(product.id, product.name))
              .toList(),
        ),
        const AppField(
          key: 'quantity',
          label: 'Quantity',
          type: AppFieldType.quantity,
          required: true,
        ),
        const AppField(
          key: 'rate',
          label: 'Rate per unit',
          type: AppFieldType.money,
          required: true,
        ),
        AppField(
          key: 'location',
          label: 'Stock location',
          type: AppFieldType.dropdown,
          required: true,
          options: locations,
        ),
        const AppField(
          key: 'restock',
          label: 'Add returned goods back to stock',
          type: AppFieldType.toggle,
          initial: true,
          helper:
              'Applies to sales returns. Purchase returns always reduce stock.',
        ),
        const AppField(
          key: 'reason',
          label: 'Reason',
          type: AppFieldType.multiline,
        ),
      ],
      onSave: (values) async {
        final type = values['type'] as String? ?? ReturnType.saleReturn;
        final isSale = type == ReturnType.saleReturn;
        String? partyId;
        var partyName = '';
        if (isSale) {
          partyId = values['customerId'] as String?;
          for (final customer in customers) {
            if (customer.id == partyId) partyName = customer.name;
          }
        } else {
          partyId = values['supplierId'] as String?;
          for (final supplier in suppliers) {
            if (supplier.id == partyId) partyName = supplier.name;
          }
        }
        final location = StockLocation.parse(values['location'] as String?);
        await ref
            .read(returnsRepositoryProvider)
            .saveReturn(
              ReturnInput(
                type: type,
                productId: values['productId'] as String? ?? '',
                quantityMilli: values['quantity'] as int? ?? 0,
                unitPricePaise: values['rate'] as int? ?? 0,
                partyId: partyId,
                partyName: partyName,
                originalDocumentNumber:
                    values['originalNumber'] as String? ?? '',
                reason: values['reason'] as String? ?? '',
                storeId: location.storeId,
                godownId: location.godownId,
                restock: values['restock'] as bool? ?? true,
              ),
            );
      },
    );
  }
}
