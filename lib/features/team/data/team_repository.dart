import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/security/permissions.dart';
import 'package:buildstock/core/session/session_service.dart';
import 'package:buildstock/core/utils/ids.dart';

class TeamMember {
  const TeamMember({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.active,
    required this.permissions,
  });

  final String uid;
  final String displayName;
  final String email;
  final String role;
  final bool active;
  final List<String> permissions;

  bool get isOwner => role == UserRole.owner;
}

class TeamInvite {
  const TeamInvite({
    required this.code,
    required this.email,
    required this.role,
    required this.expiresAt,
    required this.used,
  });

  final String code;
  final String email;
  final String role;
  final DateTime? expiresAt;
  final bool used;

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

class TeamDevice {
  const TeamDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.active,
    required this.userName,
    required this.lastSeenAt,
    required this.isThisDevice,
  });

  final String id;
  final String name;
  final String platform;
  final String appVersion;
  final bool active;
  final String userName;
  final DateTime? lastSeenAt;
  final bool isThisDevice;
}

/// Users, invites and devices of the cloud shop. These live directly in
/// Firestore (not in the offline sync outbox) because they are access control:
/// changes must take effect immediately and be checked by the security rules.
class TeamRepository {
  TeamRepository(this.services);

  final AppServices services;

  FirebaseFirestore? get _firestore => services.runtime.firestore;
  String get _shopId => services.identity.shopId;

  /// True when this device is signed in and linked to a cloud shop.
  bool get isAvailable =>
      _firestore != null &&
      !services.identity.isLocalOnly &&
      services.identity.userId != null;

