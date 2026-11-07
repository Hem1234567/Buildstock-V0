import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/audit/audit_writer.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';
import 'package:buildstock/core/sync/local_mirror.dart';
import 'package:buildstock/core/sync/sync_backend.dart';

import 'package:buildstock/features/sales/domain/invoice_calculator.dart';

class SaleInput {
  const SaleInput({
    required this.lines,
    this.documentType = DocumentType.invoice,
    this.saleType = SaleType.retail,
    this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.customerGstin = '',
    this.customerState = '',
    this.invoiceDiscountPaise = 0,
    this.isGst = true,
    this.interState = false,
    this.amountPaidPaise = 0,
    this.paymentMethod = PaymentMethods.cash,
    this.notes = '',
    this.storeId,
    this.godownId,
    this.date,
    this.validDays = 15,
  });

  final List<InvoiceLine> lines;
  final String documentType;
  final String saleType;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String customerGstin;
  final String customerState;
  final int invoiceDiscountPaise;
  final bool isGst;
  final bool interState;
  final int amountPaidPaise;
  final String paymentMethod;
  final String notes;
  final String? storeId;
  final String? godownId;
  final DateTime? date;

  /// Validity of an estimate or quotation, in days.
  final int validDays;
}

class SaleResult {
  const SaleResult({
    required this.saleId,
    required this.invoiceNumber,
    required this.totals,
  });

  final String saleId;
  final String invoiceNumber;
  final InvoiceTotals totals;
}

class SalesRepository {
  SalesRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;
  AuditWriter get audit => AuditWriter(services);

  Future<BusinessProfileRow?> businessProfile() =>
      db.select(db.businessProfiles).getSingleOrNull();

  // ------------------------------------------------------------------ reads

