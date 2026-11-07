import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/core/widgets/section_card.dart';

import 'theme/app_theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<(String, IconData, String)>)>[
      (
        'Catalogue',
        [
          ('Products', Icons.inventory_2_outlined, '/products'),
          ('Inventory', Icons.warehouse_outlined, '/inventory'),
          ('Stores & Godowns', Icons.store_mall_directory_outlined, '/stores'),
          ('Stock Transfers', Icons.swap_horiz, '/transfers'),
          ('Categories & Units', Icons.category_outlined, '/categories'),
        ],
      ),
      (
        'People',
        [
          ('Customers', Icons.people_outline, '/customers'),
          ('Suppliers', Icons.local_shipping_outlined, '/suppliers'),
          ('Staff', Icons.badge_outlined, '/staff'),
          ('Drivers & Vehicles', Icons.drive_eta_outlined, '/drivers'),
        ],
      ),
      (
        'Operations',
        [
          ('Purchases', Icons.shopping_cart_outlined, '/purchases'),
          ('Invoices', Icons.receipt_long_outlined, '/invoices'),
          ('Estimates', Icons.description_outlined, '/estimates'),
          ('Quotations', Icons.request_quote_outlined, '/quotations'),
          ('Customer Orders', Icons.assignment_outlined, '/orders'),
          (
            'Returns & Credit/Debit Notes',
            Icons.assignment_return_outlined,
            '/returns',
          ),
          ('Deliveries', Icons.delivery_dining_outlined, '/deliveries'),
          ('Attendance', Icons.fact_check_outlined, '/attendance'),
          ('Salary', Icons.payments_outlined, '/salary'),
          ('Expenses', Icons.receipt_outlined, '/expenses'),
          ('Day Book', Icons.menu_book_outlined, '/day-book'),
        ],
      ),
      (
        'Business',
        [
          ('Reports', Icons.bar_chart_outlined, '/reports'),
          ('Search Everything', Icons.search, '/search'),
          ('Business Settings', Icons.settings_outlined, '/settings'),
          ('Team & Devices', Icons.groups_outlined, '/settings/team'),
          ('Backup & Restore', Icons.backup_outlined, '/settings/backup'),
          ('Sync Center', Icons.cloud_outlined, '/sync'),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (final group in groups) ...[
            SectionHeader(title: group.$1),
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final item in group.$2)
                    ListTile(
                      leading: Icon(item.$2, size: 20),
                      title: Text(item.$1),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push(item.$3),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}
