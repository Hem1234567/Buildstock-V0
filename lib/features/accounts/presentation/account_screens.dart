import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';

import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/accounts/data/accounts_repository.dart';

final cashInHandProvider = FutureProvider<int>(
  (ref) => ref.watch(accountsRepositoryProvider).cashInHand(),
);

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  DateTimeRange _range = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime.now(),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cash = ref.watch(cashInHandProvider);
    final dayBook = ref.watch(dayBookProvider(_range));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Day Book'),
            Tab(text: 'Expenses'),
            Tab(text: 'Payments'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: LabeledValue(
                      label: 'Cash in hand',
                      value: cash.maybeWhen(
                        data: Money.format,
                        orElse: () => '—',
                      ),
                      emphasize: true,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: InkWell(
                      onTap: _pickRange,
                      child: LabeledValue(
                        label: 'Period',
                        value:
                            '${AppDate.display(_range.start)} – ${AppDate.display(_range.end)}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                AsyncView(
                  value: dayBook,
                  builder: (rows) {
                    if (rows.isEmpty) {
                      return const EmptyState(
                        title: 'No transactions',
                        message: 'Sales, purchases, payments and expenses for this period appear here.',
                        icon: Icons.menu_book_outlined,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final entry = rows[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.type),
                          subtitle: Text(
                            '${entry.reference} · ${AppDate.display(entry.date)}',
                          ),
                          trailing: Text(
                            '${entry.isIncoming ? '+' : '-'}${Money.format(entry.amountPaise)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: entry.isIncoming
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const _ExpenseList(),
                const _PaymentList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }
}

class _ExpenseList extends ConsumerWidget {
  const _ExpenseList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesStreamProvider(''));
    return Scaffold(
      body: AsyncView(
        value: expenses,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No expenses recorded',
              message: 'Rent, fuel, salaries and other real business costs appear here.',
              icon: Icons.receipt_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final expense = rows[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(expense.categoryName),
                subtitle: Text(
                  '${expense.description.isEmpty ? expense.method : expense.description} · ${AppDate.display(expense.paidAt)}',
                ),
                trailing: Text(
                  Money.format(expense.amountPaise),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
    );
  }
}

class _PaymentList extends ConsumerWidget {
  const _PaymentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentsStreamProvider);
    return AsyncView(
      value: payments,
      builder: (rows) {
        if (rows.isEmpty) {
          return const EmptyState(
            title: 'No payments recorded',
            message: 'Customer receipts and supplier payments appear here.',
            icon: Icons.payments_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final payment = rows[index];
            final incoming = payment.direction == 'in';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                payment.partyName.isEmpty
                    ? payment.partyType
                    : payment.partyName,
              ),
              subtitle: Text(
                '${payment.method} · ${AppDate.display(payment.paidAt)}',
              ),
              trailing: Text(
                '${incoming ? '+' : '-'}${Money.format(payment.amountPaise)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: incoming ? AppColors.success : AppColors.danger,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ExpenseFormScreen extends ConsumerWidget {
  const ExpenseFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(expenseCategoriesProvider).value ?? const [];
    return AppFormScreen(
      title: 'Add expense',
      saveLabel: 'Save expense',
      fields: [
        AppField(
          key: 'category',
          label: 'Category',
          type: AppFieldType.dropdown,
          required: true,
          initial: categories.isEmpty ? null : categories.first.id,
          options: categories
              .map((category) => AppFieldOption(category.id, category.name))
              .toList(),
        ),
        const AppField(
          key: 'amount',
          label: 'Amount',
          type: AppFieldType.money,
          required: true,
        ),
        AppField(
          key: 'date',
          label: 'Date',
          type: AppFieldType.date,
          initial: DateTime.now(),
        ),
        const AppField(
          key: 'method',
          label: 'Payment method',
          type: AppFieldType.dropdown,
          initial: 'cash',
          options: [
            AppFieldOption('cash', 'Cash'),
            AppFieldOption('bank', 'Bank transfer'),
            AppFieldOption('upi', 'UPI'),
            AppFieldOption('cheque', 'Cheque'),
            AppFieldOption('other', 'Other'),
          ],
        ),
        const AppField(
          key: 'description',
          label: 'Description',
          type: AppFieldType.multiline,
        ),
      ],
      onSave: (values) async {
        final categoryId = values['category'] as String?;
        final category = categories.firstWhere(
          (item) => item.id == categoryId,
          orElse: () => categories.first,
        );
        await ref
            .read(accountsRepositoryProvider)
            .saveExpense(
              ExpenseInput(
                amountPaise: values['amount'] as int? ?? 0,
                categoryId: category.id,
                categoryName: category.name,
                paidAt: values['date'] as DateTime?,
                method: values['method'] as String? ?? 'cash',
                description: values['description'] as String? ?? '',
              ),
            );
        ref.invalidate(expensesStreamProvider);
        ref.invalidate(cashInHandProvider);
        ref.invalidate(dayBookProvider);
      },
    );
  }
}
