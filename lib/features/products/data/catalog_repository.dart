import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/audit/audit_writer.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';

class ProductInput {
  const ProductInput({
    required this.name,
    this.sku = '',
    this.barcode = '',
    this.categoryId,
    this.brandId,
    this.unitId,
    this.description = '',
    this.hsnCode = '',
    this.gstRateBps = 0,
    this.purchasePricePaise = 0,
    this.retailPricePaise = 0,
    this.wholesalePricePaise = 0,
    this.minStockMilli = 0,
    this.imageRef,
    this.active = true,
  });

  final String name;
  final String sku;
  final String barcode;
  final String? categoryId;
  final String? brandId;
  final String? unitId;
  final String description;
  final String hsnCode;
  final int gstRateBps;
  final int purchasePricePaise;
  final int retailPricePaise;
  final int wholesalePricePaise;
  final int minStockMilli;
  final String? imageRef;
  final bool active;
}

class InventoryView {
  const InventoryView({
    required this.inventory,
    required this.product,
    this.storeName,
    this.godownName,
    this.unitSymbol,
  });

  final InventoryRow inventory;
  final ProductRow product;
  final String? storeName;
  final String? godownName;
  final String? unitSymbol;

  String get locationLabel {
    if (godownName != null && godownName!.isNotEmpty) return godownName!;
    if (storeName != null && storeName!.isNotEmpty) return storeName!;
    return 'Main location';
  }
}

class CatalogRepository {
  CatalogRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;
  AuditWriter get audit => AuditWriter(services);

  // ---------------------------------------------------------------- products

