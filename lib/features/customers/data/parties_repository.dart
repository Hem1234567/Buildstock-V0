import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/audit/audit_writer.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';

class CustomerInput {
  const CustomerInput({
    required this.name,
    this.businessName = '',
    this.phone = '',
    this.altPhone = '',
    this.email = '',
    this.billingAddress = '',
    this.deliveryAddress = '',
    this.city = '',
    this.state = 'Tamil Nadu',
    this.pinCode = '',
    this.gstin = '',
    this.pan = '',
    this.customerType = 'retail',
    this.creditLimitPaise = 0,
    this.openingBalancePaise = 0,
    this.notes = '',
    this.photoRef,
  });

  final String name;
  final String businessName;
  final String phone;
  final String altPhone;
  final String email;
  final String billingAddress;
  final String deliveryAddress;
  final String city;
  final String state;
  final String pinCode;
  final String gstin;
  final String pan;
  final String customerType;
  final int creditLimitPaise;
  final int openingBalancePaise;
  final String notes;
  final String? photoRef;
}

class SupplierInput {
  const SupplierInput({
    required this.name,
    this.businessName = '',
    this.phone = '',
    this.altPhone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.state = 'Tamil Nadu',
    this.pinCode = '',
    this.gstin = '',
    this.pan = '',
    this.openingBalancePaise = 0,
    this.notes = '',
    this.photoRef,
  });

  final String name;
  final String businessName;
  final String phone;
  final String altPhone;
  final String email;
  final String address;
  final String city;
  final String state;
  final String pinCode;
  final String gstin;
  final String pan;
  final int openingBalancePaise;
  final String notes;
  final String? photoRef;
}

enum LedgerKind { opening, sale, purchase, payment, returnDoc, salary, expense }

class LedgerEntry {
  const LedgerEntry({
    required this.date,
    required this.title,
    required this.kind,
    this.reference = '',
    this.debitPaise = 0,
    this.creditPaise = 0,
  });

  final DateTime date;
  final String title;
  final LedgerKind kind;
  final String reference;
  final int debitPaise;
  final int creditPaise;

  int get signedPaise => debitPaise - creditPaise;
}

class PartiesRepository {
  PartiesRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;
  AuditWriter get audit => AuditWriter(services);

  // --------------------------------------------------------------- customers

  Stream<List<CustomerRow>> watchCustomers({String query = ''}) {
    final statement = db.select(db.customers)
      ..where((t) => t.active.equals(true) & t.deletedAt.isNull());
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where(
        (t) =>
            t.name.like(pattern) |
            t.phone.like(pattern) |
            t.businessName.like(pattern) |
            t.gstin.like(pattern),
      );
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return statement.watch();
  }

