import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:buildstock/core/qr/upi_qr.dart';
import 'package:buildstock/core/scanner/invoice_qr.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/widgets/business_image.dart';
import 'package:buildstock/features/invoices/domain/invoice_document.dart';

/// Configurable typography and spacing for the Vijay Balaji Agency document.
/// Values are in logical pixels at the template's design width, so the same
/// template scales cleanly to A4, PDF and thermal renderers.
class InvoiceTemplate {
  const InvoiceTemplate({
    this.pageWidth = 780,
    this.pagePadding = 28,
    this.headingSize = 20,
    this.businessNameSize = 27,
    this.bodySize = 10.5,
    this.smallSize = 9,
    this.tableHeaderSize = 10,
    this.rowHeight = 27,
    this.showReferenceQr = false,
    this.showBankDetails = false,
  });

  final double pageWidth;
  final double pagePadding;
  final double headingSize;
  final double businessNameSize;
  final double bodySize;
  final double smallSize;
  final double tableHeaderSize;
  final double rowHeight;
  final bool showReferenceQr;
  final bool showBankDetails;

  static const standard = InvoiceTemplate();
}

const Color _ink = Color(0xFF111111);
const Color _muted = Color(0xFF5A5A5A);
const Color _paper = Color(0xFFFFFFFF);
const Color _rule = Color(0xFF2A2A2A);

/// The on-screen estimate/bill. This is the reference implementation of the
/// supplied paper format; the PDF renderer uses the same document model.
class InvoiceA4 extends StatelessWidget {
  const InvoiceA4({
    super.key,
    required this.document,
    this.template = InvoiceTemplate.standard,
    this.scale = 1,
  });

