import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/audit/audit_writer.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';
import 'package:buildstock/features/products/data/catalog_repository.dart';

/// A stock location: a store, optionally narrowed to one of its godowns.
class StockLocation {
  const StockLocation({this.storeId, this.godownId});

  final String? storeId;
  final String? godownId;

  /// Encodes the location so it can travel through a dropdown value.
  String get code => '${storeId ?? ''}|${godownId ?? ''}';

  static StockLocation parse(String? code) {
    if (code == null || !code.contains('|')) return const StockLocation();
    final parts = code.split('|');
    return StockLocation(
      storeId: parts[0].isEmpty ? null : parts[0],
      godownId: parts[1].isEmpty ? null : parts[1],
    );
  }

  bool sameAs(StockLocation other) =>
      storeId == other.storeId && godownId == other.godownId;
}

class TransferInput {
  const TransferInput({
    required this.productId,
    required this.quantityMilli,
    required this.source,
    required this.destination,
    this.notes = '',
  });

  final String productId;
  final int quantityMilli;
  final StockLocation source;
  final StockLocation destination;
  final String notes;
}

class TransferView {
  const TransferView({
    required this.transfer,
    required this.item,
    required this.product,
  });

  final StockTransferRow transfer;
  final StockTransferItemRow item;
  final ProductRow product;
}

/// Moves stock between stores/godowns using the auditable movement ledger.
/// Stock leaves the source when the transfer is created (in transit) and only
/// reaches the destination when it is received.
class TransferRepository {
  TransferRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;
  AuditWriter get audit => AuditWriter(services);
  CatalogRepository get _catalog => CatalogRepository(services);

