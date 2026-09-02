// lib/services/network/tcp_client.dart
//
// TCP socket client for WiFi-connected Frameon devices.
// Implements the same packet protocol as USB Serial.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../features/device/device_event.dart';
import '../serial/serial_service.dart';

class TCPClient {
  final String host;
  final int port;
  
  Socket? _socket;
  StreamSubscription? _subscription;
  
  final _deviceEventsController = StreamController<DeviceEvent>.broadcast();
  
  Stream<DeviceEvent> get deviceEvents => _deviceEventsController.stream;
  bool get isConnected => _socket != null;

  TCPClient({
    required this.host,
    required this.port,
  });

  /// Connect to the TCP server on the device.
  /// Throws SocketException if connection fails.
  Future<void> connect({int timeoutSecs = 10}) async {
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: Duration(seconds: timeoutSecs),
      );

      _socket!.setOption(SocketOption.tcpNoDelay, true);
      
      // Start background reader for device events
      _startReader();
    } catch (e) {
      _socket = null;
      throw SocketException('Failed to connect to $host:$port: $e');
    }
  }

  /// Disconnect and clean up resources.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _socket?.close();
    _socket = null;
  }

  /// Send a packet to the device.
  /// Returns the number of bytes sent.
  Future<int> send(Uint8List data) async {
    if (!isConnected || _socket == null) {
      throw SocketException('Not connected');
    }
    
    try {
      _socket!.add(data);
      await _socket!.flush();
      return data.length;
    } catch (e) {
      throw SocketException('Send failed: $e');
    }
  }

  /// Read a single response byte from the device (ACK/NAK/ERR).
  /// Returns null on timeout.
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    if (!isConnected || _socket == null) {
      throw SocketException('Not connected');
    }

    try {
      final completer = Completer<int?>();
      late StreamSubscription sub;
      
      sub = _socket!.listen(
        (data) {
          if (data.isNotEmpty && !completer.isCompleted) {
            completer.complete(data[0]);
            sub.cancel();
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
            sub.cancel();
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(null);
            sub.cancel();
          }
        },
      );

      return await completer.future.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () => null,
      );
    } catch (e) {
      return null;
    }
  }

  /// Background reader for device events (EVT lines).
  void _startReader() {
    final buffer = <int>[];
    
    _subscription = _socket!.listen(
      (Uint8List data) {
        buffer.addAll(data);
        
        // Look for complete lines (ending with \n)
        while (true) {
          final newlineIdx = buffer.indexOf(10); // '\n'
          if (newlineIdx == -1) break;
          
          final line = String.fromCharCodes(
            buffer.sublist(0, newlineIdx),
          ).trim();
          
          buffer.removeRange(0, newlineIdx + 1);
          
          if (line.startsWith('EVT')) {
            _parseAndEmitEvent(line);
          }
        }
      },
      onError: (error) {
        _socket = null;
        _deviceEventsController.addError(error);
      },
      onDone: () {
        _socket = null;
        _deviceEventsController.close();
      },
    );
  }

  /// Parse an EVT line and emit the shared device event model.
  void _parseAndEmitEvent(String line) {
    final event = DeviceEvent.tryParse(line);
    if (event == null) return;

    _deviceEventsController.add(event);
  }
}
