import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firmware response constants
// Must match frameon.h on the ESP32 side.
// ─────────────────────────────────────────────────────────────────────────────

/// Device accepted the packet — frames committed to display.
const int kFirmwareAck = 0x06;

/// CRC mismatch — resend required.
const int kFirmwareNak = 0x15;

/// Malformed header or unsupported dimensions.
const int kFirmwareErr = 0x1B;

// ─────────────────────────────────────────────────────────────────────────────
// Abstract serial transport layer
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract serial transport layer.
///
/// Desktop: [LibSerialPortService] via `flutter_libserialport`.
/// Web/stub: [StubSerialService] for UI development.
///
/// All implementations must be safe to call from async Dart code.
abstract class SerialService {
  /// List all currently available serial port names.
  Future<List<String>> availablePorts();

  /// Open a connection to [portName] at [baudRate].
  /// Throws [SerialException] on failure.
  Future<void> connect(String portName, {int baudRate = 115200});

  /// Close the active connection. No-op if already disconnected.
  Future<void> disconnect();

  /// Send [data] over the open connection.
  ///
  /// [onProgress] is called with 0.0–1.0 as bytes are written.
  /// Throws [SerialException] if not connected or on write failure.
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  });

  /// Read a single response byte from the device.
  ///
  /// Polls until a byte arrives or [timeoutMs] elapses.
  /// Returns the byte value, or `null` on timeout.
  ///
  /// Expected values: [kFirmwareAck], [kFirmwareNak], [kFirmwareErr].
  Future<int?> readResponseByte({int timeoutMs = 15000});

  /// Whether a connection is currently open.
  bool get isConnected;

  /// The name of the currently connected port, or null.
  String? get connectedPort;
}

// ─────────────────────────────────────────────────────────────────────────────
// SerialException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when a serial operation fails.
class SerialException implements Exception {
  final String message;
  const SerialException(this.message);

  @override
  String toString() => 'SerialException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// StubSerialService — no-op, used on web or for UI development
// ─────────────────────────────────────────────────────────────────────────────

/// Development stub — returns fake ports and simulates a successful send.
///
/// Replace by selecting [LibSerialPortService] via [serialServiceProvider]
/// at runtime on desktop platforms.
class StubSerialService implements SerialService {
  bool _connected = false;
  String? _port;

  @override
  Future<List<String>> availablePorts() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return ['COM3', 'COM4', '/dev/ttyUSB0'];
  }

  @override
  Future<void> connect(String portName, {int baudRate = 115200}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _connected = true;
    _port = portName;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _port = null;
  }

  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_connected) throw const SerialException('Not connected');
    const int chunkSize = 4096;
    int sent = 0;
    while (sent < data.length) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      sent = (sent + chunkSize).clamp(0, data.length);
      onProgress?.call(sent / data.length);
    }
  }

  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    // Simulate device processing time then ACK.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return kFirmwareAck;
  }

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedPort => _port;
}