  FirebaseFirestore get _fs {
    final firestore = _firestore;
    if (firestore == null) {
      throw const AppFailure(
        FailureCode.syncNotConfigured,
        'Cloud sync is not configured on this build',
      );
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _fs.collection('shops').doc(_shopId).collection('users');

  CollectionReference<Map<String, dynamic>> get _devices =>
      _fs.collection('shops').doc(_shopId).collection('devices');

  CollectionReference<Map<String, dynamic>> get _invites =>
      _fs.collection('invites');

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static List<String> _strings(Object? value) {
    if (value is List) return [for (final item in value) item.toString()];
    return const [];
  }

  // --------------------------------------------------------------- members

  Stream<List<TeamMember>> watchMembers() {
    return _users.snapshots().map((snapshot) {
      final members = [
        for (final doc in snapshot.docs)
          TeamMember(
            uid: doc.id,
            displayName: (doc.data()['display_name'] ?? '').toString(),
            email: (doc.data()['email'] ?? '').toString(),
            role: (doc.data()['role'] ?? UserRole.staff).toString(),
            active: doc.data()['active'] != false,
            permissions: _strings(doc.data()['permissions']),
          ),
      ];
      members.sort((a, b) {
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      return members;
    });
  }

  Future<void> updateMember(
    String uid, {
    String? role,
    bool? active,
    List<String>? permissions,
  }) async {
    if (!services.identity.can(Permissions.manageUsers)) {
      throw const AppFailure(
        FailureCode.permissionDenied,
        'You do not have permission to manage users',
      );
    }
    if (uid == services.identity.userId) {
      throw const ValidationFailure('You can not change your own access');
    }
    if (uid == _shopId) {
      throw const ValidationFailure('The owner account can not be changed');
    }
    final data = <String, Object?>{'updated_at': Timestamp.now()};
    if (role != null) {
      if (!UserRole.assignable.contains(role)) {
        throw const ValidationFailure('Choose a valid role');
      }
      data['role'] = role;
    }
    if (active != null) data['active'] = active;
    if (permissions != null) data['permissions'] = permissions;
    await _users.doc(uid).update(data);
  }

  // --------------------------------------------------------------- invites

  Stream<List<TeamInvite>> watchInvites() {
    return _invites.where('shop_id', isEqualTo: _shopId).snapshots().map((
      snapshot,
    ) {
      final invites = [
        for (final doc in snapshot.docs)
          TeamInvite(
            code: doc.id,
            email: (doc.data()['email'] ?? '').toString(),
            role: (doc.data()['role'] ?? UserRole.staff).toString(),
            expiresAt: _date(doc.data()['expires_at']),
            used: doc.data()['used'] == true,
          ),
      ];
      invites.sort(
        (a, b) => (b.expiresAt ?? DateTime(2000)).compareTo(
          a.expiresAt ?? DateTime(2000),
        ),
      );
      return invites;
    });
  }

  /// Creates a single-use invite valid for 7 days and returns its code. The
  /// invited person signs in with [email] and enters the code.
  Future<String> createInvite({
    required String email,
    required String role,
    List<String>? permissions,
  }) async {
    if (!services.identity.can(Permissions.manageUsers)) {
      throw const AppFailure(
        FailureCode.permissionDenied,
        'You do not have permission to invite users',
      );
    }
    final cleaned = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleaned)) {
      throw const ValidationFailure('Enter a valid email address');
    }
    if (!UserRole.assignable.contains(role)) {
      throw const ValidationFailure('Choose a valid role');
    }
    final code = Ids.randomCode(10);
    await _invites.doc(code).set({
      'shop_id': _shopId,
      'email': cleaned,
      'role': role,
      'permissions': permissions ?? RolePermissions.forRole(role).toList(),
      'used': false,
      'expires_at': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 7)),
      ),
      'created_by': services.identity.userId,
      'created_at': Timestamp.now(),
    });
    return code;
  }

  Future<void> revokeInvite(String code) => _invites.doc(code).delete();

  /// Redeems an invite for the signed-in account and links this device to the
  /// inviting shop. Returns the shop ID.
  Future<String> acceptInvite(String rawCode) async {
    final user = services.runtime.auth?.currentUser;
    if (user == null) {
      throw const ValidationFailure(
        'Sign in first, then enter the invite code',
      );
    }
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) throw const ValidationFailure('Enter the invite code');
    final firestore = _fs;
    final inviteReference = firestore.collection('invites').doc(code);
    final DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await inviteReference.get();
    } on FirebaseException {
      throw const ValidationFailure(
        'This invite is not for the account you are signed in with',
      );
    }
    final invite = snapshot.data();
    if (!snapshot.exists || invite == null) {
      throw const ValidationFailure('Invite not found. Check the code.');
    }
    if (invite['used'] == true) {
      throw const ValidationFailure('This invite was already used');
    }
    final expires = _date(invite['expires_at']);
    if (expires != null && expires.isBefore(DateTime.now())) {
      throw const ValidationFailure('This invite has expired');
    }
    final shopId = (invite['shop_id'] ?? '').toString();
    if (shopId.isEmpty) throw const ValidationFailure('This invite is invalid');
    final role = (invite['role'] ?? UserRole.staff).toString();
    final permissions = _strings(invite['permissions']);

    await firestore
        .collection('shops')
        .doc(shopId)
        .collection('users')
        .doc(user.uid)
        .set({
          'uid': user.uid,
          'shop_id': shopId,
          'display_name': user.displayName ?? user.email ?? 'Team member',
          'email': (user.email ?? '').toLowerCase(),
          'role': role,
          'permissions': permissions.isEmpty
              ? RolePermissions.forRole(role).toList()
              : permissions,
          'active': true,
          'invite_code': code,
          'created_at': Timestamp.now(),
          'updated_at': Timestamp.now(),
        });
    await inviteReference.update({
      'used': true,
      'used_by': user.uid,
      'used_at': Timestamp.now(),
    });

    final session = SessionService(services.db, services.runtime);
    await session.linkShop(shopId);
    await _storeMembership(
      uid: user.uid,
      shopId: shopId,
      name: user.displayName ?? user.email ?? 'Team member',
      email: user.email ?? '',
      role: role,
      permissions: permissions.isEmpty
          ? RolePermissions.forRole(role).toList()
          : permissions,
      active: true,
    );
    await services.updateIdentity(await session.load());
    return shopId;
  }

  // ---------------------------------------------------------------- devices

  Stream<List<TeamDevice>> watchDevices() {
    return _devices.snapshots().map((snapshot) {
      final devices = [
        for (final doc in snapshot.docs)
          TeamDevice(
            id: doc.id,
            name: (doc.data()['name'] ?? doc.id).toString(),
            platform: (doc.data()['platform'] ?? '').toString(),
            appVersion: (doc.data()['app_version'] ?? '').toString(),
            active: doc.data()['active'] != false,
            userName: (doc.data()['user_name'] ?? '').toString(),
            lastSeenAt: _date(doc.data()['last_seen_at']),
            isThisDevice: doc.id == services.identity.deviceId,
          ),
      ];
      devices.sort((a, b) {
        if (a.isThisDevice != b.isThisDevice) return a.isThisDevice ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return devices;
    });
  }

  Future<void> setDeviceActive(String deviceId, bool active) async {
    if (!services.identity.can(Permissions.manageUsers)) {
      throw const AppFailure(
        FailureCode.permissionDenied,
        'You do not have permission to manage devices',
      );
    }
    if (deviceId == services.identity.deviceId && !active) {
      throw const ValidationFailure(
        'You can not disable the device you are using',
      );
    }
    await _devices.doc(deviceId).update({'active': active});
  }

  Future<void> removeDevice(String deviceId) async {
    if (deviceId == services.identity.deviceId) {
      throw const ValidationFailure(
        'You can not remove the device you are using',
      );
    }
    await _devices.doc(deviceId).delete();
  }

  /// True only when the owner has switched this device off. Any error (for
  /// example no network) counts as "not disabled" so offline use is never
  /// blocked by a failed check.
  Future<bool> isThisDeviceDisabled() async {
    if (!isAvailable) return false;
    try {
      final doc = await _devices.doc(services.identity.deviceId).get();
      return doc.exists && doc.data()?['active'] == false;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ membership

  /// Copies this account's membership (role and permissions) from the cloud
  /// into the local users table, so changes made by the owner apply here.
  Future<void> refreshMembership() async {
    if (!isAvailable) return;
    final uid = services.identity.userId!;
    if (uid == _shopId) return; // the owner always has full access
    try {
      final doc = await _users.doc(uid).get();
      final data = doc.data();
      if (!doc.exists || data == null) return;
      final role = (data['role'] ?? UserRole.staff).toString();
      final permissions = _strings(data['permissions']);
      await _storeMembership(
        uid: uid,
        shopId: _shopId,
        name: (data['display_name'] ?? '').toString(),
        email: (data['email'] ?? '').toString(),
        role: role,
        permissions: permissions,
        active: data['active'] != false,
      );
      final session = SessionService(services.db, services.runtime);
      await services.updateIdentity(await session.load());
    } catch (error) {
      debugPrint('Membership refresh skipped: $error');
    }
  }

  Future<void> _storeMembership({
    required String uid,
    required String shopId,
    required String name,
    required String email,
    required String role,
    required List<String> permissions,
    required bool active,
  }) async {
    final now = DateTime.now();
    await services.db
        .into(services.db.users)
        .insertOnConflictUpdate(
          UsersCompanion.insert(
            id: uid,
            shopId: Value(shopId),
            displayName: name.isEmpty ? 'Team member' : name,
            email: Value(email),
            role: Value(role),
            permissionsJson: Value(jsonEncode(permissions)),
            active: Value(active),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(servicesProvider)),
);

final teamMembersProvider = StreamProvider<List<TeamMember>>(
  (ref) => ref.watch(teamRepositoryProvider).watchMembers(),
);

final teamInvitesProvider = StreamProvider<List<TeamInvite>>(
  (ref) => ref.watch(teamRepositoryProvider).watchInvites(),
);

final teamDevicesProvider = StreamProvider<List<TeamDevice>>(
  (ref) => ref.watch(teamRepositoryProvider).watchDevices(),
);
