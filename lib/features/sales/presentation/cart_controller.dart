import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/features/sales/domain/invoice_calculator.dart';

class CartLine {
  const CartLine({
    required this.product,
    required this.quantityMilli,
    required this.unitPricePaise,
    this.discountPaise = 0,
  });

  final ProductRow product;
  final int quantityMilli;
  final int unitPricePaise;
  final int discountPaise;

  CartLine copyWith({
    int? quantityMilli,
    int? unitPricePaise,
    int? discountPaise,
  }) => CartLine(
    product: product,
    quantityMilli: quantityMilli ?? this.quantityMilli,
    unitPricePaise: unitPricePaise ?? this.unitPricePaise,
    discountPaise: discountPaise ?? this.discountPaise,
  );

  InvoiceLine toInvoiceLine() => InvoiceLine(
    productId: product.id,
    name: product.name,
    sku: product.sku,
    hsnCode: product.hsnCode,
    unit: product.unitId ?? 'Nos',
    quantityMilli: quantityMilli,
    unitPricePaise: unitPricePaise,
    discountPaise: discountPaise,
    taxRateBps: product.gstRateBps,
  );
}

class CartState {
  const CartState({
    this.lines = const [],
    this.saleType = SaleType.retail,
    this.isGst = true,
    this.invoiceDiscountPaise = 0,
    this.customerId,
    this.amountPaidPaise = 0,
    this.paymentMethod = PaymentMethods.cash,
    this.sourceOrderId,
  });

  final List<CartLine> lines;
  final String saleType;
  final bool isGst;
  final int invoiceDiscountPaise;
  final String? customerId;
  final int amountPaidPaise;
  final String paymentMethod;

  /// Set when the cart was filled from a customer order, so the order can be
  /// marked invoiced after checkout.
  final String? sourceOrderId;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.length;

  InvoiceTotals get totals {
    if (lines.isEmpty) {
      return InvoiceCalculator.compute(
        lines: const [
          InvoiceLine(
            productId: null,
            name: 'Empty',
            quantityMilli: 1000,
            unitPricePaise: 0,
          ),
        ],
        isGst: isGst,
      );
    }
    return InvoiceCalculator.compute(
      lines: lines.map((line) => line.toInvoiceLine()).toList(),
      invoiceDiscountPaise: invoiceDiscountPaise,
      isGst: isGst,
      amountPaidPaise: amountPaidPaise,
    );
  }

  CartState copyWith({
    List<CartLine>? lines,
    String? saleType,
    bool? isGst,
    int? invoiceDiscountPaise,
    String? customerId,
    bool clearCustomer = false,
    int? amountPaidPaise,
    String? paymentMethod,
    String? sourceOrderId,
    bool clearSourceOrder = false,
  }) => CartState(
    lines: lines ?? this.lines,
    saleType: saleType ?? this.saleType,
    isGst: isGst ?? this.isGst,
    invoiceDiscountPaise: invoiceDiscountPaise ?? this.invoiceDiscountPaise,
    customerId: clearCustomer ? null : (customerId ?? this.customerId),
    amountPaidPaise: amountPaidPaise ?? this.amountPaidPaise,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    sourceOrderId: clearSourceOrder
        ? null
        : (sourceOrderId ?? this.sourceOrderId),
  );
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void setSaleType(String type) {
    final updated = state.lines.map((line) {
      final price = type == SaleType.wholesale
          ? line.product.wholesalePricePaise
          : line.product.retailPricePaise;
      return line.copyWith(
        unitPricePaise: price == 0 ? line.unitPricePaise : price,
      );
    }).toList();
    state = state.copyWith(saleType: type, lines: updated);
  }

  void setGst(bool value) => state = state.copyWith(isGst: value);

  /// Replaces the cart with the lines of a customer order.
  void loadFromOrder({
    required String orderId,
    required String? customerId,
    required List<CartLine> lines,
  }) {
    state = CartState(
      lines: lines,
      customerId: customerId,
      sourceOrderId: orderId,
    );
  }

  /// Adds a scanned product, or one more unit of it.
  void addScanned(ProductRow product) => addProduct(product);

  void addProduct(ProductRow product) {
    final existingIndex = state.lines.indexWhere(
      (line) => line.product.id == product.id,
    );
    if (existingIndex >= 0) {
      final line = state.lines[existingIndex];
      final updated = [...state.lines];
      updated[existingIndex] = line.copyWith(
        quantityMilli: line.quantityMilli + 1000,
      );
      state = state.copyWith(lines: updated);
      return;
    }
    final price = state.saleType == SaleType.wholesale
        ? product.wholesalePricePaise
        : product.retailPricePaise;
    state = state.copyWith(
      lines: [
        ...state.lines,
        CartLine(
          product: product,
          quantityMilli: 1000,
          unitPricePaise: price == 0 ? product.retailPricePaise : price,
        ),
      ],
    );
  }

  void updateQuantity(String productId, int quantityMilli) {
    if (quantityMilli <= 0) {
      remove(productId);
      return;
    }
    state = state.copyWith(
      lines: state.lines
          .map(
            (line) => line.product.id == productId
                ? line.copyWith(quantityMilli: quantityMilli)
                : line,
          )
          .toList(),
    );
  }

  void updatePrice(String productId, int unitPricePaise) {
    state = state.copyWith(
      lines: state.lines
          .map(
            (line) => line.product.id == productId
                ? line.copyWith(unitPricePaise: unitPricePaise)
                : line,
          )
          .toList(),
    );
  }

  void updateLineDiscount(String productId, int discountPaise) {
    state = state.copyWith(
      lines: state.lines
          .map(
            (line) => line.product.id == productId
                ? line.copyWith(discountPaise: discountPaise)
                : line,
          )
          .toList(),
    );
  }

  void remove(String productId) {
    state = state.copyWith(
      lines: state.lines.where((line) => line.product.id != productId).toList(),
    );
  }

  void setCustomer(String? customerId) {
    if (customerId == null) {
      state = state.copyWith(clearCustomer: true);
    } else {
      state = state.copyWith(customerId: customerId);
    }
  }

  void setInvoiceDiscount(int paise) =>
      state = state.copyWith(invoiceDiscountPaise: paise);

  void setAmountPaid(int paise) =>
      state = state.copyWith(amountPaidPaise: paise);

  void setPaymentMethod(String method) =>
      state = state.copyWith(paymentMethod: method);

  void clear() => state = const CartState();
}

final cartProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);