  Stream<List<TransferView>> watchTransfers() {
    final query = db.select(db.stockTransfers).join([
      innerJoin(
        db.stockTransferItems,
        db.stockTransferItems.transferId.equalsExp(db.stockTransfers.id),
      ),
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.stockTransferItems.productId),
      ),
    ])..orderBy([OrderingTerm.desc(db.stockTransfers.createdAt)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => TransferView(
              transfer: row.readTable(db.stockTransfers),
              item: row.readTable(db.stockTransferItems),
              product: row.readTable(db.products),
            ),
          )
          .toList(),
    );
  }

  Future<String> createTransfer(TransferInput input) async {
    if (input.quantityMilli <= 0) {
      throw const ValidationFailure(
        'Transfer quantity must be greater than zero',
      );
    }
    if (input.source.sameAs(input.destination)) {
      throw const ValidationFailure(
        'Source and destination must be different locations',
      );
    }
    if (input.source.storeId == null && input.source.godownId == null) {
      throw const ValidationFailure('Choose a source location');
    }
    if (input.destination.storeId == null &&
        input.destination.godownId == null) {
      throw const ValidationFailure('Choose a destination location');
    }

    final identity = services.identity;
    final now = DateTime.now();
    final transferId = Ids.stockTransfer();
    final itemId = Ids.stockTransferItem();

    await db.transaction(() async {
      final sequence = await db.nextSequence(
        key:
            'transfer:${Ids.deviceCodeFromName(identity.deviceCode)}:${now.year}',
        prefix: 'TRF',
      );
      final number =
          'TRF-${now.year}-${Ids.deviceCodeFromName(identity.deviceCode)}-'
          '${sequence.toString().padLeft(6, '0')}';

      await db
          .into(db.stockTransfers)
          .insert(
            StockTransfersCompanion.insert(
              id: transferId,
              shopId: Value(identity.shopId),
              transferNumber: number,
              sourceStoreId: Value(input.source.storeId),
              sourceGodownId: Value(input.source.godownId),
              destinationStoreId: Value(input.destination.storeId),
              destinationGodownId: Value(input.destination.godownId),
              status: const Value(TransferStatus.inTransit),
              notes: Value(input.notes),
              createdBy: Value(identity.displayName ?? 'Local user'),
              transferDate: now,
              createdAt: now,
              updatedAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );
      await db
          .into(db.stockTransferItems)
          .insert(
            StockTransferItemsCompanion.insert(
              id: itemId,
              shopId: Value(identity.shopId),
              transferId: transferId,
              productId: input.productId,
              quantityMilli: input.quantityMilli,
              updatedAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );

      // Stock-out at the source. Fails if the source does not hold enough.
      await _catalog.recordStockMovement(
        productId: input.productId,
        storeId: input.source.storeId,
        godownId: input.source.godownId,
        type: MovementType.transferOut,
        deltaMilli: -input.quantityMilli,
        referenceType: 'stock_transfer',
        referenceId: transferId,
        note: 'Transfer $number',
      );

      final transfer = await (db.select(
        db.stockTransfers,
      )..where((t) => t.id.equals(transferId))).getSingle();
      final item = await (db.select(
        db.stockTransferItems,
      )..where((t) => t.id.equals(itemId))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'stock_transfer',
        collection: 'stock_transfers',
        entityId: transferId,
        payload: Json.toCloud(transfer.toJson()),
        baseVersion: 0,
        priority: 45,
      );
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'stock_transfer_item',
        collection: 'stock_transfer_items',
        entityId: itemId,
        payload: Json.toCloud(item.toJson()),
        baseVersion: 0,
        priority: 46,
      );
      await audit.write(
        action: 'stock_transferred',
        entityType: 'stock_transfer',
        entityId: transferId,
        after: {
          'number': number,
          'product_id': input.productId,
          'quantity_milli': input.quantityMilli,
        },
      );
    });
    return transferId;
  }

  Future<void> receiveTransfer(String transferId) async {
    await _finish(transferId, received: true);
  }

  Future<void> cancelTransfer(String transferId) async {
    await _finish(transferId, received: false);
  }

  Future<void> _finish(String transferId, {required bool received}) async {
    final identity = services.identity;
    final now = DateTime.now();
    await db.transaction(() async {
      final transfer = await (db.select(
        db.stockTransfers,
      )..where((t) => t.id.equals(transferId))).getSingleOrNull();
      if (transfer == null) {
        throw const ValidationFailure('Transfer not found');
      }
      if (transfer.status != TransferStatus.inTransit) {
        throw const ValidationFailure('Only in-transit transfers can change');
      }
      final item = await (db.select(
        db.stockTransferItems,
      )..where((t) => t.transferId.equals(transferId))).getSingle();

      if (received) {
        await _catalog.recordStockMovement(
          productId: item.productId,
          storeId: transfer.destinationStoreId,
          godownId: transfer.destinationGodownId,
          type: MovementType.transferIn,
          deltaMilli: item.quantityMilli,
          referenceType: 'stock_transfer',
          referenceId: transferId,
          note: 'Received ${transfer.transferNumber}',
        );
      } else {
        await _catalog.recordStockMovement(
          productId: item.productId,
          storeId: transfer.sourceStoreId,
          godownId: transfer.sourceGodownId,
          type: MovementType.correction,
          deltaMilli: item.quantityMilli,
          referenceType: 'stock_transfer',
          referenceId: transferId,
          note: 'Cancelled ${transfer.transferNumber}',
        );
      }

      await (db.update(
        db.stockTransfers,
      )..where((t) => t.id.equals(transferId))).write(
        StockTransfersCompanion(
          status: Value(
            received ? TransferStatus.received : TransferStatus.cancelled,
          ),
          receivedBy: Value(received ? identity.displayName : null),
          receivedAt: Value(received ? now : null),
          updatedAt: Value(now),
          version: Value(transfer.version + 1),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      final updated = await (db.select(
        db.stockTransfers,
      )..where((t) => t.id.equals(transferId))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'stock_transfer',
        collection: 'stock_transfers',
        entityId: transferId,
        payload: Json.toCloud(updated.toJson()),
        baseVersion: transfer.version,
        priority: 45,
      );
      await audit.write(
        action: received
            ? 'stock_transfer_received'
            : 'stock_transfer_cancelled',
        entityType: 'stock_transfer',
        entityId: transferId,
        after: {'status': updated.status},
      );
    });
  }
}

final transferRepositoryProvider = Provider<TransferRepository>(
  (ref) => TransferRepository(ref.watch(servicesProvider)),
);

final transfersStreamProvider = StreamProvider<List<TransferView>>(
  (ref) => ref.watch(transferRepositoryProvider).watchTransfers(),
);
