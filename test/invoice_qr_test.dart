import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/core/scanner/invoice_qr.dart';

void main() {
  group('InvoiceQr', () {
    test('round-trips an invoice number', () {
      final text = InvoiceQr.encode('VBA-2026-DEVICE01-000042');
      final parsed = InvoiceQr.parse(text);
      expect(parsed, isNotNull);
      expect(parsed!.invoiceNumber, 'VBA-2026-DEVICE01-000042');
      expect(parsed.shopId, isNull);
    });

    test('keeps the shop id when present', () {
      final text = InvoiceQr.encode('VBA-2026-A-000001', shopId: 'shop 1');
      final parsed = InvoiceQr.parse(text)!;
      expect(parsed.shopId, 'shop 1');
    });

    test('ignores the local placeholder shop', () {
      expect(
        InvoiceQr.encode('VBA-2026-A-000001', shopId: 'local'),
        'buildstock://invoice/VBA-2026-A-000001',
      );
    });

    test('accepts a bare invoice number, including estimate prefixes', () {
      expect(
        InvoiceQr.parse('VBA-2026-DEVICE01-000042')!.invoiceNumber,
        'VBA-2026-DEVICE01-000042',
      );
      expect(
        InvoiceQr.parse('VBA-EST-2026-DEVICE01-000003')!.invoiceNumber,
        'VBA-EST-2026-DEVICE01-000003',
      );
    });

    test('rejects other codes such as UPI links and product barcodes', () {
      expect(InvoiceQr.parse('upi://pay?pa=a@b&am=10'), isNull);
      expect(InvoiceQr.parse('8901234567890'), isNull);
      expect(InvoiceQr.parse('  '), isNull);
      expect(InvoiceQr.parse(null), isNull);
      expect(InvoiceQr.parse('buildstock://invoice/'), isNull);
    });
  });
}
