import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/firebase/firebase_runtime.dart';
import 'package:buildstock/core/security/permissions.dart';
import 'package:buildstock/core/utils/ids.dart';

/// Stable identity for this installation and the active shop.
class AppIdentity {
  const AppIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.deviceCode,
    required this.shopId,
    required this.role,
    required this.permissions,
    this.userId,
    this.displayName,
    this.email,
  });

  final String deviceId;
  final String deviceName;
  final String deviceCode;

  /// `local` until the device is linked to a cloud shop.
  final String shopId;
  final String role;
  final Set<String> permissions;
  final String? userId;
  final String? displayName;
  final String? email;

  bool get isLocalOnly => shopId == 'local';

  bool can(String permission) =>
      role == UserRole.owner ||
      role == UserRole.admin ||
      permissions.contains(permission);

  AppIdentity copyWith({
    String? deviceName,
    String? deviceCode,
    String? shopId,
    String? role,
    Set<String>? permissions,
    String? userId,
    String? displayName,
    String? email,
  }) => AppIdentity(
    deviceId: deviceId,
    deviceName: deviceName ?? this.deviceName,
    deviceCode: deviceCode ?? this.deviceCode,
    shopId: shopId ?? this.shopId,
    role: role ?? this.role,
    permissions: permissions ?? this.permissions,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
  );
}

abstract final class IdentityKeys {
  static const deviceId = 'device_id';
  static const deviceName = 'device_name';
  static const deviceCode = 'device_code';
  static const shopId = 'shop_id';
}

/// Loads (or creates) this installation's identity and persists the device
/// record used by the sync dashboard.
class SessionService {
  SessionService(this.db, this.runtime);

  final AppDatabase db;
  final FirebaseRuntime runtime;

  Future<AppIdentity> load() async {
    var deviceId = await db.getSetting(IdentityKeys.deviceId);
    var deviceCode = await db.getSetting(IdentityKeys.deviceCode);
    var deviceName = await db.getSetting(IdentityKeys.deviceName);
    var shopId = await db.getSetting(IdentityKeys.shopId);

    final now = DateTime.now();
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = Ids.newId('dev');
      await db.setSetting(IdentityKeys.deviceId, deviceId);
    }
    if (deviceName == null || deviceName.isEmpty) {
      deviceName = _defaultDeviceName();
      await db.setSetting(IdentityKeys.deviceName, deviceName);
    }
    if (deviceCode == null || deviceCode.isEmpty) {
      deviceCode = 'DEV${Ids.randomCode(3)}';
      await db.setSetting(IdentityKeys.deviceCode, deviceCode);
    }

    final user = runtime.auth?.currentUser;
    if (user == null && shopId != null && shopId != 'local') {
      // Signing out returns this device to its own local data; it must not
      // keep writing into the previous account's cloud shop.
      shopId = 'local';
      await db.setSetting(IdentityKeys.shopId, shopId);
    }
    if (shopId == null || shopId.isEmpty || shopId == 'local') {
      // The owner's shop document is keyed by their auth UID.
      if (user != null) {
        shopId = user.uid;
        await db.setSetting(IdentityKeys.shopId, shopId);
      } else {
        shopId = 'local';
      }
    }

    await db
        .into(db.devices)
        .insertOnConflictUpdate(
          DevicesCompanion.insert(
            id: deviceId,
            shopId: Value(shopId),
            name: deviceName,
            platform: Value(_platformName()),
            appVersion: const Value('1.0.0'),
            deviceCode: Value(deviceCode),
            registeredAt: now,
            lastSeenAt: now,
          ),
        );

    String role = UserRole.owner;
    var permissions = <String>{...Permissions.all};

    if (user != null && user.uid != shopId) {
      final membership = await (db.select(
        db.users,
      )..where((t) => t.id.equals(user.uid))).getSingleOrNull();
      role = membership?.role ?? UserRole.staff;
      permissions = RolePermissions.forRole(role).toSet();
      if (membership != null) {
        // The owner can tune a member's permissions; they are stored with the
        // membership and override the role defaults.
        try {
          final stored = jsonDecode(membership.permissionsJson);
          if (stored is List && stored.isNotEmpty) {
            permissions = {for (final item in stored) item.toString()};
          }
        } catch (_) {}
        if (!membership.active) permissions = <String>{};
      }
    }

    return AppIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceCode: deviceCode,
      shopId: shopId,
      role: role,
      permissions: permissions,
      userId: user?.uid,
      displayName: user?.displayName,
      email: user?.email,
    );
  }

  Future<void> linkShop(String shopId) async {
    await db.setSetting(IdentityKeys.shopId, shopId);
  }

  Future<void> unlinkShop() async {
    await db.setSetting(IdentityKeys.shopId, 'local');
  }

  Future<void> renameDevice(String name) async {
    await db.setSetting(IdentityKeys.deviceName, name);
    final id = await db.getSetting(IdentityKeys.deviceId);
    if (id != null) {
      await (db.update(db.devices)..where((t) => t.id.equals(id))).write(
        DevicesCompanion(name: Value(name)),
      );
    }
  }

  String _defaultDeviceName() {
    if (kIsWeb) return 'Web device';
    try {
      if (Platform.isAndroid) return 'Android device';
      if (Platform.isIOS) return 'iPhone';
    } catch (_) {}
    return 'This device';
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }
}
