// lib/services/serial/network_serial_service.dart
//
// Adapts TCP/BLE network transports to the SerialService interface.
// Allows the rest of the app to use network transports transparently.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../network/tcp_client.dart';
import '../network/ble_client.dart';
import 'serial_service.dart';

/// Adapter that wraps TCPClient to implement SerialService interface.
class TCPSerialService implements SerialService {
  late TCPClient _client;
  bool _connected = false;

  final String host;
  final int port;

  TCPSerialService({
    required this.host,
    required this.port,
  }) : _client = TCPClient(host: host, port: port);

  @override
  bool get isConnected => _connected && _client.isConnected;

  @override
  String? get connectedPort => _connected ? '$host:$port' : null;

  @override
  Stream<DeviceEvent> get deviceEvents => _client.deviceEvents;

  @override
  Future<List<PortInfo>> availablePorts() async {
    // Network services don't enumerate "ports"
    // Discovery is handled separately via mDNS
    return [];
  }

  @override
  Future<void> connect(String portName, {int baudRate = 921600}) async {
    try {
      await _client.connect();
      _connected = true;
      debugPrint('[TCP] Connected to $host:$port');
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _client.disconnect();
    } finally {
      _connected = false;
    }
  }

  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    if (!isConnected) {
      throw SerialException('Not connected to device');
    }

    try {
      // Send in chunks to report progress
      const chunkSize = 4096;
      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        final chunk = data.sublist(i, end);
        
        await _client.send(chunk);
        
        onProgress?.call(end / data.length);
      }
    } catch (e) {
      throw SerialException('Send failed: $e');
    }
  }

  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    if (!isConnected) {
      throw SerialException('Not connected to device');
    }

    try {
      return await _client.readResponseByte(timeoutMs: timeoutMs);
    } catch (e) {
      throw SerialException('Read failed: $e');
    }
  }
}

/// Adapter that wraps BLEClient to implement SerialService interface.
class BLESerialService implements SerialService {
  late BLEClient _client;
  bool _connected = false;

  final String deviceId;
  final String deviceName;

  BLESerialService({
    required this.deviceId,
    required this.deviceName,
  }) : _client = BLEClient(deviceId: deviceId, deviceName: deviceName);

  @override
  bool get isConnected => _connected && _client.isConnected;

  @override
  String? get connectedPort => _connected ? deviceName : null;

  @override
  Stream<DeviceEvent> get deviceEvents => _client.deviceEvents;

  @override
  Future<List<PortInfo>> availablePorts() async {
    return [];
  }

  @override
  Future<void> connect(String portName, {int baudRate = 921600}) async {
    try {
      await _client.connect();
      _connected = true;
      debugPrint('[BLE] Connected to $deviceName');
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _client.disconnect();
    } finally {
      _connected = false;
    }
  }

  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    if (!isConnected) {
      throw SerialException('Not connected to device');
    }

    try {
      // BLE has MTU limits; send in chunks
      const chunkSize = 512;
      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        final chunk = data.sublist(i, end);
        
        await _client.send(chunk);
        
        onProgress?.call(end / data.length);
      }
    } catch (e) {
      throw SerialException('Send failed: $e');
    }
  }

  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    if (!isConnected) {
      throw SerialException('Not connected to device');
    }

    try {
      return await _client.readResponseByte(timeoutMs: timeoutMs);
    } catch (e) {
      throw SerialException('Read failed: $e');
    }
  }
}
