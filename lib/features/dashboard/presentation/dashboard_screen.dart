import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/features/business/data/business_repository.dart';
import 'package:buildstock/features/dashboard/presentation/dashboard_repository.dart';
import 'package:buildstock/features/sales/data/sales_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final recent = ref.watch(recentInvoicesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(recentInvoicesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.value?.name ?? 'Vijay Balaji Agency',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${AppDate.displayLong(DateTime.now())} · ${AppDate.time(DateTime.now())}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const _SyncButton(),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              AsyncView(
                value: summary,
                builder: (data) => _SummaryGrid(data: data),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Quick actions'),
              _QuickActions(theme: theme),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: 'Recent invoices',
                actionLabel: 'View all',
                onAction: () => context.push('/invoices'),
              ),
              AsyncView(
                value: recent,
                builder: (invoices) {
                  final rows = invoices;
                  if (rows.isEmpty) {
                    return const SectionCard(
                      child: EmptyState(
                        title: 'No invoices yet',
                        message: 'Create your first invoice from Sales. Nothing is pre-filled with sample data.',
                        icon: Icons.receipt_long_outlined,
                        compact: true,
                      ),
                    );
                  }
                  return SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final invoice in rows)
                          ListTile(
                            title: Text(invoice.invoiceNumber),
                            subtitle: Text(
                              '${AppDate.display(invoice.invoiceDate)} · ${Money.format(invoice.grandTotalPaise)}',
                            ),
                            trailing: StatusPill.document(
                              invoice.documentStatus,
                            ),
                            onTap: () =>
                                context.push('/invoices/${invoice.id}'),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              if (profile.value == null)
                SectionCard(
                  color: AppColors.accentSoft,
                  borderColor: AppColors.accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete your business profile',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Invoices need your real business name, address, phone and UPI ID. '
                        'Add them before your first bill.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () => context.push('/settings/business'),
                        child: const Text('Set up business profile'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncButton extends ConsumerWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sync Center',
      onPressed: () => context.push('/sync'),
      icon: const Icon(Icons.cloud_outlined),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Today\'s Sales',
        Money.format(data.todaySalesPaise),
        Icons.trending_up,
        AppColors.success,
      ),
      (
        'Today\'s Purchases',
        Money.format(data.todayPurchasesPaise),
        Icons.local_shipping_outlined,
        AppColors.info,
      ),
      (
        'Today\'s Expenses',
        Money.format(data.todayExpensesPaise),
        Icons.payments_outlined,
        AppColors.warning,
      ),
      (
        'Customer Outstanding',
        Money.format(data.receivablesPaise),
        Icons.account_balance_wallet_outlined,
        AppColors.accent,
      ),
      (
        'Supplier Payable',
        Money.format(data.payablesPaise),
        Icons.request_quote_outlined,
        AppColors.danger,
      ),
      (
        'Low Stock',
        '${data.lowStockCount}',
        Icons.inventory_2_outlined,
        AppColors.warning,
      ),
      (
        'Pending Deliveries',
        '${data.pendingDeliveries}',
        Icons.delivery_dining_outlined,
        AppColors.info,
      ),
      (
        'Pending Salaries',
        Money.format(data.pendingSalariesPaise),
        Icons.badge_outlined,
        AppColors.accent,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 720
            ? 4
            : (constraints.maxWidth > 460 ? 2 : 2);
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _StatCard(
                  label: item.$1,
                  value: item.$2,
                  icon: item.$3,
                  color: item.$4,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('New invoice', Icons.add, '/sales'),
      ('New purchase', Icons.keyboard_arrow_down, '/purchases/new'),
      ('Add product', Icons.inventory_2_outlined, '/products/new'),
      ('Add customer', Icons.person_add_alt, '/customers/new'),
      ('Add expense', Icons.receipt_long_outlined, '/expenses/new'),
      ('Reports', Icons.bar_chart_outlined, '/reports'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          ActionChip(
            avatar: Icon(action.$2, size: 16),
            label: Text(action.$1),
            onPressed: () => context.push(action.$3),
          ),
      ],
    );
  }
}
