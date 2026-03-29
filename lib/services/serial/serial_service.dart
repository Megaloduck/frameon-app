import 'dart:async';
import 'dart:typed_data';

/// Abstract serial transport layer.
///
/// The concrete implementation will use `flutter_libserialport` on desktop
/// and a WebSocket bridge on Web. By coding against this interface, the rest
/// of the app never imports platform-specific packages directly.
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

  /// Whether a connection is currently open.
  bool get isConnected;

  /// The name of the currently connected port, or null.
  String? get connectedPort;
}

/// Thrown when a serial operation fails.
class SerialException implements Exception {
  final String message;
  const SerialException(this.message);

  @override
  String toString() => 'SerialException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// Stub implementation (no-op, used until flutter_libserialport is wired)
// ─────────────────────────────────────────────────────────────────────────────

/// Development stub — returns fake ports and simulates a successful send.
///
/// Replace with [LibSerialPortService] (desktop) or [WebSocketSerialService]
/// (web) once the platform packages are added to pubspec.yaml.
class StubSerialService implements SerialService {
  bool _connected = false;
  String? _port;

  @override
  Future<List<String>> availablePorts() async {
    // Return plausible fake ports for UI development.
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
    // Simulate chunked send with progress callbacks.
    const int chunkSize = 512;
    int sent = 0;
    while (sent < data.length) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sent = (sent + chunkSize).clamp(0, data.length);
      onProgress?.call(sent / data.length);
    }
  }

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedPort => _port;
}