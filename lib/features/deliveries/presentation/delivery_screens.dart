import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/media/image_service.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/json.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/deliveries/data/operations_repository.dart';
import 'package:buildstock/features/sales/data/sales_repository.dart';
import 'package:buildstock/features/staff/data/workforce_repository.dart';

class DeliveryListScreen extends ConsumerStatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  ConsumerState<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends ConsumerState<DeliveryListScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final deliveries = ref.watch(deliveriesStreamProvider(_status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) => setState(() => _status = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: '', child: Text('All')),
              PopupMenuItem(value: 'pending', child: Text('Pending')),
              PopupMenuItem(value: 'assigned', child: Text('Assigned')),
              PopupMenuItem(value: 'in_transit', child: Text('In transit')),
              PopupMenuItem(
                value: 'partially_delivered',
                child: Text('Partially delivered'),
              ),
              PopupMenuItem(value: 'delivered', child: Text('Delivered')),
              PopupMenuItem(value: 'failed', child: Text('Failed')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFromInvoice,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: AsyncView(
        value: deliveries,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No deliveries',
              message: 'Create a delivery from a finalized invoice, assign a driver and record proof of delivery.',
              icon: Icons.delivery_dining_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final delivery = rows[index];
              return SectionCard(
                padding: const EdgeInsets.all(14),
                onTap: () => _manage(delivery),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${delivery.deliveryNumber} · ${delivery.customerName}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusPill(
                          label: delivery.status.replaceAll('_', ' '),
                          color: delivery.status == 'delivered'
                              ? AppColors.success
                              : AppColors.info,
                          background: delivery.status == 'delivered'
                              ? AppColors.successSoft
                              : AppColors.infoSoft,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${delivery.invoiceNumber} · ${AppDate.display(delivery.deliveryDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (delivery.driverName.isNotEmpty)
                      Text(
                        'Driver: ${delivery.driverName}${delivery.vehicleNumber.isEmpty ? '' : ' · ${delivery.vehicleNumber}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (delivery.deliveryChargePaise > 0)
                      Text(
                        'Charge ${Money.format(delivery.deliveryChargePaise)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createFromInvoice() async {
    final invoices = ref.read(invoiceListProvider('')).value ?? const [];
    final finalized = invoices
        .where((invoice) => invoice.documentStatus == DocumentStatus.finalized)
        .toList();
    if (finalized.isEmpty) {
      showActionMessage(context, 'Finalize an invoice first');
      return;
    }
    var invoiceId = finalized.first.id;
    String? driverId;
    final drivers = ref.read(driversStreamProvider('')).value ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: StatefulBuilder(
          builder: (context, setModalState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create delivery',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: invoiceId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Invoice'),
                items: finalized
                    .map(
                      (invoice) => DropdownMenuItem(
                        value: invoice.id,
                        child: Text(
                          '${invoice.invoiceNumber} · ${Money.format(invoice.grandTotalPaise)}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setModalState(() => invoiceId = value ?? invoiceId),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: driverId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Driver'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Assign later'),
                  ),
                  for (final driver in drivers)
                    DropdownMenuItem<String?>(
                      value: driver.id,
                      child: Text(driver.fullName),
                    ),
                ],
                onChanged: (value) => setModalState(() => driverId = value),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(operationsRepositoryProvider)
                        .createDeliveryFromInvoice(
                          invoiceId: invoiceId,
                          driverId: driverId,
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (error) {
                    if (context.mounted) {
                      showActionMessage(context, error.toString());
                    }
                  }
                },
                child: const Text('Create delivery'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manage(DeliveryRow delivery) async {
    final drivers = ref.read(driversStreamProvider('')).value ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(delivery.deliveryNumber),
              subtitle: Text(delivery.deliveryAddress),
            ),
            const Divider(),
            for (final status in DeliveryStatus.all)
              if (status != delivery.status)
                ListTile(
                  leading: const Icon(Icons.circle_outlined, size: 16),
                  title: Text(status.replaceAll('_', ' ')),
                  onTap: () async {
                    try {
                      await ref
                          .read(operationsRepositoryProvider)
                          .updateDeliveryStatus(
                            deliveryId: delivery.id,
                            status: status,
                          );
                      if (context.mounted) Navigator.pop(context);
                    } catch (error) {
                      if (context.mounted) {
                        showActionMessage(context, error.toString());
                      }
                    }
                  },
                ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Add proof of delivery photo'),
              subtitle: Text(
                '${Json.decodeList(delivery.proofImageRefs).length} photo(s) saved',
              ),
              onTap: () async {
                Navigator.pop(context);
                await _addProof(delivery);
              },
            ),
            if (delivery.driverId == null && drivers.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Assign driver'),
                onTap: () async {
                  Navigator.pop(context);
                  await _assignDriver(delivery, drivers);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addProof(DeliveryRow delivery) async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      final image = await ref
          .read(imageServiceProvider)
          .pick(
            source: source,
            ownerType: 'delivery',
            role: 'proof',
            ownerId: delivery.id,
          );
      if (image == null) return;
      await ref
          .read(operationsRepositoryProvider)
          .addDeliveryProof(deliveryId: delivery.id, imageRef: image.path);
      if (mounted) showActionMessage(context, 'Proof photo saved');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }

  Future<void> _assignDriver(
    DeliveryRow delivery,
    List<DriverRow> drivers,
  ) async {
    String driverId = drivers.first.id;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign driver'),
        content: DropdownButtonFormField<String>(
          initialValue: driverId,
          items: drivers
              .map(
                (driver) => DropdownMenuItem(
                  value: driver.id,
                  child: Text(driver.fullName),
                ),
              )
              .toList(),
          onChanged: (value) => driverId = value ?? driverId,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(operationsRepositoryProvider)
                    .assignDelivery(
                      deliveryId: delivery.id,
                      driverId: driverId,
                    );
                if (context.mounted) {
                  showActionMessage(context, 'Driver assigned');
                }
              } catch (error) {
                if (context.mounted) {
                  showActionMessage(context, error.toString());
                }
              }
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }
}
