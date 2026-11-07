import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/features/accounts/presentation/account_screens.dart';
import 'package:buildstock/features/business/data/business_repository.dart';
import 'package:buildstock/features/customers/presentation/party_screens.dart';
import 'package:buildstock/features/dashboard/presentation/dashboard_screen.dart';
import 'package:buildstock/features/deliveries/presentation/delivery_screens.dart';
import 'package:buildstock/features/inventory/presentation/inventory_screen.dart';
import 'package:buildstock/features/invoices/presentation/invoice_screens.dart';
import 'package:buildstock/features/products/presentation/product_screens.dart';
import 'package:buildstock/features/purchases/presentation/purchase_screens.dart';
import 'package:buildstock/features/reports/presentation/reports_screen.dart';
import 'package:buildstock/features/returns/presentation/returns_screens.dart';
import 'package:buildstock/features/sales/presentation/checkout_screen.dart';
import 'package:buildstock/features/sales/presentation/sales_screen.dart';
import 'package:buildstock/features/orders/presentation/orders_screens.dart';
import 'package:buildstock/features/search/global_search_screen.dart';
import 'package:buildstock/features/settings/presentation/data_tools_screens.dart';
import 'package:buildstock/features/team/presentation/team_screens.dart';
import 'package:buildstock/features/settings/presentation/printer_settings_screen.dart';
import 'package:buildstock/features/settings/presentation/settings_screens.dart';
import 'package:buildstock/features/setup/presentation/setup_screen.dart';
import 'package:buildstock/features/staff/presentation/workforce_screens.dart';
import 'package:buildstock/features/stores/presentation/store_screens.dart';
import 'package:buildstock/features/stores/presentation/transfer_screens.dart';
import 'package:buildstock/features/sync/presentation/sync_screen.dart';

import 'more_screen.dart';
import 'shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class _ProfileRefresh extends ChangeNotifier {
  _ProfileRefresh(Ref ref) {
    ref.listen(businessProfileProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _ProfileRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final profile = ref.read(businessProfileProvider);
      if (profile.isLoading) return null;
      final hasProfile = profile.value != null;
      final atSetup = state.matchedLocation == '/setup';
      if (!hasProfile && !atSetup) return '/setup';
      if (hasProfile && atSetup) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/more',
            builder: (context, state) => const MoreScreen(),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const SalesScreen(),
          ),
          GoRoute(
            path: '/sales/checkout',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const CheckoutScreen(),
          ),
          GoRoute(
            path: '/invoices',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const InvoiceHistoryScreen(),
          ),
          GoRoute(
            path: '/estimates',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                const InvoiceHistoryScreen(documentType: 'estimate'),
          ),
          GoRoute(
            path: '/quotations',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                const InvoiceHistoryScreen(documentType: 'quotation'),
          ),
          GoRoute(
            path: '/orders',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/orders/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const OrderFormScreen(),
          ),
          GoRoute(
            path: '/orders/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                OrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/search',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const GlobalSearchScreen(),
          ),
          GoRoute(
            path: '/notes/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const NoteFormScreen(),
          ),
          GoRoute(
            path: '/settings/team',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const TeamScreen(),
          ),
          GoRoute(
            path: '/settings/join',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const JoinShopScreen(),
          ),
          GoRoute(
            path: '/settings/backup',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const BackupScreen(),
          ),
          GoRoute(
            path: '/settings/photos',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const PhotoHostingScreen(),
          ),
          GoRoute(
            path: '/settings/low-stock',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const LowStockAlertsScreen(),
          ),
          GoRoute(
            path: '/invoices/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                InvoicePreviewScreen(saleId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/products',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const ProductListScreen(),
          ),
          GoRoute(
            path: '/products/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const ProductFormScreen(),
          ),
          GoRoute(
            path: '/products/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/products/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                ProductFormScreen(productId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/categories',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const CatalogueSettingsScreen(),
          ),
          GoRoute(
            path: '/customers',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const CustomerListScreen(),
          ),
          GoRoute(
            path: '/customers/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const CustomerFormScreen(),
          ),
          GoRoute(
            path: '/customers/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                CustomerDetailScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/customers/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                CustomerFormScreen(customerId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/suppliers',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const SupplierListScreen(),
          ),
          GoRoute(
            path: '/suppliers/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const SupplierFormScreen(),
          ),
          GoRoute(
            path: '/suppliers/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                SupplierDetailScreen(supplierId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/suppliers/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                SupplierFormScreen(supplierId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/purchases',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const PurchaseListScreen(),
          ),
          GoRoute(
            path: '/purchases/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const PurchaseFormScreen(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/expenses',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/expenses/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const ExpenseFormScreen(),
          ),
          GoRoute(
            path: '/day-book',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/stores',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const StoreListScreen(),
          ),
          GoRoute(
            path: '/stores/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const StoreFormScreen(),
          ),
          GoRoute(
            path: '/returns',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const ReturnListScreen(),
          ),
          GoRoute(
            path: '/returns/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const ReturnFormScreen(),
          ),
          GoRoute(
            path: '/transfers',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const TransferListScreen(),
          ),
          GoRoute(
            path: '/transfers/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const TransferFormScreen(),
          ),
          GoRoute(
            path: '/godowns/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const GodownFormScreen(),
          ),
          GoRoute(
            path: '/staff',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const StaffListScreen(),
          ),
          GoRoute(
            path: '/staff/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const StaffFormScreen(),
          ),
          GoRoute(
            path: '/staff/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                StaffFormScreen(staffId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/drivers',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const DriverListScreen(),
          ),
          GoRoute(
            path: '/drivers/new',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const DriverFormScreen(),
          ),
          GoRoute(
            path: '/drivers/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) =>
                DriverFormScreen(driverId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/attendance',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/salary',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const SalaryScreen(),
          ),
          GoRoute(
            path: '/deliveries',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const DeliveryListScreen(),
          ),
          GoRoute(
            path: '/reports',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/settings',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/settings/business',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const BusinessProfileSettingsScreen(),
          ),
          GoRoute(
            path: '/settings/printer',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const PrinterSettingsScreen(),
          ),
          GoRoute(
            path: '/settings/about',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const AboutScreen(),
          ),
          GoRoute(
            path: '/sync',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const SyncCenterScreen(),
          ),
        ],
      ),
    ],
  );
});
