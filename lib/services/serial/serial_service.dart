import 'dart:async';
import 'dart:typed_data';
//import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:serial_port_win32/serial_port_win32.dart' as spw; 



import 'port_info.dart';
export 'port_info.dart';

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
  /// List all currently available serial ports with metadata.
  ///
  /// Each [PortInfo] carries the port name plus whatever description /
  /// manufacturer strings the OS exposes for that port. Callers should
  /// use [PortInfo.name] when opening a connection and
  /// [PortInfo.displayLabel] for UI display.
  Future<List<PortInfo>> availablePorts();

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
class StubSerialService implements SerialService {
  bool _connected = false;
  String? _port;

  @override
  Future<List<PortInfo>> availablePorts() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return [
      PortInfo(
        name: 'COM3',
        description: 'Silicon Labs CP210x USB to UART Bridge',
        manufacturer: 'Silicon Laboratories',
      ),
      PortInfo(
        name: 'COM4',
        description: 'USB Serial Device',
      ),
      PortInfo(
        name: '/dev/ttyUSB0',
        description: 'CH340 Serial',
        manufacturer: 'QinHeng Electronics',
      ),
    ];
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
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return kFirmwareAck;
  }

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedPort => _port;
}