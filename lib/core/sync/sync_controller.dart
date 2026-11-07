import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/security/permissions.dart';

import 'firestore_backend.dart';
import 'sync_engine.dart';

import 'package:buildstock/features/team/data/team_repository.dart';

class SyncUiState {
  const SyncUiState({this.running = false, this.lastReport, this.error});

  final bool running;
  final SyncReport? lastReport;
  final String? error;

  SyncUiState copyWith({
    bool? running,
    SyncReport? lastReport,
    String? error,
    bool clearError = false,
  }) => SyncUiState(
    running: running ?? this.running,
    lastReport: lastReport ?? this.lastReport,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Owns manual and automatic synchronization. The UI never constructs a
/// Firestore client; it only asks this controller to run.
class SyncController extends Notifier<SyncUiState> {
  @override
  SyncUiState build() => const SyncUiState();

  Future<void> run({bool force = false}) async {
    if (state.running) return;
    final services = ref.read(servicesProvider);
    final auth = services.auth;

    if (!services.runtime.isReady) {
      state = state.copyWith(
        running: false,
        lastReport: SyncReport.notConfiguredReport(),
        error:
            services.runtime.unavailableReason ??
            'Cloud sync is not configured on this build',
      );
      return;
    }
    if (!auth.isSignedIn || services.identity.shopId == 'local') {
      state = state.copyWith(
        running: false,
        lastReport: SyncReport.notConfiguredReport(),
        error:
            'Sign in to connect this device to the cloud shop. Offline features '
            'continue to work.',
      );
      return;
    }

    state = state.copyWith(running: true, clearError: true);
    try {
      final backend = FirestoreSyncBackend(
        firestore: services.runtime.firestore!,
        shopId: services.identity.shopId,
      );

      // The owner can disable a device from Team & devices. A disabled
      // device keeps working offline but does not exchange data.
      final team = TeamRepository(services);
      if (await team.isThisDeviceDisabled()) {
        state = state.copyWith(
          running: false,
          error: 'This device was disabled by the shop owner. Ask the owner to enable it in Team & devices.',
        );
        return;
      }

      // The owner's first online sync provisions the shop and membership if
      // the earlier bootstrap attempt happened while offline.
      if (services.identity.shopId == auth.runtime.uid) {
        final profile = await services.db
            .select(services.db.businessProfiles)
            .getSingleOrNull();
        await backend.ensureOwnerShop(
          businessName: profile?.name ?? 'Vijay Balaji Agency',
          displayName:
              auth.runtime.auth?.currentUser?.displayName ??
              profile?.ownerName ??
              'Owner',
          email: auth.runtime.auth?.currentUser?.email ?? '',
          permissions: Permissions.all,
        );
      }
      await backend.registerDevice(
        deviceId: services.identity.deviceId,
        deviceName: services.identity.deviceName,
        deviceCode: services.identity.deviceCode,
        platform: defaultTargetPlatform.name,
        appVersion: '1.0.0',
        userId: auth.runtime.uid,
        userName: services.identity.displayName ?? services.identity.email,
      );
      await team.refreshMembership();

      final engine = SyncEngine(
        db: services.db,
        outbox: services.outbox,
        backend: backend,
        deviceId: services.identity.deviceId,
        userId: auth.runtime.uid ?? '',
      );
      final report = await engine.run();
      if (report.notConfigured) {
        state = state.copyWith(
          running: false,
          lastReport: report,
          error:
              'This device is not linked to a cloud shop yet. Sign in as the '
              'owner or redeem an invite from Settings.',
        );
      } else {
        state = state.copyWith(
          running: false,
          lastReport: report,
          error: report.errors.isEmpty ? null : report.errors.first,
        );
      }
      await services.db.setSetting(
        'last_sync_at',
        report.finishedAt.toIso8601String(),
      );
    } catch (error) {
      state = state.copyWith(running: false, error: error.toString());
    }
  }

  Future<void> retryFailed() async {
    final services = ref.read(servicesProvider);
    await services.outbox.retryFailed();
    await run();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);
