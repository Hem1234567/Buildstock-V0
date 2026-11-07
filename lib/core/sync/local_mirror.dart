import 'package:drift/drift.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/json.dart';

import 'sync_backend.dart';

enum MirrorOutcome { applied, skipped, conflict, unknownCollection }

/// Applies pulled cloud documents to the local SQLite mirror.
///
/// A remote document is never allowed to overwrite a record that still has a
/// pending local operation: that case becomes an explicit conflict for the user
/// to resolve, never silent last-write-wins data loss.
class LocalMirror {
  LocalMirror(this.db);

  final AppDatabase db;

  Map<String, TableInfo>? _tablesByName;

  Map<String, TableInfo> get _tables {
    _tablesByName ??= {
      for (final table in db.allTables) table.actualTableName: table,
    };
    return _tablesByName!;
  }

  Future<MirrorOutcome> apply(String collection, RemoteDocument remote) async {
    final tableName = SyncTableNames.collectionToTable[collection];
    if (tableName == null) return MirrorOutcome.unknownCollection;
    final table = _tables[tableName];
    if (table == null) return MirrorOutcome.unknownCollection;

    final pending =
        await (db.select(db.syncQueue)..where(
              (t) =>
                  t.entityId.equals(remote.id) &
                  t.status.isIn([
                    SyncStatus.pending,
                    SyncStatus.syncing,
                    SyncStatus.failed,
                  ]),
            ))
            .getSingleOrNull();

    final local = await db
        .customSelect(
          'SELECT version, sync_status FROM "$tableName" WHERE id = ? LIMIT 1',
          variables: [Variable(remote.id)],
        )
        .getSingleOrNull();

    if (pending != null) {
      await _markConflict(
        tableName: tableName,
        entityId: remote.id,
        queueId: pending.id,
        message: 'Local changes are waiting to sync; the cloud copy was not applied.',
      );
      return MirrorOutcome.conflict;
    }

    if (local != null) {
      final localVersion = local.read<int>('version');
      if (localVersion >= remote.version) return MirrorOutcome.skipped;
    }

    final columns = <String>[];
    final values = <Object?>[];
    var hasId = false;

    for (final column in table.$columns) {
      final name = column.$name;
      if (name == 'id') hasId = true;
      if (!remote.data.containsKey(name)) continue;
      columns.add('"$name"');
      if (name == 'sync_status') {
        values.add(SyncStatus.synced);
      } else {
        values.add(Json.toSqliteValue(name, remote.data[name]));
      }
    }

    if (!hasId) return MirrorOutcome.skipped;
    if (columns.isEmpty) return MirrorOutcome.skipped;

    final placeholders = List.filled(columns.length, '?').join(', ');
    final updates = columns
        .where((c) => c != '"id"')
        .map((c) => '$c = excluded.$c')
        .join(', ');
    final sql = updates.isEmpty
        ? 'INSERT OR REPLACE INTO "$tableName" (${columns.join(', ')}) '
              'VALUES ($placeholders)'
        : 'INSERT INTO "$tableName" (${columns.join(', ')}) '
              'VALUES ($placeholders) '
              'ON CONFLICT("id") DO UPDATE SET $updates';

    await db.customStatement(sql, values);
    db.notifyUpdates({TableUpdate.onTable(table)});
    return MirrorOutcome.applied;
  }

  Future<void> _markConflict({
    required String tableName,
    required String entityId,
    required String queueId,
    required String message,
  }) async {
    final now = DateTime.now();
    await db.customStatement(
      'UPDATE "$tableName" SET sync_status = ? WHERE id = ?',
      [SyncStatus.conflict, entityId],
    );
    await (db.update(db.syncQueue)..where((t) => t.id.equals(queueId))).write(
      SyncQueueCompanion(
        status: const Value(SyncStatus.conflict),
        lastError: Value(message),
        updatedAt: Value(now),
      ),
    );
  }
}
