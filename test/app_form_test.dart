import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/core/widgets/app_form.dart';

void main() {
  testWidgets('AppFormScreen renders all declared fields and the save button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppFormScreen(
          title: 'Add product',
          saveLabel: 'Save product',
          fields: const [
            AppField(key: 'name', label: 'Product name', required: true),
            AppField(key: 'sku', label: 'SKU'),
            AppField(
              key: 'price',
              label: 'Retail price',
              type: AppFieldType.money,
            ),
          ],
          onSave: (_) async {},
        ),
      ),
    );

    expect(find.text('Product name'), findsOneWidget);
    expect(find.text('SKU'), findsOneWidget);
    expect(find.text('Retail price'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Save product'), findsOneWidget);
  });

  testWidgets('AppFormScreen lays out on a phone-sized viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppFormScreen(
          title: 'Add customer',
          fields: const [
            AppField(key: 'name', label: 'Customer name', required: true),
            AppField(key: 'phone', label: 'Phone', type: AppFieldType.phone),
            AppField(
              key: 'notes',
              label: 'Notes',
              type: AppFieldType.multiline,
            ),
          ],
          onSave: (_) async {},
        ),
      ),
    );

    expect(find.text('Customer name'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
