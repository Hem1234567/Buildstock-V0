import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/features/deliveries/data/operations_repository.dart';
import 'package:buildstock/features/stores/data/transfer_repository.dart';

/// Lets the user choose which store or godown stock is taken from or added to.
/// With [allowAuto] the first choice means "no specific location": sales then
/// use the largest balances first.
class StockLocationDropdown extends ConsumerWidget {
  const StockLocationDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Stock location',
    this.autoLabel = 'Automatic (largest stock first)',
    this.allowAuto = true,
  });

  final StockLocation value;
  final ValueChanged<StockLocation> onChanged;
  final String label;
  final String autoLabel;
  final bool allowAuto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesStreamProvider).value ?? const <StoreRow>[];
    final godowns =
        ref.watch(godownsStreamProvider(null)).value ?? const <GodownRow>[];
    final options = <DropdownMenuItem<String>>[
      if (allowAuto)
        DropdownMenuItem(
          value: const StockLocation().code,
          child: Text(autoLabel, overflow: TextOverflow.ellipsis),
        ),
      for (final store in stores)
        DropdownMenuItem(
          value: StockLocation(storeId: store.id).code,
          child: Text('Store: ${store.name}', overflow: TextOverflow.ellipsis),
        ),
      for (final godown in godowns)
        DropdownMenuItem(
          value: StockLocation(
            storeId: godown.storeId,
            godownId: godown.id,
          ).code,
          child: Text(
            'Godown: ${godown.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    final codes = options.map((item) => item.value).toSet();
    final current = codes.contains(value.code)
        ? value.code
        : (options.isEmpty ? null : options.first.value);
    return DropdownButtonFormField<String>(
      key: ValueKey('${value.code}-${options.length}'),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options,
      onChanged: (code) => onChanged(StockLocation.parse(code)),
    );
  }
}
