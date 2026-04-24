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
// ── Why this file is careful about native memory ─────────────────────────────
//
// flutter_libserialport wraps a native C library (libserialport). Every
// SerialPort object holds a raw `sp_port*` pointer. When port.dispose() is
// called, it calls sp_free_port() — freeing that native struct.
//
// Two bugs can cause Windows to crash with:
//   "Debug Assertion Failed! … debug_heap.cpp … is_block_type_valid"
//
// BUG 1 — Dart-level use-after-free
//   send() and readResponseByte() both contain `await` yield points inside
//   their loops. If disconnect() fires while either loop is suspended at an
//   `await`, it frees the native port. When the loop resumes and reads the
//   old captured `port` local variable, it calls a native method on freed
//   memory → heap assertion.
//
//   FIX: Re-read _port at the TOP of every iteration (after every `await`).
//   Any iteration that sees _port == null exits immediately without touching
//   the native object.
//
// BUG 2 — Native-level use-after-free (the debug_heap.cpp crash)
//   Even with the Dart guard, port.close() + port.dispose() can be called
//   while a native sp_port_write() or sp_port_read() is still executing
//   inside the C library. The C function accesses the freed sp_port* struct
//   → heap corruption.
//
//   FIX: Deferred dispose. When disconnect() is called while an operation
//   is in flight (_activeOps > 0), the port is closed immediately (which
//   causes in-flight native calls to fail/return) but dispose() is deferred
//   until all operations have exited via _endOp(). Only after _activeOps
//   drops to zero is sp_free_port() called, at which point no native code
//   holds a live pointer to the struct.
//
// ─────────────────────────────────────────────────────────────────────────────

/// Chunk size for [send] — 4 KB gives smooth progress updates without
/// overwhelming the USB CDC driver's internal buffers.
const int _kChunkSize = 4096;

/// How long [readResponseByte] polls between native read attempts.
const Duration _kPollInterval = Duration(milliseconds: 20);

class LibSerialPortService implements SerialService {
  SerialPort? _port;

  // ── Deferred-dispose state ─────────────────────────────────────────────────
  //
  // _activeOps counts how many send/readResponseByte operations are currently
  // executing a native call (port.write / port.read). Incremented by _beginOp()
  // before each native call, decremented by _endOp() after.
  //
  // When disconnect() is called and _activeOps > 0, the port is closed (which
  // makes in-flight native calls fail and return quickly) but dispose() is NOT
  // called yet. Instead _pendingDispose is set to true. The last _endOp() to
  // run will see _pendingDispose == true and call dispose() at that point,
  // safely after all native code has exited.
  int  _activeOps      = 0;
  bool _pendingDispose = false;
  // The port we're deferring dispose() on. Kept separately because _port is
  // nulled in disconnect() before dispose() is safe to call.
  SerialPort? _disposeTarget;

  // ── Operation reference counting ──────────────────────────────────────────

  /// Call immediately before every native port.write() / port.read() call.
  void _beginOp() {
    _activeOps++;
  }

  /// Call immediately after every native port.write() / port.read() call.
  ///
  /// If this was the last in-flight operation and a dispose was deferred,
  /// calls dispose() now — safely after all native code has exited.
  void _endOp() {
    _activeOps--;
    if (_activeOps == 0 && _pendingDispose) {
      _pendingDispose = false;
      _disposeTarget?.dispose();
      _disposeTarget = null;
    }
  }

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
    // Null _port FIRST. Any in-flight loop iteration that resumes after this
    // point will see _port == null and exit — before any native call is made.
    final port = _port;
    _port = null;
    if (port == null) return;

    // Close the port immediately. This causes any currently-executing native
    // sp_port_read() or sp_port_write() to fail and return quickly. It does
    // NOT free the sp_port* struct — that requires dispose().
    if (port.isOpen) port.close();

    if (_activeOps > 0) {
      // One or more native calls are still on the call stack (between
      // _beginOp and _endOp). Defer dispose() until they all exit.
      // _endOp() will call dispose() when _activeOps drops to zero.
      _pendingDispose  = true;
      _disposeTarget   = port;
    } else {
      // No native calls in flight — safe to dispose immediately.
      port.dispose();
    }
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
      // ── Dart-level guard (Bug 1 fix) ──────────────────────────────────
      // Re-read _port after every await. disconnect() nulls _port before
      // doing anything else, so if it ran while we were suspended, we exit
      // here without touching the native object.
      final port = _port;
      if (port == null || !port.isOpen) {
        throw const SerialException('Connection lost during send');
      }

      final int      end   = (sent + _kChunkSize).clamp(0, data.length);
      final Uint8List chunk = data.sublist(sent, end);

      // ── Native-level guard (Bug 2 fix) ────────────────────────────────
      // Bracket every native call with _beginOp / _endOp so disconnect()
      // knows whether it is safe to call dispose() immediately or must defer.
      _beginOp();
      final int written = port.write(chunk);
      _endOp();

      if (written < 0) {
        final err = SerialPort.lastError;
        throw SerialException(
          'Write failed at byte $sent: ${err?.message ?? "unknown error"}',
        );
      }

      sent += written;
      onProgress?.call(sent / data.length);

      // Yield to the event loop. disconnect() may run here, nulling _port
      // and (if _activeOps == 0 at that point) safely disposing the port.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Poll the port for a single response byte from the firmware.
  ///
  /// Only returns bytes matching the known firmware protocol values
  /// (ACK 0x06, NAK 0x15, ERR 0x1B). All other bytes — including ASCII
  /// debug text from Serial.println() in the firmware — are silently
  /// discarded so they cannot be mistaken for a protocol response.
  ///
  /// Re-reads [_port] at the top of every iteration (after each `await`) to
  /// detect a disconnect() that fired while the loop was suspended.
  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    final DateTime deadline =
        DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      // ── Dart-level guard (Bug 1 fix) ──────────────────────────────────
      final port = _port;
      if (port == null || !port.isOpen) return null;

      // ── Native-level guard (Bug 2 fix) ────────────────────────────────
      _beginOp();
      final Uint8List bytes = port.read(1);
      _endOp();

      if (bytes.isNotEmpty) {
        final int byte = bytes[0];

        // ── Protocol filter (Bug 3 fix — firmware debug text) ─────────
        // The firmware emits Serial.println() debug strings on the same
        // serial line as binary ACK/NAK/ERR bytes. Without this filter,
        // the first byte of a debug string (e.g. '[' = 0x5B) would be
        // returned as the response, causing a spurious "Unexpected
        // response byte" error and a false disconnect.
        if (byte == kFirmwareAck ||
            byte == kFirmwareNak ||
            byte == kFirmwareErr) {
          return byte;
        }
        // Any other byte is a debug character — discard and keep polling.
      }

      // Yield to the event loop. disconnect() may run here.
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