  Stream<List<SaleRow>> watchDocuments({
    String? documentType,
    String? status,
    String query = '',
    DateTime? from,
    DateTime? to,
  }) {
    final statement = db.select(db.sales);
    if (documentType != null) {
      statement.where((t) => t.documentType.equals(documentType));
    }
    if (status != null) {
      statement.where((t) => t.documentStatus.equals(status));
    }
    if (from != null) {
      statement.where(
        (t) => t.invoiceDate.isBiggerOrEqualValue(AppDate.startOfDay(from)),
      );
    }
    if (to != null) {
      statement.where(
        (t) => t.invoiceDate.isSmallerOrEqualValue(AppDate.endOfDay(to)),
      );
    }
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where(
        (t) =>
            t.invoiceNumber.like(pattern) |
            t.customerId.like(pattern) |
            t.notes.like(pattern),
      );
    }
    statement.orderBy([(t) => OrderingTerm.desc(t.invoiceDate)]);
    return statement.watch();
  }

  Stream<List<SaleRow>> watchRecentInvoices({int limit = 5}) {
    final statement = db.select(db.sales)
      ..where((t) => t.documentType.equals(DocumentType.invoice))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return statement.watch();
  }

  Future<SaleRow?> saleById(String id) =>
      (db.select(db.sales)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<SaleItemRow>> itemsForSale(String saleId) {
    return (db.select(db.saleItems)
          ..where((t) => t.saleId.equals(saleId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<SaleRow?> saleByNumber(String invoiceNumber) {
    return (db.select(db.sales)
          ..where((t) => t.invoiceNumber.equals(invoiceNumber.trim())))
        .getSingleOrNull();
  }

  Future<List<PaymentRow>> paymentsForInvoice(String saleId) {
    return (db.select(db.payments)
          ..where((t) => t.invoiceId.equals(saleId))
          ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
        .get();
  }

  Future<int> paidForInvoice(String saleId) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_paise), 0) AS paid FROM payments '
          'WHERE invoice_id = ? AND direction = ?',
          variables: [
            Variable(saleId),
            const Variable(PaymentDirection.incoming),
          ],
        )
        .getSingle();
    return row.read<int>('paid');
  }

  // ---------------------------------------------------------------- writes

  Future<SaleResult> finalizeSale(SaleInput input) async {
    if (input.lines.isEmpty) {
      throw const ValidationFailure('Add at least one product to the invoice');
    }
    final profile = await businessProfile();
    if (profile == null || profile.name.trim().isEmpty) {
      throw const AppFailure(
        FailureCode.validation,
        'Set up the business profile before creating an invoice',
      );
    }
    final totals = InvoiceCalculator.compute(
      lines: input.lines,
      invoiceDiscountPaise: input.invoiceDiscountPaise,
      isGst: input.isGst,
      interState: input.interState,
      amountPaidPaise: input.amountPaidPaise,
    );
    final identity = services.identity;
    final now = DateTime.now();
    final saleId = Ids.sale();
    final date = input.date ?? now;

    String invoiceNumber = '';
    await db.transaction(() async {
      await _assertStockAvailable(input.lines, input.storeId, input.godownId);
      final sequence = await db.nextSequence(
        key: InvoiceNumber.sequenceKey(
          documentType: input.documentType,
          deviceCode: identity.deviceCode,
          date: date,
        ),
        prefix: profile.invoicePrefix,
      );
      invoiceNumber = InvoiceNumber.build(
        prefix: profile.invoicePrefix,
        date: date,
        deviceCode: identity.deviceCode,
        sequence: sequence,
      );

      final buyer = await _buyerSnapshot(input);
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              shopId: Value(identity.shopId),
              invoiceNumber: invoiceNumber,
              documentType: Value(input.documentType),
              documentStatus: const Value(DocumentStatus.finalized),
              saleType: Value(input.saleType),
              storeId: Value(input.storeId),
              godownId: Value(input.godownId),
              deviceId: Value(identity.deviceId),
              deviceCode: Value(identity.deviceCode),
              customerId: Value(input.customerId),
              invoiceDate: date,
              invoiceTime: Value(AppDate.time(now)),
              sellerSnapshotJson: Value(jsonEncode(_sellerSnapshot(profile))),
              buyerSnapshotJson: Value(jsonEncode(buyer)),
              subtotalPaise: Value(totals.subtotalPaise),
              discountPaise: Value(totals.discountPaise),
              taxableAmountPaise: Value(totals.taxableAmountPaise),
              cgstPaise: Value(totals.cgstPaise),
              sgstPaise: Value(totals.sgstPaise),
              igstPaise: Value(totals.igstPaise),
              roundOffPaise: Value(totals.roundOffPaise),
              grandTotalPaise: Value(totals.grandTotalPaise),
              amountPaidPaise: Value(totals.amountPaidPaise),
              balanceDuePaise: Value(totals.balanceDuePaise),
              paymentMethod: Value(input.paymentMethod),
              notes: Value(input.notes),
              isGst: Value(input.isGst),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              updatedAt: now,
              finalizedAt: Value(now),
              version: const Value(1),
            ),
          );

      await _insertItems(saleId, totals, identity.deviceId, now);

      for (final line in input.lines) {
        if (line.productId == null) continue;
        final parts = await _allocateStock(line, input.storeId, input.godownId);
        for (final part in parts) {
          await _applyStock(
            line: part.line,
            storeId: part.storeId,
            godownId: part.godownId,
            referenceId: saleId,
            referenceType: 'sale',
            occurredAt: date,
          );
        }
      }

      if (totals.amountPaidPaise > 0) {
        await _insertPayment(
          saleId: saleId,
          invoiceNumber: invoiceNumber,
          amounts: totals.amountPaidPaise,
          method: input.paymentMethod,
          partyType: input.customerId == null
              ? PartyType.other
              : PartyType.customer,
          partyId: input.customerId,
          partyName: buyer['name'] as String? ?? '',
          paidAt: date,
          idempotencyKey: 'invoice-initial:$saleId',
        );
      }

      final sale = await saleById(saleId);
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'sale',
        collection: 'sales',
        entityId: saleId,
        payload: Json.toCloud(sale!.toJson()),
        baseVersion: 0,
        priority: 60,
      );
      await audit.write(
        action: 'invoice_finalized',
        entityType: 'sale',
        entityId: saleId,
        after: {
          'invoice_number': invoiceNumber,
          'grand_total_paise': totals.grandTotalPaise,
        },
      );
    });

    return SaleResult(
      saleId: saleId,
      invoiceNumber: invoiceNumber,
      totals: totals,
    );
  }

  /// Saves an estimate/quotation. This never touches inventory.
  Future<SaleResult> saveEstimate(SaleInput input) async {
    final profile = await businessProfile();
    if (profile == null) {
      throw const AppFailure(
        FailureCode.validation,
        'Set up the business profile first',
      );
    }
    final totals = InvoiceCalculator.compute(
      lines: input.lines,
      invoiceDiscountPaise: input.invoiceDiscountPaise,
      isGst: input.isGst,
      interState: input.interState,
    );
    final identity = services.identity;
    final now = DateTime.now();
    final saleId = Ids.sale();
    final date = input.date ?? now;
    var number = '';
    await db.transaction(() async {
      final documentType = input.documentType == DocumentType.quotation
          ? DocumentType.quotation
          : DocumentType.estimate;
      final sequence = await db.nextSequence(
        key: InvoiceNumber.sequenceKey(
          documentType: documentType,
          deviceCode: identity.deviceCode,
          date: date,
        ),
        prefix: profile.invoicePrefix,
      );
      // A separate prefix keeps estimate and quotation numbers from ever
      // matching a tax invoice number.
      number = InvoiceNumber.build(
        prefix:
            '${profile.invoicePrefix}-'
            '${documentType == DocumentType.quotation ? 'QTN' : 'EST'}',
        date: date,
        deviceCode: identity.deviceCode,
        sequence: sequence,
      );
      final buyer = await _buyerSnapshot(input);
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              shopId: Value(identity.shopId),
              invoiceNumber: number,
              documentType: Value(
                input.documentType == DocumentType.quotation
                    ? DocumentType.quotation
                    : DocumentType.estimate,
              ),
              documentStatus: const Value(DocumentStatus.finalized),
              saleType: Value(input.saleType),
              deviceId: Value(identity.deviceId),
              deviceCode: Value(identity.deviceCode),
              customerId: Value(input.customerId),
              invoiceDate: date,
              invoiceTime: Value(AppDate.time(now)),
              sellerSnapshotJson: Value(jsonEncode(_sellerSnapshot(profile))),
              buyerSnapshotJson: Value(jsonEncode(buyer)),
              subtotalPaise: Value(totals.subtotalPaise),
              discountPaise: Value(totals.discountPaise),
              taxableAmountPaise: Value(totals.taxableAmountPaise),
              cgstPaise: Value(totals.cgstPaise),
              sgstPaise: Value(totals.sgstPaise),
              igstPaise: Value(totals.igstPaise),
              roundOffPaise: Value(totals.roundOffPaise),
              grandTotalPaise: Value(totals.grandTotalPaise),
              paymentMethod: const Value(PaymentMethods.credit),
              notes: Value(input.notes),
              isGst: Value(input.isGst),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              updatedAt: now,
              finalizedAt: Value(now),
              validUntil: Value(now.add(Duration(days: input.validDays))),
              version: const Value(1),
            ),
          );
      await _insertItems(saleId, totals, identity.deviceId, now);
      final sale = await saleById(saleId);
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'estimate',
        collection: 'sales',
        entityId: saleId,
        payload: Json.toCloud(sale!.toJson()),
        baseVersion: 0,
        priority: 60,
      );
      await audit.write(
        action: 'estimate_created',
        entityType: 'sale',
        entityId: saleId,
        after: {'number': number},
      );
    });
    return SaleResult(saleId: saleId, invoiceNumber: number, totals: totals);
  }

  /// Turns an estimate or quotation into a tax invoice. Stock is deducted
  /// from [storeId]/[godownId] (or automatically when both are null) and the
  /// source document is marked converted and linked to the new invoice.
  Future<SaleResult> convertToInvoice(
    String sourceId, {
    String? storeId,
    String? godownId,
    int amountPaidPaise = 0,
    String paymentMethod = PaymentMethods.cash,
  }) async {
    final source = await saleById(sourceId);
    if (source == null) {
      throw const AppFailure(FailureCode.notFound, 'Document not found');
    }
    if (source.documentType == DocumentType.invoice) {
      throw const ValidationFailure('This document is already an invoice');
    }
    if (source.documentStatus != DocumentStatus.finalized) {
      throw const ValidationFailure('Only an active estimate can be converted');
    }
    if (source.convertedInvoiceId != null) {
      throw const ValidationFailure('This document was already converted');
    }
    final items = await itemsForSale(sourceId);
    if (items.isEmpty) {
      throw const ValidationFailure('This document has no items');
    }
    Map<String, dynamic> buyer = const {};
    try {
      final decoded = jsonDecode(source.buyerSnapshotJson);
      if (decoded is Map<String, dynamic>) buyer = decoded;
    } catch (_) {}
    final lineDiscounts = items.fold<int>(
      0,
      (sum, item) => sum + item.discountPaise,
    );
    final invoiceDiscount = source.discountPaise > lineDiscounts
        ? source.discountPaise - lineDiscounts
        : 0;
    final interState =
        (source.igstPaise > 0) &&
        source.cgstPaise == 0 &&
        source.sgstPaise == 0;

    return db.transaction(() async {
      final result = await finalizeSale(
        SaleInput(
          lines: [
            for (final item in items)
              InvoiceLine(
                productId: item.productId,
                name: item.productName,
                sku: item.sku,
                hsnCode: item.hsnCode,
                unit: item.unit,
                quantityMilli: item.quantityMilli,
                unitPricePaise: item.unitPricePaise,
                discountPaise: item.discountPaise,
                taxRateBps: item.taxRateBps,
              ),
          ],
          saleType: source.saleType,
          customerId: source.customerId,
          customerName: (buyer['name'] as String?) ?? '',
          customerPhone: (buyer['phone'] as String?) ?? '',
          customerAddress: (buyer['address'] as String?) ?? '',
          customerGstin: (buyer['gstin'] as String?) ?? '',
          customerState: (buyer['state'] as String?) ?? '',
          invoiceDiscountPaise: invoiceDiscount,
          isGst: source.isGst,
          interState: interState,
          amountPaidPaise: amountPaidPaise,
          paymentMethod: paymentMethod,
          notes: source.notes,
          storeId: storeId,
          godownId: godownId,
        ),
      );
      final now = DateTime.now();
      await (db.update(db.sales)..where((t) => t.id.equals(sourceId))).write(
        SalesCompanion(
          convertedInvoiceId: Value(result.saleId),
          documentStatus: const Value(DocumentStatus.converted),
          notes: Value(
            '${source.notes}${source.notes.isEmpty ? '' : '\n'}'
            'Converted to invoice ${result.invoiceNumber}',
          ),
          updatedAt: Value(now),
          version: Value(source.version + 1),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      final updated = await saleById(sourceId);
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'estimate',
        collection: 'sales',
        entityId: sourceId,
        payload: Json.toCloud(updated!.toJson()),
        baseVersion: source.version,
        priority: 60,
      );
      await audit.write(
        action: 'estimate_converted',
        entityType: 'sale',
        entityId: sourceId,
        note: 'Converted to ${result.invoiceNumber}',
      );
      return result;
    });
  }

  Future<void> cancelInvoice(String saleId, String reason) async {
    final sale = await saleById(saleId);
    if (sale == null) {
      throw const AppFailure(FailureCode.notFound, 'Invoice not found');
    }
    if (sale.documentStatus != DocumentStatus.finalized) {
      throw const AppFailure(
        FailureCode.invoiceImmutable,
        'Only finalized invoices can be cancelled',
      );
    }
    final items = await itemsForSale(saleId);
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.sales)..where((t) => t.id.equals(saleId))).write(
        SalesCompanion(
          documentStatus: const Value(DocumentStatus.cancelled),
          cancelledAt: Value(now),
          cancelReason: Value(reason),
          updatedAt: Value(now),
          version: Value(sale.version + 1),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      // Cancellation returns everything to the exact location it left from.
      final movements =
          await (db.select(db.stockMovements)..where(
                (t) =>
                    t.referenceId.equals(saleId) &
                    t.referenceType.equals('sale'),
              ))
              .get();
      final names = {
        for (final item in items)
          if (item.productId != null) item.productId!: item.productName,
      };
      for (final movement in movements) {
        if (movement.quantityMilli >= 0) continue;
        await _applyStock(
          line: InvoiceLine(
            productId: movement.productId,
            name: names[movement.productId] ?? 'Product',
            quantityMilli: -movement.quantityMilli,
            unitPricePaise: movement.unitCostPaise,
          ),
          storeId: movement.storeId,
          godownId: movement.godownId,
          referenceId: saleId,
          referenceType: 'sale_cancellation',
          occurredAt: now,
          inbound: true,
        );
      }
      // Estimates and quotations never touched stock, so there is nothing to
      // put back. Old invoices without movement records fall back to the items.
      final legacyItems =
          movements.isNotEmpty || sale.documentType != DocumentType.invoice
          ? const <SaleItemRow>[]
          : items;
      for (final item in legacyItems) {
        if (item.productId == null) continue;
        await db.transaction(() async {
          final line = InvoiceLine(
            productId: item.productId,
            name: item.productName,
            quantityMilli: item.quantityMilli,
            unitPricePaise: item.unitPricePaise,
            taxRateBps: item.taxRateBps,
          );
          await _applyStock(
            line: line,
            storeId: sale.storeId,
            godownId: sale.godownId,
            referenceId: saleId,
            referenceType: 'sale_cancellation',
            occurredAt: now,
            inbound: true,
          );
        });
      }
      final updated = await saleById(saleId);
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'sale',
        collection: 'sales',
        entityId: saleId,
        payload: Json.toCloud(updated!.toJson()),
        baseVersion: sale.version,
        priority: 60,
      );
      await audit.write(
        action: 'invoice_cancelled',
        entityType: 'sale',
        entityId: saleId,
        before: sale.toJson(),
        note: reason,
      );
    });
  }

  Future<String> recordPayment({
    required String partyType,
    String? partyId,
    required String partyName,
    required int amountPaise,
    required String method,
    String? invoiceId,
    String? purchaseId,
    String reference = '',
    String notes = '',
    DateTime? paidAt,
    String? idempotencyKey,
  }) async {
    if (amountPaise <= 0) {
      throw const ValidationFailure('Payment amount must be greater than zero');
    }
    final identity = services.identity;
    final now = DateTime.now();
    final paymentId = Ids.payment();
    final key =
        idempotencyKey ??
        Ids.paymentIdempotencyKey(
          deviceId: identity.deviceId,
          clientReference: paymentId,
        );
    await db.transaction(() async {
      await _insertPaymentRaw(
        paymentId: paymentId,
        partyType: partyType,
        partyId: partyId,
        partyName: partyName,
        amountPaise: amountPaise,
        method: method,
        invoiceId: invoiceId,
        purchaseId: purchaseId,
        reference: reference,
        notes: notes,
        paidAt: paidAt ?? now,
        idempotencyKey: key,
      );
      await audit.write(
        action: 'payment_recorded',
        entityType: 'payment',
        entityId: paymentId,
        after: {
          'amount_paise': amountPaise,
          'party_type': partyType,
          'invoice_id': invoiceId,
        },
      );
    });
    return paymentId;
  }

  /// Fetches an invoice that is not available locally, using its bill number.
  /// Returns the local sale ID once the structured document and items have been
  /// mirrored into SQLite.
  Future<String?> fetchInvoiceFromCloud(String invoiceNumber) async {
    final firestore = services.runtime.firestore;
    if (firestore == null) return null;
    final shopId = services.identity.shopId;
    if (shopId == 'local') return null;

    final snapshot = await firestore
        .collection('shops')
        .doc(shopId)
        .collection('sales')
        .where('invoice_number', isEqualTo: invoiceNumber.trim())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    final saleId = doc.id;

    final items = await firestore
        .collection('shops')
        .doc(shopId)
        .collection('sale_items')
        .where('sale_id', isEqualTo: saleId)
        .get();

    final mirror = LocalMirror(db);
    await mirror.apply(
      'sales',
      RemoteDocument(
        id: doc.id,
        data: doc.data(),
        version: (doc.data()['version'] as num?)?.toInt() ?? 0,
      ),
    );
    for (final item in items.docs) {
      await mirror.apply(
        'sale_items',
        RemoteDocument(
          id: item.id,
          data: item.data(),
          version: (item.data()['version'] as num?)?.toInt() ?? 1,
        ),
      );
    }
    return saleId;
  }

  // ----------------------------------------------------------------- helpers

  Future<void> _assertStockAvailable(
    List<InvoiceLine> lines,
    String? storeId,
    String? godownId,
  ) async {
    for (final line in lines) {
      if (line.productId == null) continue;
      final rows =
          await (db.select(db.inventories)..where(
                (t) =>
                    t.productId.equals(line.productId!) &
                    (storeId == null
                        ? const Constant<bool>(true)
                        : t.storeId.equals(storeId)) &
                    (godownId == null
                        ? const Constant<bool>(true)
                        : t.godownId.equals(godownId)),
              ))
              .get();
      final available = rows.fold<int>(
        0,
        (sum, row) => sum + row.quantityMilli,
      );
      if (available < line.quantityMilli) {
        throw AppFailure(
          FailureCode.stock,
          'Insufficient stock for ${line.name}. Available '
          '${(available / 1000).toStringAsFixed(3)}, required '
          '${(line.quantityMilli / 1000).toStringAsFixed(3)}.',
        );
      }
    }
  }

  /// Splits a line across stock locations. With an explicit store/godown the
  /// whole quantity comes from there; otherwise the largest balances are used
  /// first until the line is covered.
  Future<List<_StockPart>> _allocateStock(
    InvoiceLine line,
    String? storeId,
    String? godownId,
  ) async {
    if (storeId != null && godownId != null) {
      return [_StockPart(line, storeId, godownId)];
    }
    final rows =
        await (db.select(db.inventories)
              ..where(
                (t) =>
                    t.productId.equals(line.productId!) &
                    t.quantityMilli.isBiggerThanValue(0) &
                    (storeId == null
                        ? const Constant<bool>(true)
                        : t.storeId.equals(storeId)) &
                    (godownId == null
                        ? const Constant<bool>(true)
                        : t.godownId.equals(godownId)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.quantityMilli)]))
            .get();
    var remaining = line.quantityMilli;
    final parts = <_StockPart>[];
    for (final row in rows) {
      if (remaining <= 0) break;
      final take = row.quantityMilli < remaining
          ? row.quantityMilli
          : remaining;
      parts.add(
        _StockPart(
          InvoiceLine(
            productId: line.productId,
            name: line.name,
            sku: line.sku,
            hsnCode: line.hsnCode,
            unit: line.unit,
            quantityMilli: take,
            unitPricePaise: line.unitPricePaise,
            taxRateBps: line.taxRateBps,
          ),
          row.storeId,
          row.godownId,
        ),
      );
      remaining -= take;
    }
    if (remaining > 0) {
      throw AppFailure(
        FailureCode.stock,
        'Insufficient stock for ${line.name}',
      );
    }
    return parts;
  }

  Future<void> _applyStock({
    required InvoiceLine line,
    required String? storeId,
    required String? godownId,
    required String referenceId,
    required String referenceType,
    required DateTime occurredAt,
    bool inbound = false,
  }) async {
    final productId = line.productId;
    if (productId == null) return;
    final identity = services.identity;
    final existing =
        await (db.select(db.inventories)..where(
              (t) =>
                  t.productId.equals(productId) &
                  t.storeId.equalsNullable(storeId) &
                  t.godownId.equalsNullable(godownId),
            ))
            .getSingleOrNull();
    final delta = inbound ? line.quantityMilli : -line.quantityMilli;
    final newQuantity = (existing?.quantityMilli ?? 0) + delta;
    if (newQuantity < 0) {
      throw AppFailure(
        FailureCode.stock,
        'Insufficient stock for ${line.name}',
      );
    }
    final inventoryId = Ids.inventoryKey(
      productId: productId,
      storeId: storeId,
      godownId: godownId,
    );
    final inventoryVersion = (existing?.version ?? 0) + 1;
    await db
        .into(db.inventories)
        .insertOnConflictUpdate(
          InventoriesCompanion.insert(
            id: inventoryId,
            shopId: Value(identity.shopId),
            productId: productId,
            storeId: Value(storeId),
            godownId: Value(godownId),
            quantityMilli: Value(newQuantity),
            updatedAt: occurredAt,
            version: Value(inventoryVersion),
            deviceId: Value(identity.deviceId),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );

    final movementId = Ids.stockMovement();
    await db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: movementId,
            shopId: Value(identity.shopId),
            productId: productId,
            storeId: Value(storeId),
            godownId: Value(godownId),
            type: inbound ? MovementType.customerReturn : MovementType.saleOut,
            quantityMilli: delta,
            unitCostPaise: Value(line.unitPricePaise),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            occurredAt: occurredAt,
            createdBy: Value(identity.displayName ?? 'Local user'),
            deviceId: Value(identity.deviceId),
            createdAt: occurredAt,
          ),
        );

    final movement = await (db.select(
      db.stockMovements,
    )..where((t) => t.id.equals(movementId))).getSingle();
    final inventory = await (db.select(
      db.inventories,
    )..where((t) => t.id.equals(inventoryId))).getSingle();
    await services.outbox.enqueue(
      shopId: identity.shopId,
      deviceId: identity.deviceId,
      userId: identity.userId,
      entityType: 'stock_movement',
      collection: 'stock_movements',
      entityId: movementId,
      payload: Json.toCloud(movement.toJson()),
      baseVersion: 0,
      priority: 50,
    );
    await services.outbox.enqueue(
      shopId: identity.shopId,
      deviceId: identity.deviceId,
      userId: identity.userId,
      entityType: 'inventory',
      collection: 'inventory',
      entityId: inventoryId,
      payload: Json.toCloud(inventory.toJson()),
      baseVersion: existing?.version ?? 0,
      priority: 40,
    );
  }

  Future<void> _insertItems(
    String saleId,
    InvoiceTotals totals,
    String deviceId,
    DateTime now,
  ) async {
    var order = 0;
    for (final line in totals.lines) {
      final itemId = Ids.saleItem();
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              id: itemId,
              shopId: Value(services.identity.shopId),
              saleId: saleId,
              productId: Value(line.input.productId),
              productName: line.input.name,
              sku: Value(line.input.sku),
              hsnCode: Value(line.input.hsnCode),
              unit: Value(line.input.unit),
              quantityMilli: line.input.quantityMilli,
              unitPricePaise: line.input.unitPricePaise,
              discountPaise: Value(line.discountPaise),
              taxRateBps: Value(line.input.taxRateBps),
              taxAmountPaise: Value(line.taxPaise),
              lineTotalPaise: Value(line.totalPaise),
              sortOrder: Value(order++),
              createdAt: now,
              deviceId: Value(deviceId),
            ),
          );
      final row = await (db.select(
        db.saleItems,
      )..where((t) => t.id.equals(itemId))).getSingle();
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'sale_item',
        collection: 'sale_items',
        entityId: itemId,
        payload: Json.toCloud(row.toJson()),
        baseVersion: 0,
        priority: 70,
      );
    }
  }

  Future<void> _insertPayment({
    required String saleId,
    required String invoiceNumber,
    required int amounts,
    required String method,
    required String partyType,
    required String? partyId,
    required String partyName,
    required DateTime paidAt,
    required String idempotencyKey,
  }) async {
    await _insertPaymentRaw(
      paymentId: Ids.payment(),
      partyType: partyType,
      partyId: partyId,
      partyName: partyName,
      amountPaise: amounts,
      method: method,
      invoiceId: saleId,
      reference: invoiceNumber,
      notes: 'Initial payment on $invoiceNumber',
      paidAt: paidAt,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> _insertPaymentRaw({
    required String paymentId,
    required String partyType,
    required String? partyId,
    required String partyName,
    required int amountPaise,
    required String method,
    String? invoiceId,
    String? purchaseId,
    String reference = '',
    String notes = '',
    required DateTime paidAt,
    required String idempotencyKey,
  }) async {
    final identity = services.identity;
    final now = DateTime.now();
    final direction = partyType == PartyType.supplier
        ? PaymentDirection.outgoing
        : PaymentDirection.incoming;
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: paymentId,
            shopId: Value(identity.shopId),
            partyType: Value(partyType),
            partyId: Value(partyId),
            partyName: Value(partyName),
            direction: Value(direction),
            amountPaise: amountPaise,
            method: Value(method),
            reference: Value(reference),
            paidAt: paidAt,
            invoiceId: Value(invoiceId),
            purchaseId: Value(purchaseId),
            notes: Value(notes),
            idempotencyKey: idempotencyKey,
            createdBy: Value(identity.displayName ?? 'Local user'),
            createdAt: now,
            deviceId: Value(identity.deviceId),
          ),
        );
    final row = await (db.select(
      db.payments,
    )..where((t) => t.id.equals(paymentId))).getSingle();
    await services.outbox.enqueue(
      shopId: identity.shopId,
      deviceId: identity.deviceId,
      userId: identity.userId,
      entityType: 'payment',
      collection: 'payments',
      entityId: paymentId,
      payload: Json.toCloud(row.toJson()),
      baseVersion: 0,
      priority: 80,
    );
  }

  Future<Map<String, dynamic>> _buyerSnapshot(SaleInput input) async {
    if (input.customerId != null) {
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(input.customerId!))).getSingleOrNull();
      if (customer != null) {
        return {
          'customer_id': customer.id,
          'name': customer.name,
          'business_name': customer.businessName,
          'phone': customer.phone,
          'address': [
            customer.billingAddress,
            customer.city,
            customer.state,
            customer.pinCode,
          ].where((part) => part.trim().isNotEmpty).join(', '),
          'gstin': customer.gstin,
          'state': customer.state,
          'state_code': _stateCode(customer.state),
        };
      }
    }
    return {
      'customer_id': null,
      'name': input.customerName.trim().isEmpty
          ? 'Walk-in Customer'
          : input.customerName.trim(),
      'business_name': '',
      'phone': input.customerPhone,
      'address': input.customerAddress,
      'gstin': input.customerGstin,
      'state': input.customerState,
      'state_code': _stateCode(input.customerState),
    };
  }

  Map<String, dynamic> _sellerSnapshot(BusinessProfileRow profile) => {
    'name': profile.name,
    'owner_name': profile.ownerName,
    'phones': [
      profile.phone,
      profile.altPhone,
    ].where((value) => value.trim().isNotEmpty).toList(),
    'description': profile.description,
    'address': [
      profile.address,
      profile.area,
      profile.city,
      profile.state,
      profile.pinCode,
    ].where((part) => part.trim().isNotEmpty).join(', '),
    'gstin': profile.gstin,
    'pan': profile.pan,
    'state_code': profile.stateCode,
    'upi_id': profile.upiId,
    'upi_payee_name': profile.upiPayeeName,
    'logo_ref': profile.logoRef,
    'signature_ref': profile.signatureRef,
    'stamp_ref': profile.stampRef,
  };

  String _stateCode(String state) {
    const codes = {
      'Tamil Nadu': '33',
      'Karnataka': '29',
      'Kerala': '32',
      'Andhra Pradesh': '37',
      'Telangana': '36',
      'Puducherry': '34',
      'Maharashtra': '27',
      'Delhi': '07',
    };
    return codes[state] ?? '33';
  }
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(servicesProvider)),
);

