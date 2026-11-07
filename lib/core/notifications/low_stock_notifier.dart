import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/utils/dates.dart';

class LowStockItem {
  const LowStockItem({
    required this.productId,
    required this.name,
    required this.stockMilli,
    required this.minStockMilli,
  });

  final String productId;
  final String name;
  final int stockMilli;
  final int minStockMilli;
}

abstract final class LowStockSettings {
  static const enabled = 'low_stock_alerts';
  static const lastNotice = 'low_stock_last_notice';
}

/// Posts a local notification when products fall to or below their minimum
/// stock. The alert is raised at most once per day for the same set of
/// products, so it never becomes noise.
class LowStockNotifier {
  LowStockNotifier(this.services);

  final AppServices services;

  static const _channelId = 'low_stock';
  static const _notificationId = 4101;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  AppDatabase get db => services.db;

  /// Total stock across every godown, compared with the product minimum.
  Future<List<LowStockItem>> lowStock() async {
    final rows = await db
        .customSelect(
          'SELECT p.id AS id, p.name AS name, p.min_stock_milli AS min_stock, '
          'COALESCE(SUM(i.quantity_milli), 0) AS stock '
          'FROM products p LEFT JOIN inventories i ON i.product_id = p.id '
          'WHERE p.active = 1 AND p.deleted_at IS NULL '
          'AND p.min_stock_milli > 0 '
          'GROUP BY p.id, p.name, p.min_stock_milli '
          'HAVING COALESCE(SUM(i.quantity_milli), 0) <= p.min_stock_milli '
          'ORDER BY p.name',
        )
        .get();
    return [
      for (final row in rows)
        LowStockItem(
          productId: row.read<String>('id'),
          name: row.read<String>('name'),
          stockMilli: row.read<int>('stock'),
          minStockMilli: row.read<int>('min_stock'),
        ),
    ];
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    // The plugin changed from positional to named parameters between major
    // versions. Dynamic dispatch lets one code path work with either.
    final dynamic plugin = _plugin;
    try {
      await plugin.initialize(settings: settings);
    } on NoSuchMethodError {
      await plugin.initialize(settings);
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> _show(String title, String body) async {
    await _ensureInitialized();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Low stock alerts',
        channelDescription: 'Tells you when products fall below their minimum',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
    final dynamic plugin = _plugin;
    try {
      await plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } on NoSuchMethodError {
      await plugin.show(_notificationId, title, body, details);
    }
  }

  static String summary(List<LowStockItem> items) {
    if (items.isEmpty) return '';
    final names = items.take(3).map((item) => item.name).toList();
    final rest = items.length - names.length;
    final list = names.join(', ');
    return rest > 0
        ? '$list and $rest more are at or below minimum stock.'
        : '$list ${names.length == 1 ? 'is' : 'are'} at or below minimum stock.';
  }

  /// Checks stock and notifies if needed. Returns how many products are low.
  /// Never throws: a notification problem must not disturb the app.
  Future<int> check({bool force = false}) async {
    if (kIsWeb) return 0;
    try {
      final enabled = await db.getSetting(LowStockSettings.enabled);
      if (!force && enabled == 'false') return 0;
      final items = await lowStock();
      if (items.isEmpty) {
        await db.setSetting(LowStockSettings.lastNotice, '');
        return 0;
      }
      final signature =
          '${AppDate.isoDate(DateTime.now())}|'
          '${items.map((item) => item.productId).join(',')}';
      final last = await db.getSetting(LowStockSettings.lastNotice);
      if (force || last != signature) {
        await _show('Low stock alert', summary(items));
        await db.setSetting(LowStockSettings.lastNotice, signature);
      }
      return items.length;
    } catch (_) {
      return 0;
    }
  }
}

final lowStockNotifierProvider = Provider<LowStockNotifier>(
  (ref) => LowStockNotifier(ref.watch(servicesProvider)),
);
