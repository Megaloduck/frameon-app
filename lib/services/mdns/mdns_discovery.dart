// lib/services/mdns/mdns_discovery.dart
//
// Discovers Frameon devices on the local network using mDNS (Bonjour).
// Scans for services of type "_frameon._tcp.local"

import 'dart:async';
import 'dart:io';

/// Represents a discovered Frameon device on the network.
class DiscoveredDevice {
  final String name;
  final String host;
  final int port;
  final String ipAddress;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.name,
    required this.host,
    required this.ipAddress,
    required this.port,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  @override
  String toString() => '$name ($ipAddress:$port)';
}

class MDNSDiscovery {
  static const String SERVICE_TYPE = '_frameon._tcp.local';
  static const int DISCOVERY_TIMEOUT_SECONDS = 5;

  final _devicesController = StreamController<DiscoveredDevice>.broadcast();
  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  Stream<DiscoveredDevice> get deviceStream => _devicesController.stream;
  List<DiscoveredDevice> get discoveredDevices => _discoveredDevices.values.toList();

  /// Start discovering Frameon devices on the network.
  /// For web/desktop, this is a simplified implementation.
  /// Mobile apps should use platform-specific mDNS libraries:
  ///   - iOS: NWBrowser (Network framework)
  ///   - Android: NsdManager (Android NDK)
  ///   - Windows/macOS/Linux: Use Avahi or Bonjour resolver
  Future<void> startDiscovery() async {
    // On desktop/web, we'll do simple UDP broadcast to discover devices
    // Real mDNS would require platform-specific libraries
    _broadcastDiscovery();
  }

  /// Stop discovery and close the stream.
  Future<void> stopDiscovery() async {
    await _devicesController.close();
  }

  /// Simple UDP broadcast to discover devices (fallback for desktop).
  /// Production apps should use proper mDNS implementation.
  Future<void> _broadcastDiscovery() async {
    try {
      // Get local network interfaces
      final interfaces = await NetworkInterface.list();
      
      for (final interface in interfaces) {
        if (!interface.addresses.isEmpty) {
          final addr = interface.addresses.first;
          
          // Skip loopback and link-local addresses
          if (addr.address == 'localhost' || addr.address == '127.0.0.1') continue;
          if (addr.address.startsWith('169.254.')) continue;

          // Broadcast on this subnet to discover devices
          // Frameon firmware listens on port 5555
          await _scanSubnet(addr.address);
        }
      }
    } catch (e) {
      print('[MDNS] Discovery error: $e');
    }
  }

  /// Scan a subnet for Frameon devices.
  /// This is a simplified port scan approach.
  Future<void> _scanSubnet(String localIp) async {
    // Extract subnet (e.g., "192.168.1" from "192.168.1.100")
    final parts = localIp.split('.');
    if (parts.length != 4) return;
    
    final subnet = parts.sublist(0, 3).join('.');
    final startHost = 1;
    final endHost = 10; // Scan only first 10 IPs for speed

    final futures = <Future>[];
    
    for (int i = startHost; i <= endHost; i++) {
      final host = '$subnet.$i';
      futures.add(_tryConnect(host, 5555));
    }

    // Wait for all probes with timeout
    await Future.wait(
      futures,
      eagerError: false,
    ).timeout(Duration(seconds: DISCOVERY_TIMEOUT_SECONDS));
  }

  /// Try to connect to a specific host:port to discover a device.
  Future<void> _tryConnect(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: 500),
      );

      // Successfully connected! This is a Frameon device
      final device = DiscoveredDevice(
        name: 'Frameon @ $host',
        host: host,
        ipAddress: host,
        port: port,
      );

      if (!_discoveredDevices.containsKey(device.ipAddress)) {
        _discoveredDevices[device.ipAddress] = device;
        _devicesController.add(device);
      }

      await socket.close();
    } catch (e) {
      // Connection failed, not a Frameon device
    }
  }

  /// Clear all discovered devices.
  void clear() {
    _discoveredDevices.clear();
  }
}
