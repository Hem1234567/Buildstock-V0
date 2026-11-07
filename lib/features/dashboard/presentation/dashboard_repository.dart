import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/utils/dates.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.todaySalesPaise,
    required this.todayPurchasesPaise,
    required this.todayExpensesPaise,
    required this.receivablesPaise,
    required this.payablesPaise,
    required this.lowStockCount,
    required this.pendingDeliveries,
    required this.pendingSalariesPaise,
  });

  final int todaySalesPaise;
  final int todayPurchasesPaise;
  final int todayExpensesPaise;
  final int receivablesPaise;
  final int payablesPaise;
  final int lowStockCount;
  final int pendingDeliveries;
  final int pendingSalariesPaise;

  bool get isEmpty =>
      todaySalesPaise == 0 &&
      todayPurchasesPaise == 0 &&
      todayExpensesPaise == 0 &&
      receivablesPaise == 0 &&
      payablesPaise == 0;
}

/// Aggregates are computed by SQLite over real records; no figure is cached or
/// simulated. `readsFrom` makes the dashboard stream update as the business is
/// operated offline.
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final start = AppDate.startOfDay(now);
  final end = AppDate.endOfDay(now);

  final row = await db
      .customSelect(
        '''
        SELECT
          (SELECT COALESCE(SUM(grand_total_paise), 0) FROM sales
            WHERE document_type = 'invoice' AND document_status = 'finalized'
              AND invoice_date BETWEEN ? AND ?) AS today_sales,
          (SELECT COALESCE(SUM(grand_total_paise), 0) FROM purchases
            WHERE status = 'finalized'
              AND purchase_date BETWEEN ? AND ?) AS today_purchases,
          (SELECT COALESCE(SUM(amount_paise), 0) FROM expenses
            WHERE paid_at BETWEEN ? AND ?) AS today_expenses,
          (SELECT MAX(0,
             (SELECT COALESCE(SUM(opening_balance_paise), 0) FROM customers) +
             (SELECT COALESCE(SUM(grand_total_paise), 0) FROM sales
                WHERE document_type = 'invoice'
                  AND document_status = 'finalized') -
             (SELECT COALESCE(SUM(amount_paise), 0) FROM payments
                WHERE party_type = 'customer' AND direction = 'in') -
             (SELECT COALESCE(SUM(CASE WHEN type = 'debit_note'
                                       THEN -amount_paise ELSE amount_paise END), 0)
                FROM returns
                WHERE type IN ('sale_return', 'credit_note', 'debit_note')
                  AND status = 'finalized')
           )) AS receivables,
          (SELECT MAX(0,
             (SELECT COALESCE(SUM(opening_balance_paise), 0) FROM suppliers) +
             (SELECT COALESCE(SUM(grand_total_paise), 0) FROM purchases
                WHERE status = 'finalized') -
             (SELECT COALESCE(SUM(amount_paise), 0) FROM payments
                WHERE party_type = 'supplier' AND direction = 'out') -
             (SELECT COALESCE(SUM(CASE WHEN type = 'purchase_credit_note'
                                       THEN -amount_paise ELSE amount_paise END), 0)
                FROM returns
                WHERE type IN ('purchase_return', 'purchase_debit_note',
                               'purchase_credit_note')
                  AND status = 'finalized')
           )) AS payables,
          (SELECT COUNT(*) FROM products p
            WHERE p.active = 1 AND p.min_stock_milli > 0
              AND COALESCE((SELECT SUM(i.quantity_milli) FROM inventories i
                WHERE i.product_id = p.id), 0) <= p.min_stock_milli
          ) AS low_stock,
          (SELECT COUNT(*) FROM deliveries
            WHERE status NOT IN ('delivered', 'cancelled', 'failed')
          ) AS pending_deliveries,
          (SELECT COALESCE(SUM(balance_due_paise), 0) FROM salary_records
            WHERE status IN ('draft', 'pending', 'partially_paid')
          ) AS pending_salaries
        ''',
        variables: [
          Variable(start),
          Variable(end),
          Variable(start),
          Variable(end),
          Variable(start),
          Variable(end),
        ],
        readsFrom: {
          db.sales,
          db.purchases,
          db.expenses,
          db.customers,
          db.suppliers,
          db.payments,
          db.returns,
          db.products,
          db.inventories,
          db.deliveries,
          db.salaryRecords,
        },
      )
      .getSingle();

  return DashboardSummary(
    todaySalesPaise: row.read<int>('today_sales'),
    todayPurchasesPaise: row.read<int>('today_purchases'),
    todayExpensesPaise: row.read<int>('today_expenses'),
    receivablesPaise: row.read<int>('receivables'),
    payablesPaise: row.read<int>('payables'),
    lowStockCount: row.read<int>('low_stock'),
    pendingDeliveries: row.read<int>('pending_deliveries'),
    pendingSalariesPaise: row.read<int>('pending_salaries'),
  );
});
