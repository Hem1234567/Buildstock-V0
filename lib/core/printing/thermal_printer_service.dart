import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import 'package:buildstock/core/printing/escpos.dart';

enum PrinterConnection { system, network, bluetooth, usb }

abstract final class PrinterSettingKeys {
  static const connection = 'printer_connection';
  static const host = 'printer_host';
  static const port = 'printer_port';
  static const bluetoothAddress = 'printer_bt_address';
  static const bluetoothName = 'printer_bt_name';
  static const usbDevice = 'printer_usb_device';
  static const usbName = 'printer_usb_name';
  static const paper = 'printer_paper';
  static const copies = 'printer_copies';
  static const autoPrint = 'printer_auto';
  static const printerName = 'printer_name';
}

class PrinterDevice {
  const PrinterDevice({
    required this.id,
    required this.name,
    required this.connection,
  });

  final String id;
  final String name;
  final PrinterConnection connection;
}

/// Printer choices saved in settings.
class PrintSettings {
  const PrintSettings({
    this.connection = PrinterConnection.system,
    this.host = '',
    this.port = 9100,
    this.bluetoothAddress = '',
    this.bluetoothName = '',
    this.usbDevice = '',
    this.usbName = '',
    this.paper = 'a4',
    this.copies = 1,
    this.autoPrint = false,
  });

  final PrinterConnection connection;
  final String host;
  final int port;
  final String bluetoothAddress;
  final String bluetoothName;
  final String usbDevice;
  final String usbName;

  /// `a4`, `58` or `80`.
  final String paper;
  final int copies;
  final bool autoPrint;

  factory PrintSettings.fromMap(Map<String, String> map) {
    final connection = PrinterConnection.values.firstWhere(
      (value) => value.name == map[PrinterSettingKeys.connection],
      orElse: () => PrinterConnection.system,
    );
    return PrintSettings(
      connection: connection,
      host: map[PrinterSettingKeys.host] ?? '',
      port: int.tryParse(map[PrinterSettingKeys.port] ?? '') ?? 9100,
      bluetoothAddress: map[PrinterSettingKeys.bluetoothAddress] ?? '',
      bluetoothName: map[PrinterSettingKeys.bluetoothName] ?? '',
      usbDevice: map[PrinterSettingKeys.usbDevice] ?? '',
      usbName: map[PrinterSettingKeys.usbName] ?? '',
      paper: map[PrinterSettingKeys.paper] ?? 'a4',
      copies: (int.tryParse(map[PrinterSettingKeys.copies] ?? '') ?? 1).clamp(
        1,
        5,
      ),
      autoPrint: map[PrinterSettingKeys.autoPrint] == 'true',
    );
  }

  bool get isThermalPaper => paper == '58' || paper == '80';

  /// Printable width in dots at 203 dpi.
  int get dotWidth => paper == '58' ? 384 : 576;

  /// True when a direct (non dialog) connection is chosen and complete.
  bool get isDirect => switch (connection) {
    PrinterConnection.system => false,
    PrinterConnection.network => host.trim().isNotEmpty,
    PrinterConnection.bluetooth => bluetoothAddress.isNotEmpty,
    PrinterConnection.usb => usbDevice.isNotEmpty,
  };

  String get description => switch (connection) {
    PrinterConnection.system => 'Android print dialog',
    PrinterConnection.network => 'Network printer $host:$port',
    PrinterConnection.bluetooth =>
      'Bluetooth printer ${bluetoothName.isEmpty ? bluetoothAddress : bluetoothName}',
    PrinterConnection.usb =>
      'USB printer ${usbName.isEmpty ? usbDevice : usbName}',
  };
}

class PrinterException implements Exception {
  const PrinterException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sends ESC/POS data straight to a thermal printer, without the Android print
/// dialog. Network printing uses a TCP socket (port 9100); Bluetooth (SPP) and
/// USB use the native `buildstock/printer` channel in MainActivity.
class ThermalPrinterService {
  const ThermalPrinterService();

