import 'package:cloud_firestore/cloud_firestore.dart';

import 'sync_backend.dart';

/// Firestore implementation of the sync backend. It is the only place in the
/// application (besides authentication) that talks to Firebase directly.
class FirestoreSyncBackend implements SyncBackend {
  FirestoreSyncBackend({
    required FirebaseFirestore firestore,
    required this.shopId,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  final String shopId;

  @override
  bool get isConfigured => true;

  DocumentReference<Map<String, dynamic>> _doc(String collection, String id) =>
      _firestore.collection('shops').doc(shopId).collection(collection).doc(id);

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _firestore.collection('shops').doc(shopId).collection(name);

  @override
  Future<void> push({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    required int baseVersion,
    required String operationId,
    required String deviceId,
    required String userId,
  }) async {
    final docRef = _doc(collection, documentId);
    final operationRef = _collection('sync_operations').doc(operationId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        final remoteVersion =
            (snapshot.data()?['version'] as num?)?.toInt() ?? 0;
        if (remoteVersion > baseVersion) {
          throw SyncConflictException(
            'Remote version $remoteVersion is newer than local base '
            'version $baseVersion for $collection/$documentId',
          );
        }
      }
      transaction.set(docRef, {
        ...data,
        'id': documentId,
        'shop_id': shopId,
        'device_id': deviceId,
        'updated_by': userId,
        'server_updated_at': FieldValue.serverTimestamp(),
        'last_operation_id': operationId,
      });
      // An append-only marker makes retries auditable. Deterministic document
      // IDs plus Firestore `set` semantics keep writes idempotent.
      transaction.set(operationRef, {
        'operation_id': operationId,
        'shop_id': shopId,
        'collection': collection,
        'document_id': documentId,
        'device_id': deviceId,
        'user_id': userId,
        'base_version': baseVersion,
        'applied_at': FieldValue.serverTimestamp(),
        'status': 'applied',
      });
    });
  }

  @override
  Future<List<RemoteDocument>> pull({
    required String collection,
    String? cursor,
    int limit = 200,
  }) async {
    Query<Map<String, dynamic>> query = _collection(collection)
        .orderBy('updated_at')
        .limit(limit);
    if (cursor != null && cursor.isNotEmpty) {
      query = query.where('updated_at', isGreaterThan: cursor);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) {
          final normalized = <String, dynamic>{};
          doc.data().forEach((key, value) {
            normalized[key] = _normalize(value);
          });
          return RemoteDocument(
            id: doc.id,
            data: normalized,
            version: (doc.data()['version'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);
  }

  Object? _normalize(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is List) return value.map(_normalize).toList();
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _normalize(nested)),
      );
    }
    return value;
  }

  /// Creates the shop and owner membership on the owner's first sync. Firestore
  /// rules allow this only when the authenticated UID owns the shop path.
  Future<void> ensureOwnerShop({
    required String businessName,
    required String displayName,
    required String email,
    required List<String> permissions,
  }) async {
    final shopRef = _firestore.collection('shops').doc(shopId);
    final snapshot = await shopRef.get();
    if (!snapshot.exists) {
      await shopRef.set({
        'id': shopId,
        'owner_id': shopId,
        'name': businessName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'schema_version': 1,
      });
    }
    final memberRef = shopRef.collection('users').doc(shopId);
    final member = await memberRef.get();
    if (!member.exists) {
      await memberRef.set({
        'uid': shopId,
        'shop_id': shopId,
        'display_name': displayName,
        'email': email,
        'role': 'owner',
        'permissions': permissions,
        'active': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// Registers this device heartbeat so the owner can see active devices.
  Future<void> registerDevice({
    required String deviceId,
    required String deviceName,
    required String deviceCode,
    required String platform,
    required String appVersion,
    String? userId,
    String? userName,
  }) async {
    await ifSupported(() async {
      final reference = _collection('devices').doc(deviceId);
      final existing = await reference.get();
      final now = DateTime.now().toUtc().toIso8601String();
      final data = <String, Object?>{
        'id': deviceId,
        'shop_id': shopId,
        'name': deviceName,
        'device_code': deviceCode,
        'platform': platform,
        'app_version': appVersion,
        'last_seen_at': now,
        'user_id': userId ?? '',
        'user_name': userName ?? '',
      };
      // A new device starts active. An existing device keeps whatever the
      // owner chose, so a disabled device can not re-enable itself.
      if (!existing.exists) {
        data['registered_at'] = now;
        data['active'] = true;
      }
      await reference.set(data, SetOptions(merge: true));
    });
  }

  Future<T?> ifSupported<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException {
      return null;
    }
  }
}