final recentInvoicesProvider = StreamProvider<List<SaleRow>>(
  (ref) => ref.watch(salesRepositoryProvider).watchRecentInvoices(),
);

final invoiceListProvider = StreamProvider.family<List<SaleRow>, String>((
  ref,
  query,
) {
  return ref
      .watch(salesRepositoryProvider)
      .watchDocuments(documentType: DocumentType.invoice, query: query);
});

/// Every sales document (invoices, estimates and quotations).
final documentListProvider = StreamProvider.family<List<SaleRow>, String>((
  ref,
  query,
) {
  return ref.watch(salesRepositoryProvider).watchDocuments(query: query);
});

final saleProvider = FutureProvider.family<SaleRow?, String>((ref, id) {
  return ref.watch(salesRepositoryProvider).saleById(id);
});

final saleItemsProvider = FutureProvider.family<List<SaleItemRow>, String>((
  ref,
  saleId,
) {
  return ref.watch(salesRepositoryProvider).itemsForSale(saleId);
});

final invoicePaidProvider = FutureProvider.family<int, String>((ref, saleId) {
  return ref.watch(salesRepositoryProvider).paidForInvoice(saleId);
});

final invoicePaymentsProvider = FutureProvider.family<List<PaymentRow>, String>(
  (ref, saleId) {
    return ref.watch(salesRepositoryProvider).paymentsForInvoice(saleId);
  },
);

class _StockPart {
  const _StockPart(this.line, this.storeId, this.godownId);

  final InvoiceLine line;
  final String? storeId;
  final String? godownId;
}
