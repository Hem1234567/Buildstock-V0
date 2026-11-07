import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/scanner/barcode_scanner_screen.dart';
import 'package:buildstock/core/scanner/invoice_qr.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/json.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/deliveries/data/operations_repository.dart';
import 'package:buildstock/features/invoices/data/auto_print.dart';
import 'package:buildstock/features/invoices/data/invoice_exporter.dart';
import 'package:buildstock/features/invoices/data/invoice_pdf.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/features/invoices/domain/invoice_document.dart';
import 'package:buildstock/features/invoices/presentation/invoice_a4.dart';
import 'package:buildstock/features/sales/data/sales_repository.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';
import 'package:buildstock/features/stores/presentation/stock_location_picker.dart';

class InvoiceHistoryScreen extends ConsumerStatefulWidget {
  const InvoiceHistoryScreen({super.key, this.documentType = 'invoice'});

  final String documentType;

  @override
  ConsumerState<InvoiceHistoryScreen> createState() =>
      _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends ConsumerState<InvoiceHistoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _status = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(documentListProvider(_query));
    final filtered = invoices.whenData(
      (rows) => rows
          .where((row) => row.documentType == widget.documentType)
          .where((row) => _status.isEmpty || row.documentStatus == _status)
          .toList(),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.documentType) {
          DocumentType.estimate => 'Estimates',
          DocumentType.quotation => 'Quotations',
          _ => 'Invoices',
        }),
        actions: [
          IconButton(
            tooltip: 'Scan bill QR',
            onPressed: _scanToOpen,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Find bill in cloud',
            onPressed: _findInCloud,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchField(
              controller: _search,
              hint: 'Search bill number',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final entry in const [
                  ('', 'All'),
                  (DocumentStatus.finalized, 'Finalized'),
                  (DocumentStatus.cancelled, 'Cancelled'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(entry.$2),
                      selected: _status == entry.$1,
                      onSelected: (_) => setState(() => _status = entry.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: filtered,
              builder: (rows) {
                if (rows.isEmpty) {
                  return EmptyState(
                    title: 'No documents found',
                    message: 'Create an invoice from Sales. Finalized documents are never edited; corrections use returns or cancellation.',
                    icon: Icons.receipt_long_outlined,
                    actionLabel: 'Open Sales',
                    onAction: () => context.go('/sales'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final invoice = rows[index];
                    final buyer = Json.decodeMap(invoice.buyerSnapshotJson);
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push('/invoices/${invoice.id}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  invoice.invoiceNumber,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${buyer['name'] ?? 'Walk-in'} · ${AppDate.display(invoice.invoiceDate)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.format(invoice.grandTotalPaise),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              StatusPill.document(invoice.documentStatus),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Scans the QR printed on a bill and opens that invoice.
  Future<void> _scanToOpen() async {
    final raw = await BarcodeScannerScreen.open(
      context,
      title: 'Scan bill QR',
      hint: 'Scan the QR code printed on a bill',
      qrOnly: true,
    );
    if (raw == null || !mounted) return;
    final payload = InvoiceQr.parse(raw);
    if (payload == null) {
      showActionMessage(context, 'This is not a BuildStock bill QR code');
      return;
    }
    await openInvoiceByNumber(context, ref, payload.invoiceNumber);
  }

  Future<void> _findInCloud() async {
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find invoice in cloud'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Bill number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Find'),
          ),
        ],
      ),
    );
    if (number == null || number.isEmpty) return;
    try {
      final local = await ref
          .read(salesRepositoryProvider)
          .saleByNumber(number);
      if (local != null) {
        if (mounted) context.push('/invoices/${local.id}');
        return;
      }
      final id = await ref
          .read(salesRepositoryProvider)
          .fetchInvoiceFromCloud(number);
      if (!mounted) return;
      if (id == null) {
        showActionMessage(context, 'Invoice not found in the cloud');
      } else {
        ref.invalidate(invoiceListProvider);
        context.push('/invoices/$id');
      }
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }
}

class InvoicePreviewScreen extends ConsumerStatefulWidget {
  const InvoicePreviewScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<InvoicePreviewScreen> createState() =>
      _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends ConsumerState<InvoicePreviewScreen> {
  final _previewKey = GlobalKey();
  final _exporter = const InvoiceExporter();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final sale = ref.watch(saleProvider(widget.saleId));
    final items = ref.watch(saleItemsProvider(widget.saleId));
    final payments = ref.watch(invoicePaymentsProvider(widget.saleId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice'),
        actions: [
          IconButton(
            tooltip: 'Print',
            onPressed: _busy ? null : () => _withDocument(_print),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Share PDF',
            onPressed: _busy ? null : () => _withDocument(_share),
            icon: const Icon(Icons.ios_share),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'pdf':
                  await _withDocument(_savePdf);
                case 'image':
                  await _saveImage();
                case 'thermal58':
                  await _withDocument(
                    (doc) => _saveThermal(doc, ThermalWidth.mm58),
                  );
                case 'thermal80':
                  await _withDocument(
                    (doc) => _saveThermal(doc, ThermalWidth.mm80),
                  );
                case 'payment':
                  await _recordPayment();
                case 'delivery':
                  await _createDelivery();
                case 'convert':
                  await _convertToInvoice();
                case 'cancel':
                  await _cancel();
              }
            },
            itemBuilder: (context) => [
              if (sale.value != null &&
                  sale.value!.documentType != DocumentType.invoice &&
                  sale.value!.documentStatus == DocumentStatus.finalized &&
                  sale.value!.convertedInvoiceId == null)
                const PopupMenuItem(
                  value: 'convert',
                  child: Text('Convert to invoice'),
                ),
              const PopupMenuItem(value: 'pdf', child: Text('Download PDF')),
              const PopupMenuItem(
                value: 'image',
                child: Text('Download image'),
              ),
              const PopupMenuItem(
                value: 'thermal58',
                child: Text('Thermal 58 mm'),
              ),
              const PopupMenuItem(
                value: 'thermal80',
                child: Text('Thermal 80 mm'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'payment',
                child: Text('Record payment'),
              ),
              const PopupMenuItem(
                value: 'delivery',
                child: Text('Create delivery'),
              ),
              const PopupMenuItem(
                value: 'cancel',
                child: Text('Cancel invoice'),
              ),
            ],
          ),
        ],
      ),
      body: AsyncView(
        value: sale,
        builder: (saleRow) {
          if (saleRow == null) {
            return const EmptyState(
              title: 'Invoice not found',
              message: 'This bill is not available on this device. Use the cloud search on the invoice history screen.',
              icon: Icons.receipt_long_outlined,
            );
          }
          return AsyncView(
            value: items,
            builder: (itemRows) {
              final document = InvoiceDocument.fromRows(saleRow, itemRows);
              if (document == null) {
                return const EmptyState(
                  title: 'Invoice data is incomplete',
                  message: 'The saved seller or buyer snapshot is missing, so a document cannot be generated. No fake invoice is created.',
                  icon: Icons.error_outline,
                );
              }
              return Column(
                children: [
                  if (document.isCancelled)
                    Container(
                      width: double.infinity,
                      color: AppColors.dangerSoft,
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'CANCELLED · ${document.number}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: payments.maybeWhen(
                      data: (rows) {
                        final paid = rows.fold<int>(
                          0,
                          (sum, row) => sum + row.amountPaise,
                        );
                        final balance = document.grandTotalPaise - paid;
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Paid ${Money.format(paid)} · Balance ${Money.format(balance < 0 ? 0 : balance)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (balance > 0 && !document.isCancelled)
                              TextButton(
                                onPressed: _recordPayment,
                                child: const Text('Add payment'),
                              ),
                          ],
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ),
                  Expanded(
                    child: InteractiveViewer(
                      minScale: 0.4,
                      maxScale: 4,
                      boundaryMargin: const EdgeInsets.all(80),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            child: RepaintBoundary(
                              key: _previewKey,
                              child: InvoiceA4(document: document),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _withDocument(
    Future<void> Function(InvoiceDocument document) action,
  ) async {
    final sale = await ref
        .read(salesRepositoryProvider)
        .saleById(widget.saleId);
    if (sale == null) return;
    final items = await ref
        .read(salesRepositoryProvider)
        .itemsForSale(widget.saleId);
    final document = InvoiceDocument.fromRows(sale, items);
    if (document == null) {
      if (mounted) showActionMessage(context, 'Invoice data is incomplete');
      return;
    }
    setState(() => _busy = true);
    try {
      await action(document);
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(InvoiceDocument document) async {
    final settings = await loadPrintSettings(ref);
    await _exporter.printWithSettings(document, settings);
  }

  /// Converts an estimate or quotation into a tax invoice.
  Future<void> _convertToInvoice() async {
    final sale = await ref
        .read(salesRepositoryProvider)
        .saleById(widget.saleId);
    if (sale == null || !mounted) return;
    var location = const StockLocation();
    final paid = TextEditingController();
    var method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Convert ${sale.invoiceNumber} to invoice'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StockLocationDropdown(
                  value: location,
                  label: 'Take stock from',
                  onChanged: (value) => setLocal(() => location = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: paid,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount received now (optional)',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
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
                    DropdownMenuItem(value: 'credit', child: Text('Credit')),
                  ],
                  onChanged: (value) =>
                      setLocal(() => method = value ?? method),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create invoice'),
            ),
          ],
        ),
      ),
    );
    final amount = Money.tryParseRupees(paid.text) ?? 0;
    paid.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(salesRepositoryProvider)
          .convertToInvoice(
            widget.saleId,
            storeId: location.storeId,
            godownId: location.godownId,
            amountPaidPaise: amount,
            paymentMethod: method,
          );
      ref.invalidate(recentInvoicesProvider);
      if (mounted) context.pushReplacement('/invoices/${result.saleId}');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(InvoiceDocument document) => _exporter.sharePdf(document);

  Future<void> _savePdf(InvoiceDocument document) async {
    final path = await _exporter.savePdf(document);
    if (mounted && path != null) showActionMessage(context, 'Saved to $path');
  }

  Future<void> _saveThermal(
    InvoiceDocument document,
    ThermalWidth width,
  ) async {
    final path = await _exporter.saveThermal(document, width);
    if (mounted && path != null) showActionMessage(context, 'Saved to $path');
  }

  Future<void> _saveImage() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final sale = await ref
          .read(salesRepositoryProvider)
          .saleById(widget.saleId);
      final name = sale?.invoiceNumber.replaceAll('/', '-') ?? 'invoice';
      final path = await _exporter.savePng(name, data.buffer.asUint8List());
      if (mounted && path != null) {
        showActionMessage(context, 'Saved to $path');
      }
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordPayment() async {
    final sale = await ref
        .read(salesRepositoryProvider)
        .saleById(widget.saleId);
    if (sale == null) return;
    final payments = await ref
        .read(salesRepositoryProvider)
        .paymentsForInvoice(widget.saleId);
    final paid = payments.fold<int>(0, (sum, row) => sum + row.amountPaise);
    final balance = sale.grandTotalPaise - paid;
    if (balance <= 0) {
      if (mounted) showActionMessage(context, 'This invoice is fully paid');
      return;
    }
    final amount = TextEditingController(
      text: (balance / 100).toStringAsFixed(2),
    );
    var method = 'cash';
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setDialogState(() => method = value ?? method),
                decoration: const InputDecoration(labelText: 'Method'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final paise = Money.tryParseRupees(amount.text) ?? 0;
    if (paise <= 0) return;
    try {
      final buyer = Json.decodeMap(sale.buyerSnapshotJson);
      await ref
          .read(salesRepositoryProvider)
          .recordPayment(
            partyType: sale.customerId == null
                ? PartyType.other
                : PartyType.customer,
            partyId: sale.customerId,
            partyName: buyer['name']?.toString() ?? '',
            amountPaise: paise,
            method: method,
            invoiceId: sale.id,
            reference: sale.invoiceNumber,
          );
      ref.invalidate(invoicePaymentsProvider(widget.saleId));
      if (mounted) showActionMessage(context, 'Payment recorded');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }

  Future<void> _createDelivery() async {
    try {
      await ref
          .read(operationsRepositoryProvider)
          .createDeliveryFromInvoice(invoiceId: widget.saleId);
      ref.invalidate(deliveriesStreamProvider(''));
      if (mounted) showActionMessage(context, 'Delivery created');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The invoice stays in history as cancelled, stock is returned, '
              'and the original document is never erased. Record a reason.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep invoice'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel invoice'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(salesRepositoryProvider)
          .cancelInvoice(widget.saleId, reason.text.trim());
      ref.invalidate(saleProvider(widget.saleId));
      ref.invalidate(saleItemsProvider(widget.saleId));
      ref.invalidate(invoiceListProvider);
      if (mounted) showActionMessage(context, 'Invoice cancelled');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }
}

/// Opens an invoice by its number, checking this device first and then the
/// cloud. Shows a message when it can not be found.
Future<void> openInvoiceByNumber(
  BuildContext context,
  WidgetRef ref,
  String number,
) async {
  try {
    final repository = ref.read(salesRepositoryProvider);
    final local = await repository.saleByNumber(number);
    if (local != null) {
      if (context.mounted) context.push('/invoices/${local.id}');
      return;
    }
    final id = await repository.fetchInvoiceFromCloud(number);
    if (!context.mounted) return;
    if (id == null) {
      showActionMessage(context, 'Bill $number was not found');
    } else {
      ref.invalidate(invoiceListProvider);
      ref.invalidate(documentListProvider);
      context.push('/invoices/$id');
    }
  } catch (error) {
    if (context.mounted) showActionMessage(context, error.toString());
  }
}
