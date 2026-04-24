import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LibSerialPortService
//
// Real serial implementation for macOS / Windows / Linux using the
// `flutter_libserialport` package (wraps libserialport).
//
// USB CDC on ESP32-S3:
//   The baud rate set via SerialPortConfig is largely meaningless for
//   USB CDC virtual serial — actual throughput is USB Full-Speed limited
//   (~1–2 MB/s). We still set 115200 to match Serial.begin() in the
//   firmware, as some OS drivers require a valid value.
//
// Thread safety:
//   All public methods are async and run on the Dart event loop (main
//   isolate). flutter_libserialport's native calls are blocking under the
//   hood but short enough that they don't stall the event loop.
// ─────────────────────────────────────────────────────────────────────────────

/// Chunk size for [send] — 4 KB gives smooth progress updates without
/// overwhelming the USB CDC driver's internal buffers.
const int _kChunkSize = 4096;

/// How long [readResponseByte] polls between native read attempts.
const Duration _kPollInterval = Duration(milliseconds: 20);

class LibSerialPortService implements SerialService {
  SerialPort? _port;

  // ── Public API ────────────────────────────────────────────────────────────

  @override
  Future<List<String>> availablePorts() async {
    // SerialPort.availablePorts is a synchronous getter — run it on the
    // event loop so callers can safely await it.
    return Future.value(SerialPort.availablePorts);
  }

  @override
  Future<void> connect(String portName, {int baudRate = 115200}) async {
    // Close any existing connection first.
    await disconnect();

    final port = SerialPort(portName);

    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      port.dispose();
      throw SerialException(
        'Could not open $portName: ${err?.message ?? "unknown error"}',
      );
    }

    // Configure port parameters.
    final config = SerialPortConfig();
    config.baudRate  = baudRate;
    config.bits      = 8;
    config.stopBits  = 1;
    config.parity    = SerialPortParity.none;
    config.rts = SerialPortRts.off;
    config.cts = SerialPortCts.ignore;
    config.dsr = SerialPortDsr.ignore;
    config.dtr = SerialPortDtr.off;
    config.xonXoff = SerialPortXonXoff.disabled;
    port.config = config;
    config.dispose();

    _port = port;
  }

  @override
  Future<void> disconnect() async {
    final port = _port;
    _port = null;
    if (port == null) return;
    if (port.isOpen) port.close();
    port.dispose();
  }

  /// Send [data] to the device in [_kChunkSize] chunks.
  ///
  /// [onProgress] is called after each chunk with 0.0–1.0.
  ///
  /// Throws [SerialException] if:
  ///   - the port is not open
  ///   - a native write fails (libserialport returns < 0)
  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw const SerialException('Not connected');
    }

    int sent = 0;

    while (sent < data.length) {
      final end   = (sent + _kChunkSize).clamp(0, data.length);
      final chunk = data.sublist(sent, end);

      // port.write() is synchronous inside libserialport.
      // It returns the number of bytes written, or -1 on error.
      final written = port.write(chunk);
      if (written < 0) {
        final err = SerialPort.lastError;
        throw SerialException(
          'Write failed at byte $sent: ${err?.message ?? "unknown error"}',
        );
      }

      sent += written;
      onProgress?.call(sent / data.length);

      // Yield to the event loop so the UI can update between chunks.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Poll the port for a single response byte from the firmware.
  ///
  /// The ESP32 sends exactly one byte after processing a full packet:
  ///   [kFirmwareAck] 0x06 — success
  ///   [kFirmwareNak] 0x15 — CRC mismatch
  ///   [kFirmwareErr] 0x1B — bad header / wrong dimensions
  ///
  /// Returns the byte value, or `null` if [timeoutMs] elapses with no data.
  ///
  /// Each poll attempt waits up to [_kPollInterval] before trying again,
  /// keeping CPU load near zero during the wait.
  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    final port = _port;
    if (port == null || !port.isOpen) return null;

    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      // Read up to 1 byte; timeout = 0 means non-blocking (return immediately).
      final bytes = port.read(1, timeout: 0);
      if (bytes.isNotEmpty) return bytes[0];

      // Nothing available yet — sleep briefly then try again.
      await Future<void>.delayed(_kPollInterval);
    }

    return null; // timed out
  }

  // ── Accessors ─────────────────────────────────────────────────────────────

  @override
  bool get isConnected => _port?.isOpen ?? false;

  @override
  String? get connectedPort => _port?.name;
}