  static const MethodChannel _channel = MethodChannel('buildstock/printer');

  Future<List<PrinterDevice>> bluetoothDevices() async {
    try {
      final result = await _channel.invokeListMethod<Map>('listBluetooth');
      return [
        for (final item in result ?? const <Map>[])
          PrinterDevice(
            id: item['address'].toString(),
            name: item['name'].toString(),
            connection: PrinterConnection.bluetooth,
          ),
      ];
    } on PlatformException catch (error) {
      throw PrinterException(
        error.message ?? 'Could not list Bluetooth printers',
      );
    } on MissingPluginException {
      throw const PrinterException('Bluetooth printing is not available here');
    }
  }

  Future<List<PrinterDevice>> usbDevices() async {
    try {
      final result = await _channel.invokeListMethod<Map>('listUsb');
      return [
        for (final item in result ?? const <Map>[])
          PrinterDevice(
            id: item['deviceName'].toString(),
            name: item['name'].toString(),
            connection: PrinterConnection.usb,
          ),
      ];
    } on PlatformException catch (error) {
      throw PrinterException(error.message ?? 'Could not list USB printers');
    } on MissingPluginException {
      throw const PrinterException('USB printing is not available here');
    }
  }

  /// Sends raw bytes using the connection in [settings].
  Future<void> send(PrintSettings settings, Uint8List data) async {
    switch (settings.connection) {
      case PrinterConnection.system:
        throw const PrinterException(
          'Choose a network, Bluetooth or USB printer in Printer settings.',
        );
      case PrinterConnection.network:
        await _sendNetwork(settings.host.trim(), settings.port, data);
      case PrinterConnection.bluetooth:
        await _invoke('printBluetooth', {
          'address': settings.bluetoothAddress,
          'data': data,
        });
      case PrinterConnection.usb:
        await _invoke('printUsb', {
          'deviceName': settings.usbDevice,
          'data': data,
        });
    }
  }

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } on PlatformException catch (error) {
      throw PrinterException(error.message ?? 'The printer reported an error');
    } on MissingPluginException {
      throw const PrinterException('Direct printing is not available here');
    }
  }

  Future<void> _sendNetwork(String host, int port, Uint8List data) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 6),
      );
      socket.add(data);
      await socket.flush();
      await socket.close();
    } on SocketException catch (error) {
      throw PrinterException(
        'Could not reach the printer at $host:$port (${error.message})',
      );
    } on TimeoutException {
      throw PrinterException('The printer at $host:$port did not respond');
    } finally {
      socket?.destroy();
    }
  }

  /// Renders a PDF to black-and-white pages sized for the printer.
  Future<List<MonoBitmap>> rasterize(
    Uint8List pdfBytes, {
    required int dotWidth,
  }) async {
    final pages = <MonoBitmap>[];
    await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
      pages.add(
        MonoBitmap.fromRgba(
          page.pixels,
          page.width,
          page.height,
          targetWidth: dotWidth,
        ),
      );
    }
    if (pages.isEmpty) {
      throw const PrinterException('Nothing to print');
    }
    return pages;
  }

  /// Prints a thermal-width PDF through the configured direct connection.
  Future<void> printPdf(PrintSettings settings, Uint8List pdfBytes) async {
    final pages = await rasterize(pdfBytes, dotWidth: settings.dotWidth);
    await send(settings, EscPos.job(pages, copies: settings.copies));
  }

  Future<void> testPrint(PrintSettings settings) {
    return send(
      settings,
      EscPos.testSlip('BuildStock', [
        'Printer test',
        settings.description,
        'Paper: ${settings.paper == 'a4' ? 'A4' : '${settings.paper} mm'}',
        DateTime.now().toIso8601String().substring(0, 19),
        'If you can read this, printing works.',
      ]),
    );
  }
}
