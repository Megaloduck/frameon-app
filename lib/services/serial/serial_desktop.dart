// lib/services/serial/serial_desktop.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// Win32SerialService — Windows-native serial transport via Win32 API.
//
// Replaces the previous LibSerialPortService (flutter_libserialport-based)
// which suffered from native heap corruption (_CrtIsValidHeapPointer assertion)
// on every send. This implementation goes through serial_port_win32, which
// calls CreateFile / ReadFile / WriteFile / SetCommState directly — no
// libserialport C library in the loop, no mixed-heap free, no SerialPortConfig
// lifetime puzzle.
//
// Trade-off: Windows-only. macOS and Linux are not supported by this file.
// Use the StubSerialService fallback for those platforms (or write a separate
// implementation using a platform-appropriate library).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart' as spw;

import 'serial_service.dart';

/// Chunk size for [send]. 4 KB gives smooth progress updates and matches the
/// CH340N's natural USB packet boundary on Windows. Smaller chunks are
/// fine too — the Win32 driver buffers internally.
const int _kChunkSize = 4096;

/// Per-chunk write timeout. 4 KB at 921600 baud = ~44 ms of pure
/// transmission; 500 ms gives huge slack for backpressure.
const int _kWriteTimeoutMs = 500;

/// How long [readResponseByte] waits inside each native read call before
/// returning whatever bytes have arrived. Short enough to keep the outer
/// deadline check responsive, long enough not to thrash.
const Duration _kReadChunkTimeout = Duration(milliseconds: 50);

class Win32SerialService implements SerialService {
  spw.SerialPort? _port;
  String? _portName;

  // ── Public API ────────────────────────────────────────────────────────────

  @override
  Future<List<PortInfo>> availablePorts() async {
    try {
      final infos = spw.SerialPort.getPortsWithFullMessages();
      return infos
          .map((i) => PortInfo(
                name: i.portName,
                description: i.friendlyName,
                manufacturer: i.hardwareID,
              ))
          .toList(growable: false);
    } catch (_) {
      // Fall back to name-only enumeration if metadata read fails.
      final names = spw.SerialPort.getAvailablePorts();
      return names.map((n) => PortInfo(name: n)).toList(growable: false);
    }
  }

  @override
  Future<void> connect(String portName, {int baudRate = 921600}) async {
    // Always tear down any prior connection.
    await disconnect();

    spw.SerialPort? port;
    try {
      port = spw.SerialPort(
        portName,
        openNow: false,
        BaudRate: baudRate,
        ByteSize: 8,
      
        // Read timeouts of zero mean "return immediately with whatever is
        // in the buffer". We do our own polling in readResponseByte via
        // readBytes(1, timeout: ...).
        ReadIntervalTimeout: 0,
        ReadTotalTimeoutConstant: 0,
        ReadTotalTimeoutMultiplier: 0,
      );

      await port.open();

      // Clear DTR and RTS so the CH340N's auto-reset circuit doesn't pulse
      // the ESP32 EN/IO0 lines on open. The ESP32 stays in run mode instead
      // of dropping into bootloader.
      port.setFlowControlSignal(spw.SerialPort.CLRDTR);
      port.setFlowControlSignal(spw.SerialPort.CLRRTS);

      if (!port.isOpened) {
        throw SerialException('Could not open $portName (handle invalid).');
      }

      _port = port;
      _portName = portName;
    } catch (e) {
      // Make sure we don't leak a half-opened port handle.
      try {
        port?.close();
      } catch (_) {}
      _port = null;
      _portName = null;
      if (e is SerialException) rethrow;
      throw SerialException('Could not open $portName: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    final port = _port;
    _port = null;
    _portName = null;
    if (port == null) return;

    try {
      if (port.isOpened) port.close();
    } catch (_) {
      // Close failures during teardown are non-fatal — the OS will reclaim
      // the handle when the process exits or the SerialPort is GC'd.
    }
  }

  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    int sent = 0;

    while (sent < data.length) {
      // Re-check the port at the top of every iteration in case disconnect()
      // fired while we were suspended on the previous await.
      final port = _port;
      if (port == null || !port.isOpened) {
        throw const SerialException('Connection lost during send');
      }

      final int end = (sent + _kChunkSize).clamp(0, data.length);
      final Uint8List chunk = data.sublist(sent, end);

      final bool ok = await port.writeBytesFromUint8List(
        chunk,
        timeout: _kWriteTimeoutMs,
      );

      if (!ok) {
        throw SerialException(
          'Write timed out at byte $sent of ${data.length}. '
          'USB cable may be disconnected.',
        );
      }

      sent += chunk.length;
      onProgress?.call(sent / data.length);

      // Yield so the UI thread can paint progress and so disconnect() has
      // a chance to interrupt us between chunks.
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    final DateTime deadline =
        DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      final port = _port;
      if (port == null || !port.isOpened) return null;

      Uint8List bytes;
      try {
        bytes = await port.readBytes(
          1,
          timeout: _kReadChunkTimeout,
        );
      } catch (_) {
        // Port may have just been closed by disconnect() — bail cleanly
        // rather than propagating a native error to the controller.
        return null;
      }

      if (bytes.isNotEmpty) {
        final int byte = bytes[0];
        if (byte == kFirmwareAck ||
            byte == kFirmwareNak ||
            byte == kFirmwareErr) {
          return byte;
        }
        // Any other byte is firmware debug text — discard and keep polling.
      }
    }

    return null;
  }

  // ── Accessors ─────────────────────────────────────────────────────────────

  @override
  bool get isConnected => _port?.isOpened ?? false;

  @override
  String? get connectedPort => _portName;
}

// ─────────────────────────────────────────────────────────────────────────────
// Backward-compatibility alias.
//
// device_controller.dart imports `LibSerialPortService` from this file. To
// avoid touching that import (and other consumers), we expose the new
// implementation under the old name. Rename at your leisure.
// ─────────────────────────────────────────────────────────────────────────────

typedef LibSerialPortService = Win32SerialService;