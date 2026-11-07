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

class ReturnInput {
  const ReturnInput({
    required this.type,
    required this.productId,
    required this.quantityMilli,
    required this.unitPricePaise,
    this.partyId,
    this.partyName = '',
    this.originalDocumentNumber = '',
    this.reason = '',
    this.storeId,
    this.godownId,
    this.restock = true,
  });

  final String type;
  final String productId;
  final int quantityMilli;
  final int unitPricePaise;
  final String? partyId;
  final String partyName;
  final String originalDocumentNumber;
  final String reason;
  final String? storeId;
  final String? godownId;
  final bool restock;
}

class NoteInput {
  const NoteInput({
    required this.type,
    required this.partyId,
    required this.partyName,
    required this.amountPaise,
    this.taxRateBps = 0,
    this.originalDocumentNumber = '',
    this.reason = '',
  });

  /// One of [ReturnType.noteTypes].
  final String type;
  final String partyId;
  final String partyName;

  /// Total of the note including tax.
  final int amountPaise;
  final int taxRateBps;
  final String originalDocumentNumber;
  final String reason;
}

/// Sales returns (customer sends goods back) and purchase returns (goods go
/// back to a supplier). Original invoices are never edited: a return is a
/// separate finalized document that adjusts stock and the party balance.
class ReturnsRepository {
  ReturnsRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;
  AuditWriter get audit => AuditWriter(services);
  CatalogRepository get _catalog => CatalogRepository(services);