  Stream<List<ProductRow>> watchProducts({
    String query = '',
    bool includeArchived = false,
  }) {
    final statement = db.select(db.products);
    if (!includeArchived) {
      statement.where((t) => t.active.equals(true) & t.deletedAt.isNull());
    }
    final term = query.trim();
    if (term.isNotEmpty) {
      final pattern = '%$term%';
      statement.where(
        (t) =>
            t.name.like(pattern) |
            t.sku.like(pattern) |
            t.barcode.like(pattern) |
            t.hsnCode.like(pattern),
      );
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return statement.watch();
  }

  Stream<List<ProductRow>> watchLowStock() {
    final statement = db.select(db.products).join([
      innerJoin(
        db.inventories,
        db.inventories.productId.equalsExp(db.products.id),
      ),
    ]);
    statement.where(
      db.products.active.equals(true) &
          db.products.minStockMilli.isBiggerThanValue(0),
    );
    statement.orderBy([OrderingTerm.asc(db.products.name)]);
    return statement.watch().map((rows) {
      final seen = <String>{};
      final result = <ProductRow>[];
      for (final row in rows) {
        final product = row.readTable(db.products);
        final stock = row.readTable(db.inventories).quantityMilli;
        if (stock <= product.minStockMilli && seen.add(product.id)) {
          result.add(product);
        }
      }
      return result;
    });
  }

  /// Finds an active product by exact barcode or SKU (used by the scanner).
  Future<ProductRow?> productByCode(String code) async {
    final value = code.trim();
    if (value.isEmpty) return null;
    return (db.select(db.products)
          ..where(
            (t) =>
                (t.barcode.equals(value) | t.sku.equals(value)) &
                t.deletedAt.isNull() &
                t.active.equals(true),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<ProductRow?> productById(String id) async {
    return (db.select(
      db.products,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<String> saveProduct(ProductInput input, {String? existingId}) async {
    final name = input.name.trim();
    if (name.isEmpty) {
      throw const ValidationFailure('Product name is required');
    }
    if (input.retailPricePaise < 0 || input.wholesalePricePaise < 0) {
      throw const ValidationFailure('Prices cannot be negative');
    }
    final sku = input.sku.trim();
    if (sku.isNotEmpty) {
      final duplicate =
          await (db.select(db.products)..where(
                (t) => t.sku.equals(sku) & t.id.equals(existingId ?? '').not(),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        throw const ValidationFailure(
          'This SKU is already used by another product',
        );
      }
    }

    final existing = existingId == null ? null : await productById(existingId);
    final id = existing?.id ?? Ids.product();
    final version = (existing?.version ?? 0) + 1;
    final now = DateTime.now();
    final identity = services.identity;

    await db.transaction(() async {
      await db
          .into(db.products)
          .insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              name: name,
              sku: Value(sku),
              barcode: Value(input.barcode.trim()),
              categoryId: Value(input.categoryId),
              brandId: Value(input.brandId),
              unitId: Value(input.unitId),
              description: Value(input.description.trim()),
              hsnCode: Value(input.hsnCode.trim()),
              gstRateBps: Value(input.gstRateBps),
              purchasePricePaise: Value(input.purchasePricePaise),
              retailPricePaise: Value(input.retailPricePaise),
              wholesalePricePaise: Value(input.wholesalePricePaise),
              minStockMilli: Value(input.minStockMilli),
              mainImageRef: Value(input.imageRef),
              active: Value(input.active),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              version: Value(version),
              deviceId: Value(identity.deviceId),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );

      final row = await productById(id);
      if (row == null) {
        throw const AppFailure(FailureCode.database, 'Product write failed');
      }
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'product',
        collection: 'products',
        entityId: id,
        payload: Json.toCloud(row.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 10,
      );
      await audit.write(
        action: existing == null ? 'product_created' : 'product_updated',
        entityType: 'product',
        entityId: id,
        before: existing?.toJson(),
        after: row.toJson(),
      );
    });
    return id;
  }

  Future<void> archiveProduct(String id) async {
    final existing = await productById(id);
    if (existing == null) {
      throw const AppFailure(FailureCode.notFound, 'Product not found');
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.products)..where((t) => t.id.equals(id))).write(
        ProductsCompanion(
          active: const Value(false),
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
          syncStatus: const Value(SyncStatus.pending),
          deviceId: Value(services.identity.deviceId),
        ),
      );
      final row = await productById(id);
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'product',
        collection: 'products',
        entityId: id,
        payload: Json.toCloud(row!.toJson()),
        baseVersion: existing.version,
        priority: 10,
      );
      await audit.write(
        action: 'product_archived',
        entityType: 'product',
        entityId: id,
        before: existing.toJson(),
      );
    });
  }

  // ------------------------------------------------------------ configuration

  Stream<List<CategoryRow>> watchCategories() => (db.select(
    db.categories,
  )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();

  Stream<List<BrandRow>> watchBrands() => (db.select(
    db.brands,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Stream<List<UnitRow>> watchUnits() =>
      (db.select(db.units)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<String> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationFailure('Category name is required');
    }
    final id = Ids.category();
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              shopId: Value(services.identity.shopId),
              name: trimmed,
              createdAt: now,
              updatedAt: now,
              deviceId: Value(services.identity.deviceId),
            ),
          );
      final row = await (db.select(
        db.categories,
      )..where((t) => t.id.equals(id))).getSingle();
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'category',
        collection: 'categories',
        entityId: id,
        payload: Json.toCloud(row.toJson()),
        baseVersion: 0,
        priority: 5,
      );
    });
    return id;
  }

