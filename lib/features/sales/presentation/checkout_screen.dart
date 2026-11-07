import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/customers/data/parties_repository.dart';
import 'package:buildstock/features/sales/data/sales_repository.dart';
import 'package:buildstock/features/invoices/data/auto_print.dart';
import 'package:buildstock/features/orders/data/orders_repository.dart';
import 'package:buildstock/features/sales/presentation/cart_controller.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';
import 'package:buildstock/features/stores/presentation/stock_location_picker.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _paid = TextEditingController();
  final _discount = TextEditingController();
  final _notes = TextEditingController();
  String? _customerId;
  String _docType = DocumentType.invoice;
  StockLocation _location = const StockLocation();
  final _validDays = TextEditingController(text: '15');
  String _method = PaymentMethods.cash;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _paid.text = (cart.totals.grandTotalPaise / 100).toStringAsFixed(2);
    _method = cart.paymentMethod;
    _customerId = cart.customerId;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _address,
      _paid,
      _discount,
      _notes,
      _validDays,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final customers = ref.watch(customersStreamProvider(''));
    final theme = Theme.of(context);
    final totals = cart.totals;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Document', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: DocumentType.invoice,
                        label: Text('Invoice'),
                      ),
                      ButtonSegment(
                        value: DocumentType.estimate,
                        label: Text('Estimate'),
                      ),
                      ButtonSegment(
                        value: DocumentType.quotation,
                        label: Text('Quotation'),
                      ),
                    ],
                    selected: {_docType},
                    onSelectionChanged: (value) =>
                        setState(() => _docType = value.first),
                  ),
                  const SizedBox(height: 8),
                  if (_docType == DocumentType.invoice)
                    StockLocationDropdown(
                      value: _location,
                      onChanged: (value) => setState(() => _location = value),
                      label: 'Take stock from',
                    )
                  else ...[
                    TextField(
                      controller: _validDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Valid for (days)',
                        helperText: 'Estimates and quotations never change stock. Convert them to an invoice when the customer agrees.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  AsyncView(
                    value: customers,
                    loading: const LinearProgressIndicator(),
                    builder: (rows) => DropdownButtonFormField<String?>(
                      initialValue: _customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select customer',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Walk-in customer'),
                        ),
                        for (final customer in rows)
                          DropdownMenuItem<String?>(
                            value: customer.id,
                            child: Text(customer.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _customerId = value),
                    ),
                  ),
                  if (_customerId == null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Buyer name (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _address,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('GST invoice'),
                    subtitle: const Text(
                      'Tax is calculated from each product GST rate.',
                    ),
                    value: cart.isGst,
                    onChanged: (value) =>
                        ref.read(cartProvider.notifier).setGst(value),
                    activeTrackColor: AppColors.accent,
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Invoice discount',
                            prefixText: '₹ ',
                          ),
                          onChanged: (value) {
                            final paise = Money.tryParseRupees(value) ?? 0;
                            ref
                                .read(cartProvider.notifier)
                                .setInvoiceDiscount(paise);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _paid,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount paid',
                            prefixText: '₹ ',
                          ),
                          onChanged: (value) {
                            final paise = Money.tryParseRupees(value) ?? 0;
                            ref
                                .read(cartProvider.notifier)
                                .setAmountPaid(paise);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(
                        value: 'bank',
                        child: Text('Bank transfer'),
                      ),
                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                      DropdownMenuItem(value: 'credit', child: Text('Credit')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _method = value);
                      ref.read(cartProvider.notifier).setPaymentMethod(value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                children: [
                  _row(context, 'Subtotal', Money.format(totals.subtotalPaise)),
                  if (totals.discountPaise > 0)
                    _row(
                      context,
                      'Discount',
                      '- ${Money.format(totals.discountPaise)}',
                    ),
                  _row(
                    context,
                    'Taxable',
                    Money.format(totals.taxableAmountPaise),
                  ),
                  if (totals.taxPaise > 0)
                    _row(context, 'Tax', Money.format(totals.taxPaise)),
                  const Divider(),
                  _row(
                    context,
                    'Grand Total',
                    Money.format(totals.grandTotalPaise),
                    emphasize: true,
                  ),
                  _row(
                    context,
                    'Balance Due',
                    Money.format(totals.balanceDuePaise),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: _saving || cart.isEmpty ? null : _finalize,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  '${_docType == DocumentType.invoice ? 'Finalize' : (_docType == DocumentType.quotation ? 'Save quotation' : 'Save estimate')} · ${Money.format(totals.grandTotalPaise)}',
                ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: emphasize
                ? theme.textTheme.titleLarge
                : theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _finalize() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      CustomerRow? customer;
      if (_customerId != null) {
        customer = await ref
            .read(partiesRepositoryProvider)
            .customerById(_customerId!);
      }
      final input = SaleInput(
        documentType: _docType,
        validDays: int.tryParse(_validDays.text.trim()) ?? 15,
        storeId: _location.storeId,
        godownId: _location.godownId,
        lines: cart.lines.map((line) => line.toInvoiceLine()).toList(),
        saleType: cart.saleType,
        customerId: _customerId,
        customerName: _name.text,
        customerPhone: _phone.text,
        customerAddress: _address.text,
        customerState: customer?.state ?? '',
        invoiceDiscountPaise: cart.invoiceDiscountPaise,
        isGst: cart.isGst,
        amountPaidPaise: cart.amountPaidPaise,
        paymentMethod: _method,
        notes: _notes.text.trim(),
      );
      final repository = ref.read(salesRepositoryProvider);
      final result = _docType == DocumentType.invoice
          ? await repository.finalizeSale(input)
          : await repository.saveEstimate(input);
      if (cart.sourceOrderId != null && _docType == DocumentType.invoice) {
        await ref
            .read(ordersRepositoryProvider)
            .markInvoiced(cart.sourceOrderId!, result.invoiceNumber);
      }
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(recentInvoicesProvider);
      String? printProblem;
      if (_docType == DocumentType.invoice) {
        printProblem = await autoPrintIfEnabled(ref, result.saleId);
      }
      if (!mounted) return;
      if (printProblem != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(printProblem)));
      }
      context.pushReplacement('/invoices/${result.saleId}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('AppFailure', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
