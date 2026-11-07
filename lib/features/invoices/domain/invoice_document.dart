import 'dart:convert';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/json.dart';
import 'package:buildstock/core/utils/money.dart';

class InvoiceParty {
  const InvoiceParty({
    required this.name,
    this.businessName = '',
    this.phone = '',
    this.address = '',
    this.gstin = '',
    this.state = '',
    this.stateCode = '',
    this.phones = const [],
  });

  final String name;
  final String businessName;
  final String phone;
  final String address;
  final String gstin;
  final String state;
  final String stateCode;
  final List<String> phones;

  List<String> get allPhones =>
      phones.isNotEmpty ? phones : (phone.isEmpty ? const [] : [phone]);

  factory InvoiceParty.fromSellerJson(Map<String, dynamic> json) {
    final phones =
        (json['phones'] as List?)
            ?.map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    return InvoiceParty(
      name: json['name']?.toString() ?? '',
      phone: phones.isEmpty ? '' : phones.first,
      address: json['address']?.toString() ?? '',
      gstin: json['gstin']?.toString() ?? '',
      stateCode: json['state_code']?.toString() ?? '',
      phones: phones,
    );
  }

  factory InvoiceParty.fromBuyerJson(Map<String, dynamic> json) {
    return InvoiceParty(
      name: json['name']?.toString() ?? 'Walk-in Customer',
      businessName: json['business_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      gstin: json['gstin']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      stateCode: json['state_code']?.toString() ?? '',
    );
  }
}

class InvoiceDocumentItem {
  const InvoiceDocumentItem({
    required this.name,
    required this.quantityMilli,
    required this.unitPricePaise,
    required this.lineTotalPaise,
    this.sku = '',
    this.hsnCode = '',
    this.unit = 'Nos',
    this.discountPaise = 0,
    this.taxRateBps = 0,
    this.taxPaise = 0,
  });

  final String name;
  final String sku;
  final String hsnCode;
  final String unit;
  final int quantityMilli;
  final int unitPricePaise;
  final int discountPaise;
  final int taxRateBps;
  final int taxPaise;
  final int lineTotalPaise;
}

/// Immutable rendering model assembled from the stored invoice snapshots.
/// Old invoices never change when the product catalogue or business profile is
/// edited, because every displayed value comes from this snapshot.
class InvoiceDocument {
  const InvoiceDocument({
    required this.id,
    required this.number,
    required this.documentType,
    required this.status,
    required this.date,
    required this.time,
    required this.seller,
    required this.buyer,
    required this.items,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.grandTotalPaise,
    required this.amountPaidPaise,
    required this.balanceDuePaise,
    required this.paymentMethod,
    required this.notes,
    required this.isGst,
    this.upiId = '',
    this.upiPayeeName = '',
    this.templateVersion = 1,
    this.logoRef,
    this.signatureRef,
    this.stampRef,
  });

  final String id;
  final String number;
  final String documentType;
  final String status;
  final DateTime date;
  final String time;
  final InvoiceParty seller;
  final InvoiceParty buyer;
  final List<InvoiceDocumentItem> items;
  final int subtotalPaise;
  final int discountPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int grandTotalPaise;
  final int amountPaidPaise;
  final int balanceDuePaise;
  final String paymentMethod;
  final String notes;
  final bool isGst;
  final String upiId;
  final String upiPayeeName;
  final int templateVersion;
  final String? logoRef;
  final String? signatureRef;
  final String? stampRef;

  bool get isEstimate => documentType != DocumentType.invoice;
  bool get isCancelled => status == DocumentStatus.cancelled;
  String get heading => documentType == DocumentType.quotation
      ? 'QUOTATION'
      : (isEstimate ? 'ESTIMATE' : 'BILL');
  String get dateLabel => AppDate.display(date);
  String get amountInWords => Money.inWords(grandTotalPaise);
  int get totalQuantityMilli =>
      items.fold(0, (sum, item) => sum + item.quantityMilli);

  bool get showUpiQr =>
      !isEstimate && upiId.trim().isNotEmpty && balanceDuePaise > 0;