  Future<String> addBrand(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationFailure('Brand name is required');
    }
    final id = Ids.brand();
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.brands)
          .insert(
            BrandsCompanion.insert(
              id: id,
              shopId: Value(services.identity.shopId),
              name: trimmed,
              createdAt: now,
              updatedAt: now,
              deviceId: Value(services.identity.deviceId),
            ),
          );
      final row = await (db.select(
        db.brands,
      )..where((t) => t.id.equals(id))).getSingle();
      await services.outbox.enqueue(
        shopId: services.identity.shopId,
        deviceId: services.identity.deviceId,
        userId: services.identity.userId,
        entityType: 'brand',
        collection: 'brands',
        entityId: id,
        payload: Json.toCloud(row.toJson()),
        baseVersion: 0,
        priority: 5,
      );
    });
    return id;
  }

  // --------------------------------------------------------------- inventory

  Stream<List<InventoryView>> watchInventory({String? storeId}) {
    final query = db.select(db.inventories).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.inventories.productId),
      ),
      leftOuterJoin(db.stores, db.stores.id.equalsExp(db.inventories.storeId)),
      leftOuterJoin(
        db.godowns,
        db.godowns.id.equalsExp(db.inventories.godownId),
      ),
      leftOuterJoin(db.units, db.units.id.equalsExp(db.products.unitId)),
    ]);
    query.where(db.products.active.equals(true));
    if (storeId != null) {
      query.where(db.inventories.storeId.equals(storeId));
    }
    query.orderBy([OrderingTerm.asc(db.products.name)]);
    return query.watch().map(
      (rows) => rows.map((row) {
        final store = row.readTableOrNull(db.stores);
        final godown = row.readTableOrNull(db.godowns);
        final unit = row.readTableOrNull(db.units);
        return InventoryView(
          inventory: row.readTable(db.inventories),
          product: row.readTable(db.products),
          storeName: store?.name,
          godownName: godown?.name,
          unitSymbol: unit?.symbol,
        );
      }).toList(),
    );
  }

  Stream<List<StockMovementRow>> watchMovements({String? productId}) {
    final query = db.select(db.stockMovements)
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
      ..limit(200);
    if (productId != null) {
      query.where((t) => t.productId.equals(productId));
    }
    return query.watch();
  }

  Future<int> stockFor(String productId) async {
    final rows = await (db.select(
      db.inventories,
    )..where((t) => t.productId.equals(productId))).get();
    return rows.fold<int>(0, (sum, row) => sum + row.quantityMilli);
  }

  Future<InventoryRow?> _inventoryRow(
    String productId,
    String? storeId,
    String? godownId,
  ) {
    return (db.select(db.inventories)..where(
          (t) =>
              t.productId.equals(productId) &
              t.storeId.equalsNullable(storeId) &
              t.godownId.equalsNullable(godownId),
        ))
        .getSingleOrNull();
  }

  /// Appends a stock movement and updates the projection. [deltaMilli] is
  /// signed: positive receives stock, negative issues stock.
  Future<void> recordStockMovement({
    required String productId,
    String? storeId,
    String? godownId,
    required String type,
    required int deltaMilli,
    String referenceType = '',
    String referenceId = '',
    String note = '',
    int unitCostPaise = 0,
    bool allowNegative = false,
  }) async {
    if (deltaMilli == 0) return;
    final identity = services.identity;
    final now = DateTime.now();
    await db.transaction(() async {
      final existing = await _inventoryRow(productId, storeId, godownId);
      final newQuantity = (existing?.quantityMilli ?? 0) + deltaMilli;
      if (newQuantity < 0 && !allowNegative) {
        throw const AppFailure(
          FailureCode.stock,
          'Stock cannot go below zero for this operation',
        );
      }
      final inventoryId = Ids.inventoryKey(
        productId: productId,
        storeId: storeId,
        godownId: godownId,
      );
      final version = (existing?.version ?? 0) + 1;
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
              updatedAt: now,
              version: Value(version),
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
              type: type,
              quantityMilli: deltaMilli,
              unitCostPaise: Value(unitCostPaise),
              referenceType: Value(referenceType),
              referenceId: Value(referenceId),
              note: Value(note),
              occurredAt: now,
              createdBy: Value(identity.displayName ?? 'Local user'),
              deviceId: Value(identity.deviceId),
              createdAt: now,
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
        priority: 40,
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
        priority: 30,
      );
    });
  }

  Future<void> adjustStock({
    required String productId,
    String? storeId,
    String? godownId,
    required int deltaMilli,
    required String reason,
    bool isDamage = false,
  }) async {
    final type = deltaMilli >= 0
        ? MovementType.adjustmentIn
        : (isDamage ? MovementType.damage : MovementType.adjustmentOut);
    await recordStockMovement(
      productId: productId,
      storeId: storeId,
      godownId: godownId,
      type: type,
      deltaMilli: deltaMilli,
      note: reason,
      allowNegative: true,
    );
    await audit.write(
      action: 'stock_adjusted',
      entityType: 'product',
      entityId: productId,
      after: {'delta_milli': deltaMilli, 'reason': reason},
    );
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(servicesProvider)),
);

final productsStreamProvider = StreamProvider.family<List<ProductRow>, String>((
  ref,
  query,
) {
  return ref.watch(catalogRepositoryProvider).watchProducts(query: query);
});

final productProvider = FutureProvider.family<ProductRow?, String>((ref, id) {
  return ref.watch(catalogRepositoryProvider).productById(id);
});

final categoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchCategories(),
);

final brandsProvider = StreamProvider<List<BrandRow>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchBrands(),
);

final unitsProvider = StreamProvider<List<UnitRow>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchUnits(),
);

final inventoryStreamProvider = StreamProvider<List<InventoryView>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchInventory(),
);

final lowStockProvider = StreamProvider<List<ProductRow>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchLowStock(),
);
