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
// Use-after-free fix (Windows _CrtIsValidHeapPointer crash)
// ───────────────────────────────────────────────────────────
// readResponseByte() and send() both contain `await` yield points inside
// their loops.  If disconnect() is called while either loop is suspended at
// an `await`, it nulls _port and calls port.dispose() (freeing native memory).
// When the loop resumes and calls port.read() / port.write() on the old
// captured `port` reference, it touches freed memory → heap assertion on Windows.
//
// Fix: capture _port at the TOP of every iteration (AFTER every await), not
// once before the loop.  Any iteration that finds _port == null returns/throws
// immediately, never touching the disposed native object.
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
    config.baudRate = baudRate;
    config.bits     = 8;
    config.stopBits = 1;
    config.parity   = SerialPortParity.none;
    config.rts      = SerialPortRts.off;
    config.cts      = SerialPortCts.ignore;
    config.dsr      = SerialPortDsr.ignore;
    config.dtr      = SerialPortDtr.off;
    config.xonXoff  = SerialPortXonXoff.disabled;
    port.config = config;
    config.dispose();

    _port = port;
  }

  @override
  Future<void> disconnect() async {
    // Null _port FIRST so any in-flight loop iteration that resumes after
    // this point will see null and exit cleanly — before dispose() is called.
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
  /// Re-reads [_port] at the top of every iteration (after each `await`) to
  /// detect a disconnect() that fired while the loop was suspended.
  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    int sent = 0;

    while (sent < data.length) {
      // ── Re-read _port after every await point ─────────────────────────
      // If disconnect() ran while we were suspended at the previous
      // Future.delayed, _port is now null — bail out immediately instead of
      // writing to a disposed native object.
      final port = _port;
      if (port == null || !port.isOpen) {
        throw const SerialException('Connection lost during send');
      }

      final int    end     = (sent + _kChunkSize).clamp(0, data.length);
      final Uint8List chunk = data.sublist(sent, end);

      final int written = port.write(chunk);
      if (written < 0) {
        final err = SerialPort.lastError;
        throw SerialException(
          'Write failed at byte $sent: ${err?.message ?? "unknown error"}',
        );
      }

      sent += written;
      onProgress?.call(sent / data.length);

      // Yield to the event loop — disconnect() may run here.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Poll the port for a single response byte from the firmware.
  ///
  /// Re-reads [_port] at the top of every iteration (after each `await`) to
  /// detect a disconnect() that fired while the loop was suspended.
  ///
  /// Without this, the captured `port` reference points to a disposed native
  /// object after disconnect(), causing _CrtIsValidHeapPointer on Windows.
  @override
Future<int?> readResponseByte({int timeoutMs = 15000}) async {
  final DateTime deadline =
      DateTime.now().add(Duration(milliseconds: timeoutMs));

  while (DateTime.now().isBefore(deadline)) {
    final port = _port;
    if (port == null || !port.isOpen) return null;

    final Uint8List bytes = port.read(1, timeout: 0);
    if (bytes.isNotEmpty) {
      final int byte = bytes[0];
      // Only surface known protocol bytes — skip debug text from firmware.
      if (byte == kFirmwareAck || byte == kFirmwareNak || byte == kFirmwareErr) {
        return byte;
      }
      // Any other byte is a Serial.println() debug character — discard and keep polling.
    }

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