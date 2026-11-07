import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/features/orders/data/orders_repository.dart';
import 'package:buildstock/features/search/global_search_screen.dart';
import 'package:buildstock/core/utils/json.dart';

void main() {
  group('Credit and debit notes', () {
    test('only the four note types are notes', () {
      for (final type in ReturnType.noteTypes) {
        expect(ReturnType.isNote(type), isTrue);
      }
      expect(ReturnType.isNote(ReturnType.saleReturn), isFalse);
      expect(ReturnType.isNote(ReturnType.purchaseReturn), isFalse);
    });

    test('customer and supplier notes are told apart', () {
      expect(ReturnType.isCustomerNote(ReturnType.creditNote), isTrue);
      expect(ReturnType.isCustomerNote(ReturnType.debitNote), isTrue);
      expect(ReturnType.isCustomerNote(ReturnType.purchaseDebitNote), isFalse);
    });

    test('each type has its own number prefix', () {
      final prefixes = ReturnType.noteTypes.map(ReturnType.prefix).toSet();
      expect(prefixes.length, ReturnType.noteTypes.length);
    });
  });

  group('Customer orders', () {
    test('order lines survive a JSON round trip', () {
      const line = OrderLine(
        productId: 'p1',
        name: 'Cement 50kg',
        quantityMilli: 2500,
        unitPricePaise: 38000,
        taxRateBps: 2800,
      );
      final decoded = OrderLine.fromJson(line.toJson());
      expect(decoded.name, 'Cement 50kg');
      expect(decoded.quantityMilli, 2500);
      expect(decoded.amountPaise, 95000);
    });

    test('bad JSON gives an empty list instead of throwing', () {
      expect(OrderLine.decode('oops'), isEmpty);
      expect(OrderLine.decode('{}'), isEmpty);
    });

    test('active statuses are the ones that still need work', () {
      expect(OrderStatus.isActive(OrderStatus.open), isTrue);
      expect(OrderStatus.isActive(OrderStatus.ready), isTrue);
      expect(OrderStatus.isActive(OrderStatus.invoiced), isFalse);
      expect(OrderStatus.isActive(OrderStatus.cancelled), isFalse);
    });
  });

  group('Global search', () {
    test('escapes LIKE wildcards in the query', () {
      expect(GlobalSearchRepository.likePattern('50%'), r'%50\%%');
      expect(GlobalSearchRepository.likePattern('a_b'), r'%a\_b%');
    });
  });

  group('Json dates', () {
    test('seconds and milliseconds both become the same instant', () {
      final seconds = Json.epochToDate(1760000000, utc: true);
      final millis = Json.epochToDate(1760000000000, utc: true);
      expect(seconds, millis);
      expect(seconds.year, 2025);
    });
  });
}