  static InvoiceDocument? fromRows(SaleRow sale, List<SaleItemRow> items) {
    final sellerJson = Json.decodeMap(sale.sellerSnapshotJson);
    final buyerJson = Json.decodeMap(sale.buyerSnapshotJson);
    if (sellerJson.isEmpty && buyerJson.isEmpty && items.isEmpty) return null;
    return InvoiceDocument(
      id: sale.id,
      number: sale.invoiceNumber,
      documentType: sale.documentType,
      status: sale.documentStatus,
      date: sale.invoiceDate,
      time: sale.invoiceTime,
      seller: InvoiceParty.fromSellerJson(sellerJson),
      buyer: InvoiceParty.fromBuyerJson(buyerJson),
      items: items
          .map(
            (item) => InvoiceDocumentItem(
              name: item.productName,
              sku: item.sku,
              hsnCode: item.hsnCode,
              unit: item.unit,
              quantityMilli: item.quantityMilli,
              unitPricePaise: item.unitPricePaise,
              discountPaise: item.discountPaise,
              taxRateBps: item.taxRateBps,
              taxPaise: item.taxAmountPaise,
              lineTotalPaise: item.lineTotalPaise,
            ),
          )
          .toList(),
      subtotalPaise: sale.subtotalPaise,
      discountPaise: sale.discountPaise,
      taxablePaise: sale.taxableAmountPaise,
      cgstPaise: sale.cgstPaise,
      sgstPaise: sale.sgstPaise,
      igstPaise: sale.igstPaise,
      roundOffPaise: sale.roundOffPaise,
      grandTotalPaise: sale.grandTotalPaise,
      amountPaidPaise: sale.amountPaidPaise,
      balanceDuePaise: sale.balanceDuePaise,
      paymentMethod: sale.paymentMethod,
      notes: sale.notes,
      isGst: sale.isGst,
      upiId: sellerJson['upi_id']?.toString() ?? '',
      upiPayeeName:
          sellerJson['upi_payee_name']?.toString() ?? sale.invoiceNumber,
      templateVersion: sale.templateVersion,
      logoRef: sellerJson['logo_ref']?.toString(),
      signatureRef: sellerJson['signature_ref']?.toString(),
      stampRef: sellerJson['stamp_ref']?.toString(),
    );
  }

  String paymentMethodLabel() {
    return switch (paymentMethod) {
      PaymentMethods.cash => 'Cash',
      PaymentMethods.upi => 'UPI',
      PaymentMethods.bank => 'Bank Transfer',
      PaymentMethods.cheque => 'Cheque',
      PaymentMethods.credit => 'Credit',
      _ => 'Other',
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice_number': number,
    'document_type': documentType,
    'document_status': status,
    'invoice_date': date.toIso8601String(),
    'seller': {
      'name': seller.name,
      'phones': seller.allPhones,
      'address': seller.address,
      'gstin': seller.gstin,
    },
    'buyer': {
      'name': buyer.name,
      'phone': buyer.phone,
      'address': buyer.address,
      'gstin': buyer.gstin,
    },
    'items': items
        .map(
          (item) => {
            'name': item.name,
            'sku': item.sku,
            'hsn_code': item.hsnCode,
            'unit': item.unit,
            'quantity_milli': item.quantityMilli,
            'unit_price_paise': item.unitPricePaise,
            'discount_paise': item.discountPaise,
            'tax_rate_bps': item.taxRateBps,
            'tax_paise': item.taxPaise,
            'line_total_paise': item.lineTotalPaise,
          },
        )
        .toList(),
    'subtotal_paise': subtotalPaise,
    'discount_paise': discountPaise,
    'taxable_paise': taxablePaise,
    'cgst_paise': cgstPaise,
    'sgst_paise': sgstPaise,
    'igst_paise': igstPaise,
    'round_off_paise': roundOffPaise,
    'grand_total_paise': grandTotalPaise,
    'amount_paid_paise': amountPaidPaise,
    'balance_due_paise': balanceDuePaise,
    'payment_method': paymentMethod,
    'is_gst': isGst,
    'upi_id': upiId,
    'template_version': templateVersion,
  };

  String encode() => jsonEncode(toJson());
}
