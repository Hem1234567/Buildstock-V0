import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:buildstock/core/backup/backup_service.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/firebase/firebase_runtime.dart';
import 'package:buildstock/core/session/session_service.dart';
import 'package:buildstock/features/orders/data/orders_repository.dart';
import 'package:buildstock/features/returns/data/returns_repository.dart';
import 'package:buildstock/features/search/global_search_screen.dart';

AppServices _services(AppDatabase db) => AppServices(
  db: db,
  runtime: const FirebaseRuntime(),
  identity: const AppIdentity(
    deviceId: 'dev-test',
    deviceName: 'Test device',
    deviceCode: 'TEST01',
    shopId: 'local',
    role: UserRole.owner,
    permissions: {},
  ),
);

Future<void> _addProduct(AppDatabase db, String id, String name) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await db.customStatement(
    'INSERT INTO products (id, name, barcode, purchase_price_paise, '
    'wholesale_price_paise, retail_price_paise, created_at, updated_at) '
    "VALUES (?, ?, '8901234567890', 30000, 35000, 38000, ?, ?)",
    [id, name, now, now],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppServices services;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    services = _services(db);
  });

  tearDown(() async => db.close());

  testWidgets('global search finds a product by name and by barcode', (
    tester,
  ) async {
    await _addProduct(db, 'prd_1', 'Cement 50kg');
    final search = GlobalSearchRepository(db);
    final byName = await search.search('cement');
    expect(byName.where((hit) => hit.group == 'Products'), hasLength(1));
    final byBarcode = await search.search('8901234567890');
    expect(byBarcode.first.route, '/products/prd_1');
  });

  testWidgets('customer order is numbered and listed', (tester) async {
    await _addProduct(db, 'prd_1', 'Cement 50kg');
    final orders = OrdersRepository(services);
    final id = await orders.createOrder(
      customerName: 'Site A',
      lines: const [
        OrderLine(
          productId: 'prd_1',
          name: 'Cement 50kg',
          quantityMilli: 10000,
          unitPricePaise: 38000,
        ),
      ],
    );
    final saved = await orders.orderById(id);
    expect(saved, isNotNull);
    expect(saved!.orderNumber, startsWith('ORD-'));
    expect(saved.status, OrderStatus.open);
    await orders.setStatus(id, OrderStatus.confirmed);
    expect((await orders.orderById(id))!.status, OrderStatus.confirmed);
    await orders.markInvoiced(id, 'VBA-2026-TEST01-000001');
    expect((await orders.orderById(id))!.status, OrderStatus.invoiced);
    expect(() => orders.setStatus(id, OrderStatus.open), throwsA(anything));
  });

  testWidgets('credit note lowers the customer balance, debit note raises it', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT INTO customers (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['cus_1', 'Ravi', now, now],
    );
    final returns = ReturnsRepository(services);
    await returns.saveNote(
      const NoteInput(
        type: ReturnType.creditNote,
        partyId: 'cus_1',
        partyName: 'Ravi',
        amountPaise: 50000,
        reason: 'Rate difference',
      ),
    );
    await returns.saveNote(
      const NoteInput(
        type: ReturnType.debitNote,
        partyId: 'cus_1',
        partyName: 'Ravi',
        amountPaise: 20000,
        reason: 'Extra unloading charge',
      ),
    );
    final rows = await db
        .customSelect(
          "SELECT type, amount_paise, stock_action FROM returns ORDER BY type",
        )
        .get();
    expect(rows, hasLength(2));
    expect(
      rows.every((row) => row.read<String>('stock_action') == 'none'),
      isTrue,
    );
    final stock = await db
        .customSelect('SELECT COUNT(*) AS c FROM stock_movements')
        .getSingle();
    expect(stock.read<int>('c'), 0);
  });

  testWidgets('backup restores business data and keeps the device identity', (
    tester,
  ) async {
    await _addProduct(db, 'prd_1', 'Cement 50kg');
    await db.setSetting(IdentityKeys.deviceCode, 'TEST01');
    final service = BackupService(services);
    final bytes = await service.createBackup();

    await db.customStatement('DELETE FROM products');
    await db.setSetting(IdentityKeys.deviceCode, 'CHANGED');
    final summary = await service.restore(bytes);

    expect(summary.rows, greaterThan(0));
    final products = await db.customSelect('SELECT name FROM products').get();
    expect(products.single.read<String>('name'), 'Cement 50kg');
    // Identity belongs to the installation, not to the backup.
    expect(await db.getSetting(IdentityKeys.deviceCode), 'CHANGED');
    expect(jsonEncode(summary.tables), isNotEmpty);
  });
}
