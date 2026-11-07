/// Payload printed as a small QR code on every invoice so that a bill can be
/// opened again by scanning it, on this or any other device of the shop.
class InvoiceQrPayload {
  const InvoiceQrPayload({required this.invoiceNumber, this.shopId});

  final String invoiceNumber;
  final String? shopId;
}

abstract final class InvoiceQr {
  static const String scheme = 'buildstock://invoice/';

  static final RegExp _plainNumber = RegExp(
    r'^[A-Za-z0-9]+(-[A-Za-z0-9]+)*-\d{4}-[A-Za-z0-9]+-\d{6}$',
  );

  /// Builds the text stored in the QR code.
  static String encode(String invoiceNumber, {String? shopId}) {
    final number = Uri.encodeComponent(invoiceNumber.trim());
    final shop = (shopId == null || shopId.isEmpty || shopId == 'local')
        ? ''
        : '?shop=${Uri.encodeComponent(shopId)}';
    return '$scheme$number$shop';
  }

  /// Parses scanned text. Accepts the BuildStock QR format and a bare invoice
  /// number (for example from a printed barcode). Returns null for anything
  /// else, such as a UPI payment QR or a product barcode.
  static InvoiceQrPayload? parse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith(scheme)) {
      final rest = text.substring(scheme.length);
      final queryIndex = rest.indexOf('?');
      final numberPart = queryIndex < 0 ? rest : rest.substring(0, queryIndex);
      final number = Uri.decodeComponent(numberPart).trim();
      if (number.isEmpty) return null;
      String? shop;
      if (queryIndex >= 0) {
        final params = Uri.splitQueryString(rest.substring(queryIndex + 1));
        shop = params['shop'];
      }
      return InvoiceQrPayload(invoiceNumber: number, shopId: shop);
    }
    if (_plainNumber.hasMatch(text)) {
      return InvoiceQrPayload(invoiceNumber: text);
    }
    return null;
  }
}