  final InvoiceDocument document;
  final InvoiceTemplate template;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final contentWidth = template.pageWidth - template.pagePadding * 2;
    return Container(
      width: template.pageWidth,
      color: _paper,
      padding: EdgeInsets.all(template.pagePadding),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: template.bodySize,
          height: 1.32,
          color: _ink,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(contentWidth),
            const SizedBox(height: 6),
            const Divider(color: _rule, thickness: 1.2, height: 12),
            _documentInfo(),
            const SizedBox(height: 10),
            _buyerBlock(),
            const SizedBox(height: 10),
            _itemsTable(contentWidth),
            const SizedBox(height: 10),
            _totalsSection(contentWidth),
            const SizedBox(height: 12),
            _paymentAndSignature(contentWidth),
            const SizedBox(height: 12),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header(double contentWidth) {
    final logo = businessImage(document.logoRef, fit: BoxFit.contain);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: contentWidth * 0.28,
              child: Text(
                document.heading,
                style: TextStyle(
                  fontSize: template.headingSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final phone in document.seller.allPhones)
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: template.bodySize + 0.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (logo != null)
          SizedBox(height: 52, child: Center(child: logo))
        else
          const SizedBox.shrink(),
        Text(
          document.seller.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: template.businessNameSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'DEALERS IN CEMENT, BRICKS, SAND, JELLY AND GRAVEL',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: template.bodySize, letterSpacing: 0.3),
        ),
        Text(
          'AVAILABLE IN WHOLESALE AND RETAIL',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: template.smallSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          document.seller.address,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: template.bodySize),
        ),
        if (document.seller.gstin.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'GSTIN: ${document.seller.gstin}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: template.smallSize),
          ),
        ],
      ],
    );
  }

  Widget _documentInfo() {
    final base = TextStyle(
      fontFamily: 'Inter',
      fontSize: template.bodySize,
      color: _ink,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'Date: '),
              TextSpan(
                text: AppDate.display(document.date),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'Bill No: '),
              TextSpan(
                text: document.number,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buyerBlock() {
    final lines = <String>[
      if (document.buyer.businessName.isNotEmpty) document.buyer.businessName,
      if (document.buyer.address.isNotEmpty) document.buyer.address,
      if (document.buyer.phone.isNotEmpty) 'Ph: ${document.buyer.phone}',
      if (document.buyer.gstin.isNotEmpty) 'GSTIN: ${document.buyer.gstin}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _rule, width: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TO',
            style: TextStyle(fontSize: 8, letterSpacing: 1, color: _muted),
          ),
          const SizedBox(height: 2),
          Text(
            document.buyer.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          for (final line in lines)
            Text(line, style: TextStyle(fontSize: template.bodySize)),
        ],
      ),
    );
  }

  Widget _itemsTable(double contentWidth) {
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFF1F1F1)),
        children: [
          _cell('S.No', bold: true, align: TextAlign.center),
          _cell('Description', bold: true),
          _cell('Qty', bold: true, align: TextAlign.center),
          _cell('Rate', bold: true, align: TextAlign.right),
          _cell('Amount', bold: true, align: TextAlign.right),
        ],
      ),
    ];

    var index = 0;
    for (final item in document.items) {
      index++;
      rows.add(
        TableRow(
          children: [
            _cell('$index', align: TextAlign.center),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: template.bodySize + 0.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.sku.isNotEmpty ||
                      item.hsnCode.isNotEmpty ||
                      item.unit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        [
                          if (item.sku.isNotEmpty) 'SKU ${item.sku}',
                          if (item.hsnCode.isNotEmpty) 'HSN ${item.hsnCode}',
                          if (item.unit.isNotEmpty) item.unit,
                        ].join('  ·  '),
                        style: TextStyle(
                          fontSize: template.smallSize - 0.5,
                          color: _muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _cell(Quantity.format(item.quantityMilli), align: TextAlign.center),
            _cell(Money.format(item.unitPricePaise), align: TextAlign.right),
            _cell(
              Money.format(item.lineTotalPaise),
              align: TextAlign.right,
              bold: true,
            ),
          ],
        ),
      );
    }

    // Keep the paper proportions even for a single item.
    for (var filler = index; filler < 5; filler++) {
      rows.add(
        TableRow(
          children: [
            _cell(' ', align: TextAlign.center),
            _cell(' '),
            _cell(' ', align: TextAlign.center),
            _cell(' ', align: TextAlign.right),
            _cell(' ', align: TextAlign.right),
          ],
        ),
      );
    }

    return Table(
      columnWidths: {
        0: const FixedColumnWidth(38),
        1: const FlexColumnWidth(),
        2: const FixedColumnWidth(62),
        3: const FixedColumnWidth(84),
        4: const FixedColumnWidth(96),
      },
      border: TableBorder.all(color: _rule, width: 0.6),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  Widget _cell(
    String text, {
    TextAlign align = TextAlign.left,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: template.tableHeaderSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _totalsSection(double contentWidth) {
    final rows = <(String, String, bool)>[
      ('Subtotal', Money.format(document.subtotalPaise), false),
      if (document.discountPaise > 0)
        ('Discount', '- ${Money.format(document.discountPaise)}', false),
      ('Taxable Amount', Money.format(document.taxablePaise), false),
      if (document.isGst && document.cgstPaise > 0)
        ('CGST', Money.format(document.cgstPaise), false),
      if (document.isGst && document.sgstPaise > 0)
        ('SGST', Money.format(document.sgstPaise), false),
      if (document.isGst && document.igstPaise > 0)
        ('IGST', Money.format(document.igstPaise), false),
      if (document.roundOffPaise != 0)
        ('Round Off', Money.format(document.roundOffPaise), false),
      ('Grand Total', Money.format(document.grandTotalPaise), true),
      if (document.amountPaidPaise > 0)
        ('Amount Paid', Money.format(document.amountPaidPaise), false),
      ('Balance Due', Money.format(document.balanceDuePaise), true),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AMOUNT IN WORDS',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  document.amountInWords,
                  style: TextStyle(
                    fontSize: template.bodySize,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (document.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notes: ${document.notes}',
                    style: TextStyle(fontSize: template.smallSize),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          width: contentWidth * 0.42,
          child: Column(
            children: [
              for (final row in rows)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: row.$3 ? _rule : const Color(0xFFDDDDDD),
                        width: row.$3 ? 1 : 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        row.$1,
                        style: TextStyle(
                          fontSize: template.bodySize,
                          fontWeight: row.$3
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      Text(
                        row.$2,
                        style: TextStyle(
                          fontSize: row.$3
                              ? template.bodySize + 1.5
                              : template.bodySize,
                          fontWeight: row.$3
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentAndSignature(double contentWidth) {
    final qrWidget = document.showUpiQr
        ? QrImageView(
            data: UpiQr.paymentUri(
              upiId: document.upiId,
              payeeName: document.upiPayeeName,
              amountPaise: document.balanceDuePaise,
              invoiceNumber: document.number,
              invoiceId: document.id,
            ),
            version: QrVersions.auto,
            size: 92,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: _ink,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: _ink,
            ),
          )
        : null;

    final signature = businessImage(document.signatureRef, fit: BoxFit.contain);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (qrWidget != null)
          SizedBox(
            width: contentWidth * 0.3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                qrWidget,
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Scan to pay with UPI\n${Money.format(document.balanceDuePaise)}',
                    style: TextStyle(fontSize: template.smallSize),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: contentWidth * 0.3,
            child: Text(
              'Payment Mode: ${document.paymentMethodLabel()}',
              style: TextStyle(fontSize: template.bodySize),
            ),
          ),
        const Spacer(),
        if (!document.isCancelled && document.number.isNotEmpty) ...[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: InvoiceQr.encode(document.number),
                version: QrVersions.auto,
                size: 64,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 2),
              Text(
                'Scan to open',
                style: TextStyle(fontSize: template.smallSize - 1),
              ),
            ],
          ),
          const Spacer(),
        ],
        SizedBox(
          width: contentWidth * 0.3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (signature != null)
                SizedBox(height: 42, child: signature)
              else
                const SizedBox(height: 34),
              Container(width: 170, height: 0.8, color: _rule),
              const SizedBox(height: 4),
              Text(
                'Authorized Signature',
                style: TextStyle(fontSize: template.smallSize),
              ),
              if (document.seller.name.isNotEmpty)
                Text(
                  'For ${document.seller.name}',
                  style: TextStyle(
                    fontSize: template.smallSize - 0.5,
                    color: _muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Column(
      children: [
        const Divider(color: Color(0xFFDDDDDD), height: 1, thickness: 0.6),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Goods once sold will not be taken back. Subject to Chennai jurisdiction.',
                style: TextStyle(
                  fontSize: template.smallSize - 0.5,
                  color: _muted,
                ),
              ),
            ),
            if (document.showUpiQr)
              Text(
                'UPI: ${document.upiId}',
                style: TextStyle(
                  fontSize: template.smallSize - 0.5,
                  color: _muted,
                ),
              ),
          ],
        ),
        if (document.isEstimate)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This is an estimate, not a tax invoice.',
              style: TextStyle(
                fontSize: template.smallSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
