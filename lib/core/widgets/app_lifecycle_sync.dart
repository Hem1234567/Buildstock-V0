import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/backup/backup_service.dart';
import 'package:buildstock/core/media/image_service.dart';
import 'package:buildstock/core/notifications/low_stock_notifier.dart';
import 'package:buildstock/core/sync/sync_controller.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

/// Triggers synchronization when the app starts, resumes, or regains a network
/// interface. Connectivity is only a trigger: the engine still handles cloud
/// failures and keeps the outbox intact.
class AppLifecycleSync extends ConsumerStatefulWidget {
  const AppLifecycleSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleSync> createState() => _AppLifecycleSyncState();
}

class _AppLifecycleSyncState extends ConsumerState<AppLifecycleSync>
    with WidgetsBindingObserver {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
    }
  }

  void _sync() {
    if (!mounted) return;
    if (!_started) _started = true;
    unawaited(ref.read(syncControllerProvider.notifier).run());
    unawaited(_housekeeping());
  }

  /// Background chores that must never disturb the user: upload waiting photos,
  /// raise a low-stock alert and keep the daily local backup.
  Future<void> _housekeeping() async {
    try {
      await ref.read(imageServiceProvider).uploadPending();
    } catch (_) {}
    try {
      await ref.read(lowStockNotifierProvider).check();
    } catch (_) {}
    try {
      await ref.read(backupServiceProvider).autoBackupIfDue();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectivityProvider, (previous, next) {
      final results = next.value;
      if (results == null) return;
      final online = results.any(
        (result) =>
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.ethernet ||
            result == ConnectivityResult.vpn,
      );
      if (online) _sync();
    });
    return widget.child;
  }
}
