// lib/services/network/ble_client.dart
//
// BLE GATT client for connecting to Frameon devices over Bluetooth Low Energy.
// Requires flutter_blue_plus package on mobile platforms.

import 'dart:async';
import 'dart:typed_data';

import '../serial/serial_service.dart';

/// Stub implementation of BLE client for desktop platforms.
/// Mobile platforms should use flutter_blue_plus or flutter_ble libraries.
class BLEClient {
  final String deviceId;
  final String deviceName;

  BLEClient({
    required this.deviceId,
    required this.deviceName,
  });

  bool get isConnected => false;

  Stream<DeviceEvent> get deviceEvents =>
      Stream.empty();

  /// Connect to the BLE device.
  Future<void> connect({int timeoutSecs = 10}) async {
    throw UnsupportedError(
      'BLE is not supported on this platform. '
      'Please use mobile app for BLE functionality.',
    );
  }

  /// Disconnect from the BLE device.
  Future<void> disconnect() async {}

  /// Send a packet to the device.
  Future<int> send(Uint8List data) async {
    throw UnsupportedError('BLE not supported on this platform');
  }

  /// Read response byte from device.
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    throw UnsupportedError('BLE not supported on this platform');
  }
}

/// BLE device info returned by scanner.
class BLEDeviceInfo {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final DateTime discoveredAt;

  BLEDeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  @override
  String toString() => '$deviceName (RSSI: $rssi dBm)';
}

/// Scans for BLE Frameon devices.
/// This is a stub implementation; real apps should use flutter_blue_plus.
class BLEScanner {
  static const String FRAMEON_SERVICE_UUID = '180A';

  final _devicesController = StreamController<BLEDeviceInfo>.broadcast();
  
  Stream<BLEDeviceInfo> get deviceStream => _devicesController.stream;

  /// Start scanning for BLE devices.
  Future<void> startScan() async {
    // Stub: Real implementation would use platform-specific BLE APIs
    _devicesController.addError(
      UnsupportedError('BLE scanning not available on this platform'),
    );
  }

  /// Stop scanning.
  Future<void> stopScan() async {
    await _devicesController.close();
  }
}
