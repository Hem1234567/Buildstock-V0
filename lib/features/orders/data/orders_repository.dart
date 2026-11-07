import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/audit/audit_writer.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';
import 'package:buildstock/features/sales/domain/invoice_calculator.dart';

abstract final class OrderStatus {
  static const open = 'open';
  static const confirmed = 'confirmed';
  static const ready = 'ready';
  static const delivered = 'delivered';
  static const invoiced = 'invoiced';
  static const cancelled = 'cancelled';

  static const all = [open, confirmed, ready, delivered, invoiced, cancelled];

  static String label(String status) => switch (status) {
    open => 'Open',
    confirmed => 'Confirmed',
    ready => 'Ready',
    delivered => 'Delivered',
    invoiced => 'Invoiced',
    cancelled => 'Cancelled',
    _ => status,
  };

  /// Statuses that still need work.
  static bool isActive(String status) =>
      status == open || status == confirmed || status == ready;
}

class OrderLine {
  const OrderLine({
    required this.productId,
    required this.name,
    required this.quantityMilli,
    required this.unitPricePaise,
    this.sku = '',
    this.hsnCode = '',
    this.unit = 'Nos',
    this.taxRateBps = 0,
  });

  final String productId;
  final String name;
  final int quantityMilli;
  final int unitPricePaise;
  final String sku;
  final String hsnCode;
  final String unit;
  final int taxRateBps;

  OrderLine copyWith({int? quantityMilli, int? unitPricePaise}) => OrderLine(
    productId: productId,
    name: name,
    quantityMilli: quantityMilli ?? this.quantityMilli,
    unitPricePaise: unitPricePaise ?? this.unitPricePaise,
    sku: sku,
    hsnCode: hsnCode,
    unit: unit,
    taxRateBps: taxRateBps,
  );

  int get amountPaise => (quantityMilli * unitPricePaise / 1000).round();

  InvoiceLine toInvoiceLine() => InvoiceLine(
    productId: productId,
    name: name,
    sku: sku,
    hsnCode: hsnCode,
    unit: unit,
    quantityMilli: quantityMilli,
    unitPricePaise: unitPricePaise,
    taxRateBps: taxRateBps,
  );

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'quantity_milli': quantityMilli,
    'unit_price_paise': unitPricePaise,
    'sku': sku,
    'hsn_code': hsnCode,
    'unit': unit,
    'tax_rate_bps': taxRateBps,
  };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    productId: (json['product_id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    quantityMilli: (json['quantity_milli'] as num?)?.toInt() ?? 0,
    unitPricePaise: (json['unit_price_paise'] as num?)?.toInt() ?? 0,
    sku: (json['sku'] ?? '').toString(),
    hsnCode: (json['hsn_code'] ?? '').toString(),
    unit: (json['unit'] ?? 'Nos').toString(),
    taxRateBps: (json['tax_rate_bps'] as num?)?.toInt() ?? 0,
  );

  static List<OrderLine> decode(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return [
          for (final item in decoded)
            if (item is Map<String, dynamic>) OrderLine.fromJson(item),
        ];
      }
    } catch (_) {}
    return const [];
  }
}

/// Customer orders: goods a customer has asked for, to be prepared and
/// invoiced later. An order never changes stock; stock moves when the order is
/// turned into an invoice.
class OrdersRepository {
  OrdersRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;

  Stream<List<OrderRow>> watchOrders({String status = ''}) {
    final query = db.select(db.orders)
      ..where(
        (t) => status.isEmpty
            ? const Constant<bool>(true)
            : t.status.equals(status),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Stream<OrderRow?> watchOrder(String id) {
    return (db.select(
      db.orders,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<OrderRow?> orderById(String id) =>
      (db.select(db.orders)..where((t) => t.id.equals(id))).getSingleOrNull();

  static int totalFor(List<OrderLine> lines) {
    if (lines.isEmpty) return 0;
    return InvoiceCalculator.compute(
      lines: lines.map((line) => line.toInvoiceLine()).toList(),
      isGst: true,
    ).grandTotalPaise;
  }

  Future<String> createOrder({
    String? customerId,
    String customerName = '',
    DateTime? expectedDate,
    required List<OrderLine> lines,
    String notes = '',
  }) async {
    if (lines.isEmpty) {
      throw const ValidationFailure('Add at least one product to the order');
    }
    final identity = services.identity;
    final now = DateTime.now();
    final id = Ids.order();
    var name = customerName.trim();
    if (customerId != null) {
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(customerId))).getSingleOrNull();
      if (customer != null) name = customer.name;
    }
    var number = '';
    await db.transaction(() async {
      final sequence = await db.nextSequence(
        key: 'order:${Ids.deviceCodeFromName(identity.deviceCode)}:${now.year}',
        prefix: 'ORD',
      );
      number =
          'ORD-${now.year}-${Ids.deviceCodeFromName(identity.deviceCode)}-'
          '${sequence.toString().padLeft(6, '0')}';
      await db
          .into(db.orders)
          .insert(
            OrdersCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              orderNumber: number,
              customerId: Value(customerId),
              customerName: Value(name.isEmpty ? 'Walk-in Customer' : name),
              expectedDate: Value(expectedDate),
              itemsJson: Value(
                jsonEncode(lines.map((l) => l.toJson()).toList()),
              ),
              totalPaise: Value(totalFor(lines)),
              notes: Value(notes.trim()),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              updatedAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );
      await _enqueue(id, baseVersion: 0);
      await AuditWriter(services).write(
        action: 'order_created',
        entityType: 'order',
        entityId: id,
        after: {'order_number': number},
      );
    });
    return id;
  }

  Future<void> setStatus(String id, String status) async {
    final order = await orderById(id);
    if (order == null) {
      throw const AppFailure(FailureCode.notFound, 'Order not found');
    }
    if (order.status == OrderStatus.invoiced ||
        order.status == OrderStatus.cancelled) {
      throw const ValidationFailure('This order is already closed');
    }
    await _update(order, status: status);
    await AuditWriter(services).write(
      action: 'order_status_changed',
      entityType: 'order',
      entityId: id,
      before: {'status': order.status},
      after: {'status': status},
    );
  }

  Future<void> markInvoiced(String id, String invoiceNumber) async {
    final order = await orderById(id);
    if (order == null) return;
    await _update(
      order,
      status: OrderStatus.invoiced,
      notes:
          '${order.notes}${order.notes.isEmpty ? '' : '\n'}'
          'Invoiced as $invoiceNumber',
    );
  }

  Future<void> _update(OrderRow order, {String? status, String? notes}) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.orders)..where((t) => t.id.equals(order.id))).write(
        OrdersCompanion(
          status: Value(status ?? order.status),
          notes: Value(notes ?? order.notes),
          updatedAt: Value(now),
          version: Value(order.version + 1),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _enqueue(order.id, baseVersion: order.version);
    });
  }

  Future<void> _enqueue(String id, {required int baseVersion}) async {
    final row = await orderById(id);
    final identity = services.identity;
    await services.outbox.enqueue(
      shopId: identity.shopId,
      deviceId: identity.deviceId,
      userId: identity.userId,
      entityType: 'order',
      collection: 'orders',
      entityId: id,
      payload: Json.toCloud(row!.toJson()),
      baseVersion: baseVersion,
      priority: 65,
    );
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(servicesProvider)),
);

final ordersStreamProvider = StreamProvider.family<List<OrderRow>, String>(
  (ref, status) =>
      ref.watch(ordersRepositoryProvider).watchOrders(status: status),
);

final orderProvider = StreamProvider.family<OrderRow?, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).watchOrder(id),
);
