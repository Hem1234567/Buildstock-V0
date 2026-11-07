package com.vijaybalaji.buildstock

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Hosts the Flutter UI and exposes a small `buildstock/printer` channel used
 * for direct ESC/POS printing over Bluetooth (SPP) and USB. Network printing is
 * done entirely in Dart with a raw TCP socket.
 */
class MainActivity : FlutterActivity() {

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingPermissionAction: (() -> Unit)? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listBluetooth" -> withBluetoothPermission(result) {
                        runAsync(result) { listBluetooth() }
                    }

                    "printBluetooth" -> {
                        val address = call.argument<String>("address")
                        val data = call.argument<ByteArray>("data")
                        if (address == null || data == null) {
                            result.error("bad_args", "address and data are required", null)
                        } else {
                            withBluetoothPermission(result) {
                                runAsync(result) {
                                    writeBluetooth(address, data)
                                    true
                                }
                            }
                        }
                    }

                    "listUsb" -> runAsync(result) { listUsb() }

                    "printUsb" -> {
                        val deviceName = call.argument<String>("deviceName")
                        val data = call.argument<ByteArray>("data")
                        if (deviceName == null || data == null) {
                            result.error("bad_args", "deviceName and data are required", null)
                        } else {
                            printUsb(deviceName, data, result)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------ helpers

    private fun <T> runAsync(result: MethodChannel.Result, block: () -> T) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("printer_error", error.message ?: error.toString(), null)
                }
            }
        }
    }

    private fun withBluetoothPermission(result: MethodChannel.Result, action: () -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            action()
            return
        }
        pendingPermissionAction = action
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_BLUETOOTH)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLUETOOTH) return
        val action = pendingPermissionAction
        val result = pendingPermissionResult
        pendingPermissionAction = null
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted && action != null) {
            action()
        } else {
            result?.error(
                "permission_denied",
                "Bluetooth permission was not granted",
                null
            )
        }
    }

    // ---------------------------------------------------------- bluetooth

    @SuppressLint("MissingPermission")
    private fun listBluetooth(): List<Map<String, String>> {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = manager.adapter
            ?: throw IllegalStateException("Bluetooth is not available on this device")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is turned off")
        return adapter.bondedDevices.map { device ->
            mapOf(
                "name" to (device.name ?: device.address),
                "address" to device.address
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeBluetooth(address: String, data: ByteArray) {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = manager.adapter
            ?: throw IllegalStateException("Bluetooth is not available on this device")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is turned off")
        val device = adapter.getRemoteDevice(address)
        adapter.cancelDiscovery()
        val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        try {
            socket.connect()
            val output = socket.outputStream
            var offset = 0
            while (offset < data.size) {
                val count = minOf(BLUETOOTH_CHUNK, data.size - offset)
                output.write(data, offset, count)
                output.flush()
                offset += count
                Thread.sleep(15)
            }
            // Give the printer time to drain its buffer before closing.
            Thread.sleep(400)
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }

    // ---------------------------------------------------------------- usb

    private fun listUsb(): List<Map<String, Any>> {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        return manager.deviceList.values.map { device ->
            mapOf(
                "deviceName" to device.deviceName,
                "name" to (device.productName ?: device.deviceName),
                "vendorId" to device.vendorId,
                "productId" to device.productId
            )
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun printUsb(deviceName: String, data: ByteArray, result: MethodChannel.Result) {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.error("printer_error", "USB printer is not connected", null)
            return
        }
        if (manager.hasPermission(device)) {
            runAsync(result) {
                writeUsb(manager, device, data)
                true
            }
            return
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                try {
                    unregisterReceiver(this)
                } catch (_: Exception) {
                }
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                if (granted) {
                    runAsync(result) {
                        writeUsb(manager, device, data)
                        true
                    }
                } else {
                    result.error("permission_denied", "USB permission was not granted", null)
                }
            }
        }
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val permissionIntent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(ACTION_USB_PERMISSION).setPackage(packageName),
            flags
        )
        manager.requestPermission(device, permissionIntent)
    }

    private fun writeUsb(manager: UsbManager, device: UsbDevice, data: ByteArray) {
        var chosenInterface: UsbInterface? = null
        var chosenEndpoint: UsbEndpoint? = null
        for (i in 0 until device.interfaceCount) {
            val usbInterface = device.getInterface(i)
            for (e in 0 until usbInterface.endpointCount) {
                val endpoint = usbInterface.getEndpoint(e)
                if (endpoint.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    endpoint.direction == UsbConstants.USB_DIR_OUT
                ) {
                    if (chosenEndpoint == null ||
                        usbInterface.interfaceClass == UsbConstants.USB_CLASS_PRINTER
                    ) {
                        chosenInterface = usbInterface
                        chosenEndpoint = endpoint
                    }
                }
            }
        }
        if (chosenInterface == null || chosenEndpoint == null) {
            throw IllegalStateException("This USB device has no printable endpoint")
        }
        val connection = manager.openDevice(device)
            ?: throw IllegalStateException("Could not open the USB printer")
        try {
            if (!connection.claimInterface(chosenInterface, true)) {
                throw IllegalStateException("Could not claim the USB printer interface")
            }
            var offset = 0
            while (offset < data.size) {
                val count = minOf(USB_CHUNK, data.size - offset)
                val written = connection.bulkTransfer(
                    chosenEndpoint,
                    data,
                    offset,
                    count,
                    USB_TIMEOUT_MS
                )
                if (written < 0) throw IllegalStateException("USB transfer failed")
                offset += written
            }
            connection.releaseInterface(chosenInterface)
        } finally {
            connection.close()
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "buildstock/printer"
        private const val REQUEST_BLUETOOTH = 7301
        private const val ACTION_USB_PERMISSION = "com.vijaybalaji.buildstock.USB_PERMISSION"
        private const val BLUETOOTH_CHUNK = 512
        private const val USB_CHUNK = 16384
        private const val USB_TIMEOUT_MS = 10000
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
