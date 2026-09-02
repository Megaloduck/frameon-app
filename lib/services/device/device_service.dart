// lib/services/device/device_service.dart
//
// Unified device discovery and connection service.
// Manages USB serial, TCP network, and BLE connections.
// Provides a single interface for device enumeration and selection.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../mdns/mdns_discovery.dart';
import '../network/tcp_client.dart';
import '../network/ble_client.dart';
import '../serial/serial_service.dart';
import '../serial/network_serial_service.dart';

/// Types of connections available to Frameon devices.
enum ConnectionType { serial, tcp, ble }

/// A unified device descriptor that works for all connection types.
class FrameonDevice {
  final String id;
  final String name;
  final ConnectionType type;
  final String? address;  // for TCP/BLE
  final int? port;        // for TCP
  final String? serialPort;  // for serial

  FrameonDevice({
    required this.id,
    required this.name,
    required this.type,
    this.address,
    this.port,
    this.serialPort,
  });

  @override
  String toString() {
    return switch (type) {
      ConnectionType.serial => '$name ($serialPort)',
      ConnectionType.tcp => '$name ($address:$port)',
      ConnectionType.ble => '$name (BLE)',
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameonDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Unified device discovery and connection management service.
class DeviceService {
  late MDNSDiscovery _mdns;
  late BLEScanner _bleScanner;
  
  final _devicesController = StreamController<List<FrameonDevice>>.broadcast();
  final Map<String, FrameonDevice> _discoveredDevices = {};
  final Map<String, SerialService> _services = {};

  Stream<List<FrameonDevice>> get devicesStream => _devicesController.stream;
  List<FrameonDevice> get discoveredDevices => _discoveredDevices.values.toList();

  DeviceService() {
    _mdns = MDNSDiscovery();
    _bleScanner = BLEScanner();
  }

  /// Start discovering all available devices.
  Future<void> startDiscovery() async {
    // Discover USB serial ports
    await _discoverUSBDevices();

    // Discover network devices via mDNS
    _discoverNetworkDevices();

    // Discover BLE devices
    _discoverBLEDevices();
  }

  /// Stop discovery.
  Future<void> stopDiscovery() async {
    await _mdns.stopDiscovery();
    await _bleScanner.stopScan();
  }

  /// Get or create a SerialService for a device.
  /// Returns the appropriate implementation based on connection type.
  SerialService getServiceForDevice(FrameonDevice device) {
    if (_services.containsKey(device.id)) {
      return _services[device.id]!;
    }

    final service = switch (device.type) {
      ConnectionType.serial => StubSerialService(),  // Placeholder
      ConnectionType.tcp => TCPSerialService(
        host: device.address!,
        port: device.port ?? 5555,
      ),
      ConnectionType.ble => BLESerialService(
        deviceId: device.id,
        deviceName: device.name,
      ),
    };

    _services[device.id] = service;
    return service;
  }

  /// Discover USB serial devices.
  Future<void> _discoverUSBDevices() async {
    try {
      // This would use the actual serial service
      // For now, we'll skip as it's handled by existing code
    } catch (e) {
      debugPrint('Error discovering USB devices: $e');
    }
  }

  /// Discover network devices via mDNS.
  void _discoverNetworkDevices() {
    _mdns.deviceStream.listen((device) {
      final frameonDevice = FrameonDevice(
        id: 'tcp_${device.ipAddress}',
        name: device.name,
        type: ConnectionType.tcp,
        address: device.ipAddress,
        port: device.port,
      );

      if (!_discoveredDevices.containsKey(frameonDevice.id)) {
        _discoveredDevices[frameonDevice.id] = frameonDevice;
        _notifyDevicesChanged();
      }
    });

    _mdns.startDiscovery();
  }

  /// Discover BLE devices.
  void _discoverBLEDevices() {
    _bleScanner.deviceStream.listen((device) {
      final frameonDevice = FrameonDevice(
        id: 'ble_${device.deviceId}',
        name: device.deviceName,
        type: ConnectionType.ble,
      );

      if (!_discoveredDevices.containsKey(frameonDevice.id)) {
        _discoveredDevices[frameonDevice.id] = frameonDevice;
        _notifyDevicesChanged();
      }
    });

    _bleScanner.startScan();
  }

  /// Notify listeners of device list changes.
  void _notifyDevicesChanged() {
    _devicesController.add(discoveredDevices);
  }

  /// Clear all discovered devices.
  void clear() {
    _discoveredDevices.clear();
    _notifyDevicesChanged();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopDiscovery();
    await _devicesController.close();
    for (final service in _services.values) {
      try {
        await service.disconnect();
      } catch (e) {
        // Ignore errors during cleanup
      }
    }
  }
}