  Future<CustomerRow?> customerById(String id) => (db.select(
    db.customers,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> saveCustomer(CustomerInput input, {String? existingId}) async {
    if (input.name.trim().isEmpty) {
      throw const ValidationFailure('Customer name is required');
    }
    final existing = existingId == null ? null : await customerById(existingId);
    final id = existing?.id ?? Ids.customer();
    final now = DateTime.now();
    final identity = services.identity;
    final version = (existing?.version ?? 0) + 1;

    await db.transaction(() async {
      await db
          .into(db.customers)
          .insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              name: input.name.trim(),
              businessName: Value(input.businessName.trim()),
              phone: Value(input.phone.trim()),
              altPhone: Value(input.altPhone.trim()),
              email: Value(input.email.trim()),
              billingAddress: Value(input.billingAddress.trim()),
              deliveryAddress: Value(input.deliveryAddress.trim()),
              city: Value(input.city.trim()),
              state: Value(input.state.trim()),
              pinCode: Value(input.pinCode.trim()),
              gstin: Value(input.gstin.trim().toUpperCase()),
              pan: Value(input.pan.trim().toUpperCase()),
              customerType: Value(input.customerType),
              creditLimitPaise: Value(input.creditLimitPaise),
              openingBalancePaise: Value(input.openingBalancePaise),
              photoRef: Value(input.photoRef),
              notes: Value(input.notes.trim()),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              version: Value(version),
              deviceId: Value(identity.deviceId),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );
      final row = await customerById(id);
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'customer',
        collection: 'customers',
        entityId: id,
        payload: Json.toCloud(row!.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 12,
      );
      await audit.write(
        action: existing == null ? 'customer_created' : 'customer_updated',
        entityType: 'customer',
        entityId: id,
        before: existing?.toJson(),
        after: row.toJson(),
      );
    });
    return id;
  }

  Future<void> archiveCustomer(String id) async {
    final existing = await customerById(id);
    if (existing == null) {
      throw const AppFailure(FailureCode.notFound, 'Customer not found');
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.customers)..where((t) => t.id.equals(id))).write(
        CustomersCompanion(
          active: const Value(false),
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
          syncStatus: const Value(SyncStatus.pending),
          deviceId: Value(services.identity.deviceId),
        ),
      );
      final row = await customerById(id);
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'customer',
        collection: 'customers',
        entityId: id,
        payload: Json.toCloud(row!.toJson()),
        baseVersion: existing.version,
        priority: 12,
      );
    });
  }

  /// Outstanding balance for every customer, computed from ledgers rather than
  /// a mutable cached total.
  Stream<Map<String, int>> watchCustomerBalances() {
    return db
        .customSelect(
          '''
          SELECT c.id AS id,
            c.opening_balance_paise
              + COALESCE(s.total, 0)
              - COALESCE(p.total, 0)
              - COALESCE(r.total, 0) AS outstanding
          FROM customers c
          LEFT JOIN (
            SELECT customer_id, SUM(grand_total_paise) AS total
            FROM sales
            WHERE document_status = 'finalized' AND document_type = 'invoice'
            GROUP BY customer_id
          ) s ON s.customer_id = c.id
          LEFT JOIN (
            SELECT party_id, SUM(amount_paise) AS total
            FROM payments
            WHERE party_type = 'customer' AND direction = 'in'
            GROUP BY party_id
          ) p ON p.party_id = c.id
          LEFT JOIN (
            SELECT party_id,
              SUM(CASE WHEN type = 'debit_note' THEN -amount_paise
                       ELSE amount_paise END) AS total
            FROM returns
            WHERE type IN ('sale_return', 'credit_note', 'debit_note')
              AND status = 'finalized'
            GROUP BY party_id
          ) r ON r.party_id = c.id
          ''',
          readsFrom: {db.customers, db.sales, db.payments, db.returns},
        )
        .watch()
        .map(
          (rows) => {
            for (final row in rows)
              row.read<String>('id'): row.read<int>('outstanding'),
          },
        );
  }

  Future<int> customerOutstanding(String customerId) async {
    final row = await db
        .customSelect(
          '''
          SELECT
            (SELECT COALESCE(opening_balance_paise, 0) FROM customers WHERE id = ?) +
            (SELECT COALESCE(SUM(grand_total_paise), 0) FROM sales
              WHERE customer_id = ? AND document_status = 'finalized'
                AND document_type = 'invoice') -
            (SELECT COALESCE(SUM(amount_paise), 0) FROM payments
              WHERE party_id = ? AND party_type = 'customer' AND direction = 'in') -
            (SELECT COALESCE(SUM(CASE WHEN type = 'debit_note'
                                      THEN -amount_paise ELSE amount_paise END), 0)
              FROM returns
              WHERE party_id = ?
                AND type IN ('sale_return', 'credit_note', 'debit_note')
                AND status = 'finalized')
            AS outstanding
          ''',
          variables: [
            Variable(customerId),
            Variable(customerId),
            Variable(customerId),
            Variable(customerId),
          ],
          readsFrom: {db.customers, db.sales, db.payments, db.returns},
        )
        .getSingle();
    return row.read<int>('outstanding');
  }

  Future<List<LedgerEntry>> customerLedger(String customerId) async {
    final customer = await customerById(customerId);
    if (customer == null) return const [];
    final entries = <LedgerEntry>[];
    if (customer.openingBalancePaise != 0) {
      entries.add(
        LedgerEntry(
          date: customer.createdAt,
          title: 'Opening balance',
          kind: LedgerKind.opening,
          debitPaise: customer.openingBalancePaise,
        ),
      );
    }
    final invoices =
        await (db.select(db.sales)..where(
              (t) =>
                  t.customerId.equals(customerId) &
                  t.documentStatus.equals(DocumentStatus.finalized) &
                  t.documentType.equals(DocumentType.invoice),
            ))
            .get();
    for (final invoice in invoices) {
      entries.add(
        LedgerEntry(
          date: invoice.invoiceDate,
          title: 'Invoice ${invoice.invoiceNumber}',
          kind: LedgerKind.sale,
          reference: invoice.id,
          debitPaise: invoice.grandTotalPaise,
        ),
      );
    }
    final payments =
        await (db.select(db.payments)..where(
              (t) =>
                  t.partyId.equals(customerId) &
                  t.partyType.equals(PartyType.customer) &
                  t.direction.equals(PaymentDirection.incoming),
            ))
            .get();
    for (final payment in payments) {
      entries.add(
        LedgerEntry(
          date: payment.paidAt,
          title: 'Payment received (${payment.method})',
          kind: LedgerKind.payment,
          reference: payment.id,
          creditPaise: payment.amountPaise,
        ),
      );
    }
    final returns =
        await (db.select(db.returns)..where(
              (t) =>
                  t.partyId.equals(customerId) &
                  t.type.isIn([
                    ReturnType.saleReturn,
                    ReturnType.creditNote,
                    ReturnType.debitNote,
                  ]) &
                  t.status.equals(DocumentStatus.finalized),
            ))
            .get();
    for (final document in returns) {
      entries.add(
        LedgerEntry(
          date: document.createdAt,
          title: switch (document.type) {
            ReturnType.creditNote => 'Credit note ${document.returnNumber}',
            ReturnType.debitNote => 'Debit note ${document.returnNumber}',
            _ => 'Sales return ${document.returnNumber}',
          },
          kind: LedgerKind.returnDoc,
          reference: document.id,
          debitPaise: document.type == ReturnType.debitNote
              ? document.amountPaise
              : 0,
          creditPaise: document.type == ReturnType.debitNote
              ? 0
              : document.amountPaise,
        ),
      );
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  // --------------------------------------------------------------- suppliers

  Stream<List<SupplierRow>> watchSuppliers({String query = ''}) {
    final statement = db.select(db.suppliers)
      ..where((t) => t.active.equals(true) & t.deletedAt.isNull());
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where(
        (t) =>
            t.name.like(pattern) |
            t.phone.like(pattern) |
            t.businessName.like(pattern) |
            t.gstin.like(pattern),
      );
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return statement.watch();
  }

  Future<SupplierRow?> supplierById(String id) => (db.select(
    db.suppliers,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> saveSupplier(SupplierInput input, {String? existingId}) async {
    if (input.name.trim().isEmpty) {
      throw const ValidationFailure('Supplier name is required');
    }
    final existing = existingId == null ? null : await supplierById(existingId);
    final id = existing?.id ?? Ids.supplier();
    final now = DateTime.now();
    final identity = services.identity;
    final version = (existing?.version ?? 0) + 1;

    await db.transaction(() async {
      await db
          .into(db.suppliers)
          .insertOnConflictUpdate(
            SuppliersCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              name: input.name.trim(),
              businessName: Value(input.businessName.trim()),
              phone: Value(input.phone.trim()),
              altPhone: Value(input.altPhone.trim()),
              email: Value(input.email.trim()),
              address: Value(input.address.trim()),
              city: Value(input.city.trim()),
              state: Value(input.state.trim()),
              pinCode: Value(input.pinCode.trim()),
              gstin: Value(input.gstin.trim().toUpperCase()),
              pan: Value(input.pan.trim().toUpperCase()),
              openingBalancePaise: Value(input.openingBalancePaise),
              photoRef: Value(input.photoRef),
              notes: Value(input.notes.trim()),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              version: Value(version),
              deviceId: Value(identity.deviceId),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );
      final row = await supplierById(id);
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'supplier',
        collection: 'suppliers',
        entityId: id,
        payload: Json.toCloud(row!.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 12,
      );
      await audit.write(
        action: existing == null ? 'supplier_created' : 'supplier_updated',
        entityType: 'supplier',
        entityId: id,
        before: existing?.toJson(),
        after: row.toJson(),
      );
    });
    return id;
  }

  Stream<Map<String, int>> watchSupplierBalances() {
    return db
        .customSelect(
          '''
          SELECT s.id AS id,
            s.opening_balance_paise
              + COALESCE(p.total, 0)
              - COALESCE(pay.total, 0)
              - COALESCE(r.total, 0) AS payable
          FROM suppliers s
          LEFT JOIN (
            SELECT supplier_id, SUM(grand_total_paise) AS total
            FROM purchases WHERE status = 'finalized'
            GROUP BY supplier_id
          ) p ON p.supplier_id = s.id
          LEFT JOIN (
            SELECT party_id, SUM(amount_paise) AS total
            FROM payments
            WHERE party_type = 'supplier' AND direction = 'out'
            GROUP BY party_id
          ) pay ON pay.party_id = s.id
          LEFT JOIN (
            SELECT party_id,
              SUM(CASE WHEN type = 'purchase_credit_note' THEN -amount_paise
                       ELSE amount_paise END) AS total
            FROM returns
            WHERE type IN ('purchase_return', 'purchase_debit_note',
                           'purchase_credit_note')
              AND status = 'finalized'
            GROUP BY party_id
          ) r ON r.party_id = s.id
          ''',
          readsFrom: {db.suppliers, db.purchases, db.payments, db.returns},
        )
        .watch()
        .map(
          (rows) => {
            for (final row in rows)
              row.read<String>('id'): row.read<int>('payable'),
          },
        );
  }

  Future<int> supplierPayable(String supplierId) async {
    final row = await db
        .customSelect(
          '''
          SELECT
            (SELECT COALESCE(opening_balance_paise, 0) FROM suppliers WHERE id = ?) +
            (SELECT COALESCE(SUM(grand_total_paise), 0) FROM purchases
              WHERE supplier_id = ? AND status = 'finalized') -
            (SELECT COALESCE(SUM(amount_paise), 0) FROM payments
              WHERE party_id = ? AND party_type = 'supplier' AND direction = 'out')
            AS payable
          ''',
          variables: [
            Variable(supplierId),
            Variable(supplierId),
            Variable(supplierId),
          ],
          readsFrom: {db.suppliers, db.purchases, db.payments},
        )
        .getSingle();
    return row.read<int>('payable');
  }
}

final partiesRepositoryProvider = Provider<PartiesRepository>(
  (ref) => PartiesRepository(ref.watch(servicesProvider)),
);

final customersStreamProvider =
    StreamProvider.family<List<CustomerRow>, String>((ref, query) {
      return ref.watch(partiesRepositoryProvider).watchCustomers(query: query);
    });

final suppliersStreamProvider =
    StreamProvider.family<List<SupplierRow>, String>((ref, query) {
      return ref.watch(partiesRepositoryProvider).watchSuppliers(query: query);
    });

final customerProvider = FutureProvider.family<CustomerRow?, String>((ref, id) {
  return ref.watch(partiesRepositoryProvider).customerById(id);
});

final supplierProvider = FutureProvider.family<SupplierRow?, String>((ref, id) {
  return ref.watch(partiesRepositoryProvider).supplierById(id);
});

final customerBalancesProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(partiesRepositoryProvider).watchCustomerBalances(),
);

final supplierBalancesProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(partiesRepositoryProvider).watchSupplierBalances(),
);

final customerLedgerProvider = FutureProvider.family<List<LedgerEntry>, String>(
  (ref, id) {
    return ref.watch(partiesRepositoryProvider).customerLedger(id);
  },
);