  Stream<List<ReturnRow>> watchReturns() => (db.select(
    db.returns,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  /// Records a credit or debit note. A note only changes the party balance.
  /// It never touches stock, and the original invoice stays as it was.
  Future<String> saveNote(NoteInput input) async {
    if (!ReturnType.isNote(input.type)) {
      throw const ValidationFailure('Choose a note type');
    }
    if (input.amountPaise <= 0) {
      throw const ValidationFailure('Enter the note amount');
    }
    if (input.partyId.isEmpty) {
      throw const ValidationFailure('Choose the customer or supplier');
    }
    if (input.reason.trim().isEmpty) {
      throw const ValidationFailure('Write the reason for this note');
    }
    final identity = services.identity;
    final now = DateTime.now();
    final noteId = Ids.returnDoc();
    final itemId = Ids.newId('rti');
    await db.transaction(() async {
      final code = Ids.deviceCodeFromName(identity.deviceCode);
      final prefix = ReturnType.prefix(input.type);
      final sequence = await db.nextSequence(
        key: 'note:${input.type}:$code:${now.year}',
        prefix: prefix,
      );
      final number =
          '$prefix-${now.year}-$code-${sequence.toString().padLeft(6, '0')}';
      await db
          .into(db.returns)
          .insert(
            ReturnsCompanion.insert(
              id: noteId,
              shopId: Value(identity.shopId),
              returnNumber: number,
              type: Value(input.type),
              partyId: Value(input.partyId),
              partyName: Value(input.partyName),
              originalDocumentNumber: Value(input.originalDocumentNumber),
              reason: Value(input.reason.trim()),
              amountPaise: Value(input.amountPaise),
              refundMethod: const Value('credit'),
              stockAction: const Value('none'),
              status: const Value(DocumentStatus.finalized),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              finalizedAt: Value(now),
              deviceId: Value(identity.deviceId),
            ),
          );
      await db
          .into(db.returnItems)
          .insert(
            ReturnItemsCompanion.insert(
              id: itemId,
              shopId: Value(identity.shopId),
              returnId: noteId,
              productId: 'adjustment',
              productName: input.reason.trim(),
              quantityMilli: 1000,
              unitPricePaise: input.amountPaise,
              taxRateBps: Value(input.taxRateBps),
              lineTotalPaise: Value(input.amountPaise),
              createdAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );
      final row = await (db.select(
        db.returns,
      )..where((t) => t.id.equals(noteId))).getSingle();
      final item = await (db.select(
        db.returnItems,
      )..where((t) => t.id.equals(itemId))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'return',
        collection: 'returns',
        entityId: noteId,
        payload: Json.toCloud(row.toJson()),
        baseVersion: 0,
        priority: 50,
      );
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'return_item',
        collection: 'return_items',
        entityId: itemId,
        payload: Json.toCloud(item.toJson()),
        baseVersion: 0,
        priority: 51,
      );
      await audit.write(
        action: 'note_recorded',
        entityType: 'return',
        entityId: noteId,
        after: {
          'number': number,
          'type': input.type,
          'amount_paise': input.amountPaise,
          'reason': input.reason,
        },
      );
    });
    return noteId;
  }

  Future<String> saveReturn(ReturnInput input) async {
    if (input.quantityMilli <= 0) {
      throw const ValidationFailure(
        'Return quantity must be greater than zero',
      );
    }
    if (input.unitPricePaise <= 0) {
      throw const ValidationFailure('Enter the return rate');
    }
    if (input.type != ReturnType.saleReturn &&
        input.type != ReturnType.purchaseReturn) {
      throw const ValidationFailure('Choose a return type');
    }
    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(input.productId))).getSingleOrNull();
    if (product == null) {
      throw const ValidationFailure('Choose a product');
    }

    final identity = services.identity;
    final now = DateTime.now();
    final returnId = Ids.returnDoc();
    final itemId = Ids.newId('rti');
    final lineTotal = (input.quantityMilli * input.unitPricePaise / 1000)
        .round();
    final isSale = input.type == ReturnType.saleReturn;

    await db.transaction(() async {
      final code = Ids.deviceCodeFromName(identity.deviceCode);
      final sequence = await db.nextSequence(
        key: 'return:$code:${now.year}',
        prefix: isSale ? 'SRN' : 'PRN',
      );
      final number =
          '${isSale ? 'SRN' : 'PRN'}-${now.year}-$code-'
          '${sequence.toString().padLeft(6, '0')}';

      await db
          .into(db.returns)
          .insert(
            ReturnsCompanion.insert(
              id: returnId,
              shopId: Value(identity.shopId),
              returnNumber: number,
              type: Value(input.type),
              partyId: Value(input.partyId),
              partyName: Value(input.partyName),
              originalDocumentNumber: Value(input.originalDocumentNumber),
              reason: Value(input.reason),
              amountPaise: Value(lineTotal),
              refundMethod: const Value('credit'),
              stockAction: Value(input.restock ? 'restock' : 'discard'),
              status: const Value(DocumentStatus.finalized),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              finalizedAt: Value(now),
              deviceId: Value(identity.deviceId),
            ),
          );
      await db
          .into(db.returnItems)
          .insert(
            ReturnItemsCompanion.insert(
              id: itemId,
              shopId: Value(identity.shopId),
              returnId: returnId,
              productId: product.id,
              productName: product.name,
              quantityMilli: input.quantityMilli,
              unitPricePaise: input.unitPricePaise,
              taxRateBps: Value(product.gstRateBps),
              lineTotalPaise: Value(lineTotal),
              createdAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );

      // Stock effect goes through the movement ledger.
      if (isSale && input.restock) {
        await _catalog.recordStockMovement(
          productId: product.id,
          storeId: input.storeId,
          godownId: input.godownId,
          type: MovementType.customerReturn,
          deltaMilli: input.quantityMilli,
          referenceType: 'return',
          referenceId: returnId,
          note: 'Sales return $number',
        );
      } else if (!isSale) {
        await _catalog.recordStockMovement(
          productId: product.id,
          storeId: input.storeId,
          godownId: input.godownId,
          type: MovementType.supplierReturn,
          deltaMilli: -input.quantityMilli,
          referenceType: 'return',
          referenceId: returnId,
          note: 'Purchase return $number',
        );
      }

      final row = await (db.select(
        db.returns,
      )..where((t) => t.id.equals(returnId))).getSingle();
      final item = await (db.select(
        db.returnItems,
      )..where((t) => t.id.equals(itemId))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'return',
        collection: 'returns',
        entityId: returnId,
        payload: Json.toCloud(row.toJson()),
        baseVersion: 0,
        priority: 50,
      );
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'return_item',
        collection: 'return_items',
        entityId: itemId,
        payload: Json.toCloud(item.toJson()),
        baseVersion: 0,
        priority: 51,
      );
      await audit.write(
        action: 'return_recorded',
        entityType: 'return',
        entityId: returnId,
        after: {
          'number': number,
          'type': input.type,
          'amount_paise': lineTotal,
          'reason': input.reason,
        },
      );
    });
    return returnId;
  }
}

final returnsRepositoryProvider = Provider<ReturnsRepository>(
  (ref) => ReturnsRepository(ref.watch(servicesProvider)),
);

final returnsStreamProvider = StreamProvider<List<ReturnRow>>(
  (ref) => ref.watch(returnsRepositoryProvider).watchReturns(),
);
