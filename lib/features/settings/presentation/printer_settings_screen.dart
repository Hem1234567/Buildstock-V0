import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/printing/thermal_printer_service.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/business/data/business_repository.dart';

/// Printer and paper settings: A4 / 58 mm / 80 mm, and how the bill reaches
/// the printer (Android print dialog, network, Bluetooth or USB).
class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9100');
  PrinterConnection _connection = PrinterConnection.system;
  String _paper = 'a4';
  int _copies = 1;
  bool _auto = false;
  String _btAddress = '';
  String _btName = '';
  String _usbDevice = '';
  String _usbName = '';
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final map = await ref
        .read(businessRepositoryProvider)
        .watchSettings()
        .first;
    final settings = PrintSettings.fromMap(map);
    if (!mounted) return;
    setState(() {
      _connection = settings.connection;
      _paper = settings.paper;
      _copies = settings.copies;
      _auto = settings.autoPrint;
      _host.text = settings.host;
      _port.text = '${settings.port}';
      _btAddress = settings.bluetoothAddress;
      _btName = settings.bluetoothName;
      _usbDevice = settings.usbDevice;
      _usbName = settings.usbName;
      _loaded = true;
    });
  }

  PrintSettings get _current => PrintSettings(
    connection: _connection,
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 9100,
    bluetoothAddress: _btAddress,
    bluetoothName: _btName,
    usbDevice: _usbDevice,
    usbName: _usbName,
    paper: _paper,
    copies: _copies,
    autoPrint: _auto,
  );

  Future<void> _save() async {
    final repository = ref.read(businessRepositoryProvider);
    final values = <String, String>{
      PrinterSettingKeys.connection: _connection.name,
      PrinterSettingKeys.host: _host.text.trim(),
      PrinterSettingKeys.port: '${int.tryParse(_port.text.trim()) ?? 9100}',
      PrinterSettingKeys.bluetoothAddress: _btAddress,
      PrinterSettingKeys.bluetoothName: _btName,
      PrinterSettingKeys.usbDevice: _usbDevice,
      PrinterSettingKeys.usbName: _usbName,
      PrinterSettingKeys.paper: _paper,
      PrinterSettingKeys.copies: '$_copies',
      PrinterSettingKeys.autoPrint: '$_auto',
      PrinterSettingKeys.printerName: _current.description,
    };
    for (final entry in values.entries) {
      await repository.putSetting(entry.key, entry.value);
    }
    ref.invalidate(appSettingsProvider);
    if (mounted) showActionMessage(context, 'Print settings saved');
  }

  Future<void> _pickDevice(PrinterConnection kind) async {
    setState(() => _busy = true);
    try {
      const service = ThermalPrinterService();
      final devices = kind == PrinterConnection.bluetooth
          ? await service.bluetoothDevices()
          : await service.usbDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        showActionMessage(
          context,
          kind == PrinterConnection.bluetooth
              ? 'No paired Bluetooth printers. Pair the printer in Android settings first.'
              : 'No USB device found. Connect the printer with an OTG cable.',
        );
        return;
      }
      final chosen = await showModalBottomSheet<PrinterDevice>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final device in devices)
                ListTile(
                  leading: Icon(
                    kind == PrinterConnection.bluetooth
                        ? Icons.bluetooth
                        : Icons.usb,
                  ),
                  title: Text(device.name),
                  subtitle: Text(device.id),
                  onTap: () => Navigator.pop(context, device),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      setState(() {
        if (kind == PrinterConnection.bluetooth) {
          _btAddress = chosen.id;
          _btName = chosen.name;
        } else {
          _usbDevice = chosen.id;
          _usbName = chosen.name;
        }
      });
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await const ThermalPrinterService().testPrint(_current);
      if (mounted) showActionMessage(context, 'Test page sent to the printer');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Printer & paper')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Printer & paper')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SectionCard(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _paper,
                  decoration: const InputDecoration(labelText: 'Default paper'),
                  items: const [
                    DropdownMenuItem(value: 'a4', child: Text('A4')),
                    DropdownMenuItem(value: '58', child: Text('Thermal 58 mm')),
                    DropdownMenuItem(value: '80', child: Text('Thermal 80 mm')),
                  ],
                  onChanged: (value) =>
                      setState(() => _paper = value ?? _paper),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _copies,
                  decoration: const InputDecoration(labelText: 'Copies'),
                  items: [
                    for (var count = 1; count <= 5; count++)
                      DropdownMenuItem(value: count, child: Text('$count')),
                  ],
                  onChanged: (value) =>
                      setState(() => _copies = value ?? _copies),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto print after finalizing'),
                  subtitle: const Text(
                    'If disabled, you choose when to print from the invoice.',
                  ),
                  value: _auto,
                  onChanged: (value) => setState(() => _auto = value),
                  activeTrackColor: AppColors.accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'How to print'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<PrinterConnection>(
                  initialValue: _connection,
                  decoration: const InputDecoration(labelText: 'Connection'),
                  items: const [
                    DropdownMenuItem(
                      value: PrinterConnection.system,
                      child: Text('Android print dialog'),
                    ),
                    DropdownMenuItem(
                      value: PrinterConnection.network,
                      child: Text('Network / Wi-Fi (direct)'),
                    ),
                    DropdownMenuItem(
                      value: PrinterConnection.bluetooth,
                      child: Text('Bluetooth (direct)'),
                    ),
                    DropdownMenuItem(
                      value: PrinterConnection.usb,
                      child: Text('USB (direct)'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _connection = value ?? _connection),
                ),
                const SizedBox(height: 12),
                if (_connection == PrinterConnection.system)
                  Text(
                    'Bills open the standard Android print dialog. Use it for '
                    'A4 printers and any printer with an Android print service.',
                    style: theme.textTheme.bodySmall,
                  ),
                if (_connection != PrinterConnection.system && _paper == 'a4')
                  Text(
                    'Direct printing sends thermal receipts. Choose 58 mm or '
                    '80 mm paper above; A4 bills still use the print dialog.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                if (_connection == PrinterConnection.network) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _host,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Printer IP address',
                            hintText: '192.168.1.50',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_connection == PrinterConnection.bluetooth) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      _btAddress.isEmpty
                          ? 'No printer selected'
                          : (_btName.isEmpty ? _btAddress : _btName),
                    ),
                    subtitle: const Text('Choose from paired devices'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () => _pickDevice(PrinterConnection.bluetooth),
                  ),
                ],
                if (_connection == PrinterConnection.usb) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.usb),
                    title: Text(
                      _usbDevice.isEmpty
                          ? 'No printer selected'
                          : (_usbName.isEmpty ? _usbDevice : _usbName),
                    ),
                    subtitle: const Text('Choose a connected USB printer'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () => _pickDevice(PrinterConnection.usb),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || !_current.isDirect ? null : _test,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Test print'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
