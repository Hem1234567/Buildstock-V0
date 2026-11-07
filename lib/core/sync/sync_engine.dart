import 'dart:async';

import 'package:drift/drift.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/json.dart';

import 'local_mirror.dart';
import 'outbox.dart';
import 'sync_backend.dart';

class SyncReport {
  const SyncReport({
    required this.startedAt,
    required this.finishedAt,
    required this.pushed,
    required this.pulled,
    required this.failed,
    required this.conflicts,
    required this.skipped,
    required this.errors,
    this.notConfigured = false,
    this.offline = false,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int pushed;
  final int pulled;
  final int failed;
  final int conflicts;
  final int skipped;
  final List<String> errors;
  final bool notConfigured;
  final bool offline;

  bool get isSuccess =>
      errors.isEmpty && failed == 0 && conflicts == 0 && !notConfigured;

  Duration get duration => finishedAt.difference(startedAt);

  static SyncReport notConfiguredReport() => SyncReport(
    startedAt: DateTime.now(),
    finishedAt: DateTime.now(),
    pushed: 0,
    pulled: 0,
    failed: 0,
    conflicts: 0,
    skipped: 0,
    errors: const ['Cloud sync is not configured'],
    notConfigured: true,
  );
}

/// Pushes the durable outbox and pulls incremental cloud changes.
///
/// The engine is deliberately sequential: dependent records must reach the
/// cloud before their children, and a queue item is only marked synced after
/// the backend confirms the write.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.outbox,
    required this.backend,
    required this.deviceId,
    required this.userId,
    LocalMirror? mirror,
  }) : mirror = mirror ?? LocalMirror(db);

  final AppDatabase db;
  final Outbox outbox;
  final SyncBackend backend;
  final LocalMirror mirror;
  final String deviceId;
  final String userId;

  static const int pushBatchSize = 40;
  static const int pullPageSize = 150;
  static const int maxPullPerCollection = 1500;
  static const int maxAttempts = 8;

  bool _running = false;
  bool get isRunning => _running;

  Future<SyncReport> run() async {
    final startedAt = DateTime.now();
    if (_running) {
      return SyncReport(
        startedAt: startedAt,
        finishedAt: startedAt,
        pushed: 0,
        pulled: 0,
        failed: 0,
        conflicts: 0,
        skipped: 0,
        errors: const ['A synchronization is already running'],
      );
    }
    if (!backend.isConfigured) return SyncReport.notConfiguredReport();

    _running = true;
    var pushed = 0;
    var pulled = 0;
    var failed = 0;
    var conflicts = 0;
    var skipped = 0;
    final errors = <String>[];
    var notConfigured = false;

    try {
      await outbox.recoverInterrupted();

      // ---------------- push ----------------
      final due =
          await (db.select(db.syncQueue)
                ..where(
                  (t) =>
                      t.status.isIn([SyncStatus.pending, SyncStatus.failed]) &
                      t.nextAttemptAt.isSmallerOrEqualValue(DateTime.now()),
                )
                ..orderBy([
                  (t) => OrderingTerm.asc(t.priority),
                  (t) => OrderingTerm.asc(t.createdAt),
                ])
                ..limit(pushBatchSize))
              .get();

      for (final item in due) {
        await (db.update(
          db.syncQueue,
        )..where((t) => t.id.equals(item.id))).write(
          SyncQueueCompanion(
            status: const Value(SyncStatus.syncing),
            updatedAt: Value(DateTime.now()),
          ),
        );
        try {
          await backend.push(
            collection: item.collectionName,
            documentId: item.entityId,
            data: Json.decodeMap(item.payloadJson),
            baseVersion: item.baseVersion,
            operationId: item.operationId,
            deviceId: deviceId,
            userId: userId,
          );
          await _markQueueSynced(item);
          pushed++;
        } on SyncConflictException catch (error) {
          conflicts++;
          await _markConflict(item, error.message);
        } on SyncNotConfiguredException {
          notConfigured = true;
          await _markPendingAgain(item, 'Cloud sync is not configured');
          break;
        } on FirebaseException catch (error) {
          failed++;
          await _markFailed(item, _describeFirebaseError(error));
        } catch (error) {
          failed++;
          await _markFailed(item, error.toString());
        }
      }

      if (!notConfigured) {
        // ---------------- pull ----------------
        for (final collection in SyncCollections.all) {
          try {
            final result = await _pullCollection(collection);
            pulled += result.applied;
            skipped += result.skipped;
            conflicts += result.conflicts;
          } catch (error) {
            errors.add('$collection: $error');
          }
        }
      }
    } finally {
      _running = false;
    }

    return SyncReport(
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      pushed: pushed,
      pulled: pulled,
      failed: failed,
      conflicts: conflicts,
      skipped: skipped,
      errors: errors,
      notConfigured: notConfigured,
    );
  }

  Future<_PullResult> _pullCollection(String collection) async {
    var cursor = await _readCursor(collection);
    var applied = 0;
    var skipped = 0;
    var conflicts = 0;
    var fetched = 0;

    while (fetched < maxPullPerCollection) {
      final docs = await backend.pull(
        collection: collection,
        cursor: cursor,
        limit: pullPageSize,
      );
      if (docs.isEmpty) break;

      for (final doc in docs) {
        final outcome = await mirror.apply(collection, doc);
        switch (outcome) {
          case MirrorOutcome.applied:
            applied++;
          case MirrorOutcome.skipped:
            skipped++;
          case MirrorOutcome.conflict:
            conflicts++;
          case MirrorOutcome.unknownCollection:
            break;
        }
      }

      final timestamps = docs
          .map((d) => d.data['updated_at'])
          .whereType<String>()
          .toList();
      if (timestamps.isNotEmpty) {
        timestamps.sort();
        cursor = timestamps.last;
        await _writeCursor(collection, cursor);
      }
      fetched += docs.length;
      if (docs.length < pullPageSize) break;
    }

    return _PullResult(
      applied: applied,
      skipped: skipped,
      conflicts: conflicts,
    );
  }

  Future<String?> _readCursor(String collection) async {
    final row = await (db.select(
      db.syncMetadata,
    )..where((t) => t.key.equals('cursor:$collection'))).getSingleOrNull();
    return row?.cursor;
  }

  Future<void> _writeCursor(String collection, String cursor) async {
    final now = DateTime.now();
    await db
        .into(db.syncMetadata)
        .insertOnConflictUpdate(
          SyncMetadataCompanion.insert(
            key: 'cursor:$collection',
            collectionName: collection,
            cursor: Value(cursor),
            lastPulledAt: Value(now.toIso8601String()),
            updatedAt: now,
          ),
        );
  }

  Future<void> _markQueueSynced(SyncQueueRow item) async {
    final now = DateTime.now();
    await (db.update(db.syncQueue)..where((t) => t.id.equals(item.id))).write(
      SyncQueueCompanion(
        status: const Value(SyncStatus.synced),
        attempts: Value(item.attempts + 1),
        lastError: const Value(null),
        updatedAt: Value(now),
      ),
    );
    await _setEntitySyncStatus(
      item.collectionName,
      item.entityId,
      SyncStatus.synced,
    );
  }

  Future<void> _markPendingAgain(SyncQueueRow item, String reason) async {
    await (db.update(db.syncQueue)..where((t) => t.id.equals(item.id))).write(
      SyncQueueCompanion(
        status: const Value(SyncStatus.pending),
        lastError: Value(reason),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _markFailed(SyncQueueRow item, String error) async {
    final attempts = item.attempts + 1;
    final next = DateTime.now().add(Outbox.backoff(attempts));
    await (db.update(db.syncQueue)..where((t) => t.id.equals(item.id))).write(
      SyncQueueCompanion(
        status: Value(
          attempts >= maxAttempts ? SyncStatus.failed : SyncStatus.pending,
        ),
        attempts: Value(attempts),
        lastError: Value(error),
        nextAttemptAt: Value(next),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (attempts >= maxAttempts) {
      await _setEntitySyncStatus(
        item.collectionName,
        item.entityId,
        SyncStatus.failed,
      );
    }
  }

  Future<void> _markConflict(SyncQueueRow item, String error) async {
    await (db.update(db.syncQueue)..where((t) => t.id.equals(item.id))).write(
      SyncQueueCompanion(
        status: const Value(SyncStatus.conflict),
        lastError: Value(error),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _setEntitySyncStatus(
      item.collectionName,
      item.entityId,
      SyncStatus.conflict,
    );
  }

  Future<void> _setEntitySyncStatus(
    String collection,
    String entityId,
    String status,
  ) async {
    final tableName = SyncTableNames.collectionToTable[collection];
    if (tableName == null) return;
    try {
      await db.customStatement(
        'UPDATE "$tableName" SET sync_status = ? WHERE id = ?',
        [status, entityId],
      );
    } catch (_) {
      // Tables without a sync_status column are skipped.
    }
  }

  String _describeFirebaseError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Permission denied by Firestore rules. Sign in with an '
            'authorized account for this shop.';
      case 'unavailable':
        return 'Cloud is unreachable. The operation remains queued.';
      case 'not-found':
        return 'The cloud document no longer exists.';
      case 'resource-exhausted':
        return 'Firestore quota exceeded. Retry after the quota resets.';
      default:
        return '${error.code}: ${error.message ?? 'Firebase error'}';
    }
  }
}

class _PullResult {
  const _PullResult({
    required this.applied,
    required this.skipped,
    required this.conflicts,
  });

  final int applied;
  final int skipped;
  final int conflicts;
}
