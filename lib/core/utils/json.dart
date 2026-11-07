import 'dart:convert';

/// JSON helpers for the sync layer: Firestore documents use snake_case while
/// Drift rows use camelCase. These helpers convert both directions and encode
/// `DateTime` as ISO-8601 so documents stay portable between devices.
class Json {
  const Json._();

  static const _dateKeys = {
    'created_at',
    'updated_at',
    'occurred_at',
    'invoice_date',
    'purchase_date',
    'paid_at',
    'delivery_date',
    'expected_delivery_time',
    'actual_delivery_time',
    'transfer_date',
    'received_at',
    'payment_date',
    'period_start',
    'period_end',
    'valid_until',
    'finalized_at',
    'cancelled_at',
    'joining_date',
    'date_of_birth',
    'licence_expiry_date',
    'insurance_expiry',
    'fitness_expiry',
    'pollution_expiry',
    'opening_date',
    'registered_at',
    'last_seen_at',
    'captured_at',
    'deleted_at',
  };

  static String snake(String input) => input.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m.group(1)}_${m.group(2)!.toLowerCase()}',
  );

  static String camel(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;
    final buffer = StringBuffer(parts.first);
    for (final part in parts.skip(1)) {
      if (part.isEmpty) continue;
      buffer.write(part[0].toUpperCase());
      buffer.write(part.substring(1));
    }
    return buffer.toString();
  }

  /// Converts a Drift `toJson()` map into a Firestore-friendly document.
  /// Drift serialises `DateTime` columns as epoch seconds, so they are restored
  /// to ISO-8601 strings here. Firestore therefore always sees stable strings
  /// that sort correctly for incremental pulls.
  static Map<String, dynamic> toCloud(Map<String, dynamic> row) {
    final out = <String, dynamic>{};
    row.forEach((key, value) {
      if (value == null) return;
      final cloudKey = snake(key);
      if (value is DateTime) {
        out[cloudKey] = value.toUtc().toIso8601String();
      } else if (value is int && _dateKeys.contains(cloudKey)) {
        out[cloudKey] = epochToDate(value, utc: true).toIso8601String();
      } else {
        out[cloudKey] = value;
      }
    });
    return out;
  }

  /// Accepts an epoch in seconds (SQLite storage) or milliseconds (Drift's
  /// `toJson`). Values above 1e11 can only be milliseconds, since 1e11 seconds
  /// is the year 5138.
  static DateTime epochToDate(int value, {bool utc = false}) {
    final millis = value.abs() > 100000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: utc);
  }

  static bool isDateKey(String key) => _dateKeys.contains(key);

  /// Converts a cloud value to what SQLite expects for a Drift column.
  static Object? toSqliteValue(String key, Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw ? 1 : 0;
    if (raw is DateTime) return raw.millisecondsSinceEpoch ~/ 1000;
    if (isDateKey(key) && raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
    }
    if (isDateKey(key) && raw is int) {
      return raw > 100000000000 ? raw ~/ 1000 : raw;
    }
    return raw;
  }

  /// Converts a Firestore document snapshot map into local row values.
  static Map<String, dynamic> fromCloud(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((key, value) {
      var converted = value;
      if (converted is String && _dateKeys.contains(key)) {
        converted = DateTime.tryParse(converted);
      }
      out[camel(key)] = converted;
    });
    return out;
  }

  static String encode(Object? value) => jsonEncode(value);

  static Map<String, dynamic> decodeMap(String? value) {
    if (value == null || value.isEmpty) return const {};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static List<dynamic> decodeList(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static int asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static DateTime? asDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return epochToDate(value);
    return null;
  }

  static bool asBool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    return fallback;
  }
}
