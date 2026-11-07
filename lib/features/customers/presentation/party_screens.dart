import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/customers/data/parties_repository.dart';
import 'package:buildstock/features/sales/data/sales_repository.dart';
import 'package:buildstock/core/widgets/feedback.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersStreamProvider(_query));
    final balances = ref.watch(customerBalancesProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customers/new'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search name, phone or GSTIN',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: customers,
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    title: 'No customers yet',
                    message: 'Add real customers to track credit and deliveries. Walk-in billing works without a saved customer.',
                    icon: Icons.people_outline,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final customer = rows[index];
                    final balance = balances[customer.id] ?? 0;
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push('/customers/${customer.id}'),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.accentSoft,
                            child: Text(
                              customer.name.isEmpty
                                  ? '?'
                                  : customer.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  [
                                    if (customer.phone.isNotEmpty)
                                      customer.phone,
                                    customer.customerType,
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(balance < 0 ? 0 : balance),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: balance > 0
                                          ? AppColors.warning
                                          : AppColors.success,
                                    ),
                              ),
                              Text(
                                'Outstanding',
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

class CustomerFormScreen extends ConsumerWidget {
  const CustomerFormScreen({super.key, this.customerId});

  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = customerId == null
        ? null
        : ref.watch(customerProvider(customerId!)).value;
    if (customerId != null && customer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AppFormScreen(
      title: customerId == null ? 'Add customer' : 'Edit customer',
      saveLabel: customerId == null ? 'Save customer' : 'Update customer',
      fields: [
        AppField(
          key: 'name',
          label: 'Customer name',
          required: true,
          initial: customer?.name,
        ),
        AppField(
          key: 'businessName',
          label: 'Business name',
          initial: customer?.businessName,
        ),
        AppField(
          key: 'phone',
          label: 'Phone',
          type: AppFieldType.phone,
          initial: customer?.phone,
        ),
        AppField(
          key: 'altPhone',
          label: 'Alternate phone',
          type: AppFieldType.phone,
          initial: customer?.altPhone,
        ),
        AppField(
          key: 'email',
          label: 'Email',
          type: AppFieldType.email,
          initial: customer?.email,
        ),
        AppField(
          key: 'billingAddress',
          label: 'Billing address',
          type: AppFieldType.multiline,
          initial: customer?.billingAddress,
        ),
        AppField(
          key: 'deliveryAddress',
          label: 'Delivery address',
          type: AppFieldType.multiline,
          initial: customer?.deliveryAddress,
        ),
        AppField(key: 'city', label: 'City', initial: customer?.city),
        AppField(
          key: 'state',
          label: 'State',
          initial: customer?.state ?? 'Tamil Nadu',
        ),
        AppField(key: 'pinCode', label: 'PIN code', initial: customer?.pinCode),
        AppField(key: 'gstin', label: 'GSTIN', initial: customer?.gstin),
        AppField(key: 'pan', label: 'PAN', initial: customer?.pan),
        AppField(
          key: 'customerType',
          label: 'Customer type',
          type: AppFieldType.dropdown,
          initial: customer?.customerType ?? 'retail',
          options: const [
            AppFieldOption('retail', 'Retail'),
            AppFieldOption('wholesale', 'Wholesale'),
          ],
        ),
        AppField(
          key: 'creditLimit',
          label: 'Credit limit',
          type: AppFieldType.money,
          initial: customer?.creditLimitPaise,
        ),
        AppField(
          key: 'openingBalance',
          label: 'Opening balance (due from customer)',
          type: AppFieldType.money,
          initial: customer?.openingBalancePaise,
        ),
        AppField(
          key: 'photo',
          label: 'Customer photo',
          type: AppFieldType.photo,
          photoOwner: 'customer',
          initial: customer?.photoRef,
        ),
        AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
          initial: customer?.notes,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(partiesRepositoryProvider)
            .saveCustomer(
              CustomerInput(
                name: values['name'] as String? ?? '',
                businessName: values['businessName'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                altPhone: values['altPhone'] as String? ?? '',
                email: values['email'] as String? ?? '',
                billingAddress: values['billingAddress'] as String? ?? '',
                deliveryAddress: values['deliveryAddress'] as String? ?? '',
                city: values['city'] as String? ?? '',
                state: values['state'] as String? ?? 'Tamil Nadu',
                pinCode: values['pinCode'] as String? ?? '',
                gstin: values['gstin'] as String? ?? '',
                pan: values['pan'] as String? ?? '',
                customerType: values['customerType'] as String? ?? 'retail',
                creditLimitPaise: values['creditLimit'] as int? ?? 0,
                openingBalancePaise: values['openingBalance'] as int? ?? 0,
                photoRef: values['photo'] as String?,
                notes: values['notes'] as String? ?? '',
              ),
              existingId: customerId,
            );
        ref.invalidate(customersStreamProvider);
        ref.invalidate(customerProvider(customerId ?? ''));
        ref.invalidate(customerBalancesProvider);
      },
    );
  }
}

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    final ledger = ref.watch(customerLedgerProvider(customerId));
    final balances = ref.watch(customerBalancesProvider).value ?? const {};
    final balance = balances[customerId] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          IconButton(
            onPressed: () => context.push('/customers/$customerId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: AsyncView(
        value: customer,
        builder: (row) {
          if (row == null) {
            return const EmptyState(
              title: 'Customer not found',
              message: 'This customer may have been archived.',
              icon: Icons.person_outline,
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
                      row.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (row.businessName.isNotEmpty) Text(row.businessName),
                    const SizedBox(height: 4),
                    Text(
                      [
                        row.phone,
                        row.city,
                        row.state,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (row.gstin.isNotEmpty) Text('GSTIN ${row.gstin}'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledValue(
                            label: 'Outstanding',
                            value: Money.format(balance < 0 ? 0 : balance),
                            emphasize: true,
                            color: balance > 0
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'Credit limit',
                            value: Money.format(row.creditLimitPaise),
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'Type',
                            value: row.customerType,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                _recordPayment(context, ref, row, balance),
                            child: const Text('Record payment'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.go('/sales'),
                            child: const Text('New sale'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Ledger'),
              AsyncView(
                value: ledger,
                builder: (rows) {
                  if (rows.isEmpty) {
                    return const SectionCard(
                      child: EmptyState(
                        title: 'No transactions',
                        message: 'Invoices and payments for this customer will appear here.',
                        compact: true,
                      ),
                    );
                  }
                  return SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final entry in rows)
                          ListTile(
                            dense: true,
                            title: Text(entry.title),
                            subtitle: Text(AppDate.display(entry.date)),
                            trailing: Text(
                              entry.debitPaise > 0
                                  ? 'Dr ${Money.format(entry.debitPaise)}'
                                  : 'Cr ${Money.format(entry.creditPaise)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: entry.debitPaise > 0
                                    ? AppColors.lightText
                                    : AppColors.success,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    CustomerRow customer,
    int balance,
  ) async {
    final amount = TextEditingController(
      text: balance > 0 ? (balance / 100).toStringAsFixed(2) : '',
    );
    var method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                ],
                onChanged: (value) =>
                    setDialogState(() => method = value ?? method),
                decoration: const InputDecoration(labelText: 'Method'),
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
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final paise = Money.tryParseRupees(amount.text) ?? 0;
    if (paise <= 0) return;
    try {
      await ref
          .read(salesRepositoryProvider)
          .recordPayment(
            partyType: PartyType.customer,
            partyId: customer.id,
            partyName: customer.name,
            amountPaise: paise,
            method: method,
          );
      ref.invalidate(customerLedgerProvider(customerId));
      ref.invalidate(customerBalancesProvider);
      if (context.mounted) {
        showActionMessage(context, 'Payment recorded');
      }
    } catch (error) {
      if (context.mounted) showActionMessage(context, error.toString());
    }
  }
}

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersStreamProvider(_query));
    final balances = ref.watch(supplierBalancesProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/suppliers/new'),
        icon: const Icon(Icons.add_business),
        label: const Text('Add supplier'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search supplier or phone',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: suppliers,
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    title: 'No suppliers yet',
                    message: 'Add the suppliers you actually buy from to record purchases and payables.',
                    icon: Icons.local_shipping_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final supplier = rows[index];
                    final payable = balances[supplier.id] ?? 0;
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push('/suppliers/${supplier.id}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  supplier.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  supplier.phone,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(payable < 0 ? 0 : payable),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: payable > 0
                                          ? AppColors.danger
                                          : AppColors.success,
                                    ),
                              ),
                              Text(
                                'Payable',
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

class SupplierFormScreen extends ConsumerWidget {
  const SupplierFormScreen({super.key, this.supplierId});

  final String? supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplier = supplierId == null
        ? null
        : ref.watch(supplierProvider(supplierId!)).value;
    if (supplierId != null && supplier == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AppFormScreen(
      title: supplierId == null ? 'Add supplier' : 'Edit supplier',
      saveLabel: supplierId == null ? 'Save supplier' : 'Update supplier',
      fields: [
        AppField(
          key: 'name',
          label: 'Supplier name',
          required: true,
          initial: supplier?.name,
        ),
        AppField(
          key: 'businessName',
          label: 'Business name',
          initial: supplier?.businessName,
        ),
        AppField(
          key: 'phone',
          label: 'Phone',
          type: AppFieldType.phone,
          initial: supplier?.phone,
        ),
        AppField(
          key: 'email',
          label: 'Email',
          type: AppFieldType.email,
          initial: supplier?.email,
        ),
        AppField(
          key: 'address',
          label: 'Address',
          type: AppFieldType.multiline,
          initial: supplier?.address,
        ),
        AppField(key: 'city', label: 'City', initial: supplier?.city),
        AppField(
          key: 'state',
          label: 'State',
          initial: supplier?.state ?? 'Tamil Nadu',
        ),
        AppField(key: 'pinCode', label: 'PIN code', initial: supplier?.pinCode),
        AppField(key: 'gstin', label: 'GSTIN', initial: supplier?.gstin),
        AppField(key: 'pan', label: 'PAN', initial: supplier?.pan),
        AppField(
          key: 'openingBalance',
          label: 'Opening payable',
          type: AppFieldType.money,
          initial: supplier?.openingBalancePaise,
        ),
        AppField(
          key: 'photo',
          label: 'Supplier photo',
          type: AppFieldType.photo,
          photoOwner: 'supplier',
          initial: supplier?.photoRef,
        ),
        AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
          initial: supplier?.notes,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(partiesRepositoryProvider)
            .saveSupplier(
              SupplierInput(
                name: values['name'] as String? ?? '',
                businessName: values['businessName'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                email: values['email'] as String? ?? '',
                address: values['address'] as String? ?? '',
                city: values['city'] as String? ?? '',
                state: values['state'] as String? ?? 'Tamil Nadu',
                pinCode: values['pinCode'] as String? ?? '',
                gstin: values['gstin'] as String? ?? '',
                pan: values['pan'] as String? ?? '',
                openingBalancePaise: values['openingBalance'] as int? ?? 0,
                photoRef: values['photo'] as String?,
                notes: values['notes'] as String? ?? '',
              ),
              existingId: supplierId,
            );
        ref.invalidate(suppliersStreamProvider);
        ref.invalidate(supplierProvider(supplierId ?? ''));
        ref.invalidate(supplierBalancesProvider);
      },
    );
  }
}

class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplier = ref.watch(supplierProvider(supplierId));
    final balances = ref.watch(supplierBalancesProvider).value ?? const {};
    final payable = balances[supplierId] ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier')),
      body: AsyncView(
        value: supplier,
        builder: (row) {
          if (row == null) {
            return const EmptyState(
              title: 'Supplier not found',
              message: 'This supplier may have been archived.',
              icon: Icons.local_shipping_outlined,
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
                      row.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      [
                        row.phone,
                        row.city,
                        row.state,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledValue(
                            label: 'Payable',
                            value: Money.format(payable < 0 ? 0 : payable),
                            emphasize: true,
                            color: payable > 0
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                        Expanded(
                          child: LabeledValue(
                            label: 'GSTIN',
                            value: row.gstin.isEmpty ? '—' : row.gstin,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => context.push('/purchases/new'),
                            child: const Text('New purchase'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _recordPayment(context, ref, row, payable),
                            child: const Text('Pay supplier'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    SupplierRow supplier,
    int payable,
  ) async {
    final amount = TextEditingController(
      text: payable > 0 ? (payable / 100).toStringAsFixed(2) : '',
    );
    var method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pay supplier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                ],
                onChanged: (value) =>
                    setDialogState(() => method = value ?? method),
                decoration: const InputDecoration(labelText: 'Method'),
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
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final paise = Money.tryParseRupees(amount.text) ?? 0;
    if (paise <= 0) return;
    try {
      await ref
          .read(salesRepositoryProvider)
          .recordPayment(
            partyType: PartyType.supplier,
            partyId: supplier.id,
            partyName: supplier.name,
            amountPaise: paise,
            method: method,
          );
      ref.invalidate(supplierBalancesProvider);
      if (context.mounted) showActionMessage(context, 'Payment recorded');
    } catch (error) {
      if (context.mounted) showActionMessage(context, error.toString());
    }
  }
}
