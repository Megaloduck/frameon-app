// lib/services/serial/serial_desktop.dart
//
// Platform-specific serial implementations.
//
//  ┌─────────────────────────────────────────────────────────────────────────┐
//  │  Platform    │  Class                │  Package                        │
//  │──────────────│───────────────────────│─────────────────────────────────│
//  │  Windows     │  Win32SerialService   │  serial_port_win32              │
//  │  macOS/Linux │  LibSerialPortService │  flutter_libserialport          │
//  └─────────────────────────────────────────────────────────────────────────┘
//
// Selected in device_controller.dart:
//   Platform.isWindows          → Win32SerialService()
//   Platform.isMacOS/isLinux    → LibSerialPortService()
//   web / other                 → StubSerialService()
//
// ── FIX SUMMARY ──────────────────────────────────────────────────────────────
//
//  Bug 1 (FIXED): `typedef LibSerialPortService = Win32SerialService` alias
//    caused macOS/Linux to get the Windows-only driver. Removed.
//
//  Bug 2 (FIXED): LibSerialPortService.availablePorts() returned List<String>.
//    Now returns List<PortInfo> to match the SerialService interface.
//
//  Bug 3 (FIXED): LibSerialPortService.connect() defaulted to baud 115200.
//    Default is now 921600, matching the firmware.
//
//  Bug 4 (FIXED): LibSerialPortService had no background reader, so EVT lines
//    and deviceEvents were dead. Now runs _readLoop() like Win32's.
//
//  Bug 5 — ROOT CAUSE of "No response from device within 8 s" (FIXED):
//    Win32SerialService.connect() set Win32 COMMTIMEOUTS to (0, 0, 0):
//        ReadIntervalTimeout:        0
//        ReadTotalTimeoutConstant:   0
//        ReadTotalTimeoutMultiplier: 0
//    Per Microsoft docs, all-zeros means reads never time out — the OS thread
//    blocks indefinitely inside ReadFile until the requested bytes arrive.
//    serial_port_win32's readBytes() wraps ReadFile in a Dart-level Future
//    timeout, but the underlying native thread stays blocked even after the
//    Dart timeout fires. Each subsequent readBytes call stacks another blocked
//    thread, making the reader permanently unreliable after the first packet.
//    FIX: ReadIntervalTimeout: 0xFFFFFFFF (MAXDWORD) with the other two at 0.
//    Per docs: "returns immediately with bytes already received, even if none."
//    This is the correct non-blocking mode — the Dart loop handles timing.
//
//  Bug 6 (FIXED): `catch (_) { break; }` in _readLoop silently killed the
//    loop on any native exception (e.g. a USB hiccup). Now backs off and
//    retries; only exits cleanly when disconnect() is called.
//
//  Bug 7 (FIXED): Redundant import of device_event.dart (already re-exported
//    by serial_service.dart). Removed.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:serial_port_win32/serial_port_win32.dart' as spw;

import 'serial_service.dart'; // re-exports PortInfo, DeviceEvent, kFirmwareAck/Nak/Err


// ═════════════════════════════════════════════════════════════════════════════
// LibSerialPortService — macOS & Linux  (flutter_libserialport / libserialport)
// ═════════════════════════════════════════════════════════════════════════════
//
// ── Native memory safety ──────────────────────────────────────────────────────
//
// flutter_libserialport wraps libserialport (C). Every SerialPort object holds
// an sp_port* freed by dispose(). Two failure modes:
//
//  BUG A — Dart-level use-after-free
//   send()/_readLoop() both `await` inside loops. If disconnect() fires
//   mid-loop it closes and disposes the port. Re-reading _port after every
//   `await` ensures we exit before touching the freed pointer.
//
//  BUG B — Native-level use-after-free
//   port.close() + dispose() can fire while sp_port_write/read() is on the C
//   stack. Deferred dispose: disconnect() closes the port (aborting in-flight
//   native calls) then lets the last _endOp() call dispose() once _activeOps
//   drops to zero.
//
// ─────────────────────────────────────────────────────────────────────────────

const int      _kLibChunkSize    = 4096;
const Duration _kLibPollInterval = Duration(milliseconds: 20);
const Duration _kLibIdleSleep    = Duration(milliseconds: 16);
const Duration _kLibErrorBackoff = Duration(milliseconds: 100);

class LibSerialPortService implements SerialService {
  SerialPort? _port;

  int         _activeOps      = 0;
  bool        _pendingDispose = false;
  SerialPort? _disposeTarget;

  final StreamController<DeviceEvent> _evtCtrl =
      StreamController<DeviceEvent>.broadcast();
  int?   _pendingResponseByte;
  String _lineBuf    = '';
  bool   _loopActive = false;

  void _beginOp() => _activeOps++;

  void _endOp() {
    _activeOps--;
    if (_activeOps == 0 && _pendingDispose) {
      _pendingDispose = false;
      _disposeTarget?.dispose();
      _disposeTarget  = null;
    }
  }

  @override
  Stream<DeviceEvent> get deviceEvents => _evtCtrl.stream;

  @override
  Future<List<PortInfo>> availablePorts() async {
    final names = SerialPort.availablePorts;
    return names.map((n) => PortInfo(name: n)).toList(growable: false);
  }

  @override
  Future<void> connect(String portName, {int baudRate = 921600}) async {
    await disconnect();

    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      port.dispose();
      throw SerialException(
        'Could not open $portName: ${err?.message ?? "unknown error"}',
      );
    }

    final config    = SerialPortConfig();
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

    _port                = port;
    _lineBuf             = '';
    _pendingResponseByte = null;
    _loopActive          = true;
    _readLoop();
  }

  @override
  Future<void> disconnect() async {
    final port  = _port;
    _port       = null;
    _loopActive = false;
    if (port == null) return;

    if (port.isOpen) port.close();

    if (_activeOps > 0) {
      _pendingDispose = true;
      _disposeTarget  = port;
    } else {
      port.dispose();
    }
  }

  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    int sent = 0;
    while (sent < data.length) {
      final port = _port;
      if (port == null || !port.isOpen) {
        throw const SerialException('Connection lost during send');
      }

      final int       end   = (sent + _kLibChunkSize).clamp(0, data.length);
      final Uint8List chunk = data.sublist(sent, end);

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
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final pending = _pendingResponseByte;
      if (pending != null) {
        _pendingResponseByte = null;
        return pending;
      }
      if (_port == null) return null;
      await Future<void>.delayed(_kLibPollInterval);
    }
    return null;
  }

  @override
  bool    get isConnected  => _port?.isOpen ?? false;
  @override
  String? get connectedPort => _port?.name;

  Future<void> _readLoop() async {
    while (_loopActive) {
      final port = _port;
      if (port == null || !port.isOpen) break;

      _beginOp();
      final Uint8List bytes = port.read(1);
      _endOp();

      if (bytes.isEmpty) {
        await Future<void>.delayed(_kLibIdleSleep);
        continue;
      }

      final int b = bytes[0];

      if (b == kFirmwareAck || b == kFirmwareNak || b == kFirmwareErr) {
        _pendingResponseByte = b;
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      if (b == 0x0A) {
        final line = _lineBuf.trimRight();
        _lineBuf = '';
        if (line.isNotEmpty) _dispatchLine(line);
      } else if (b != 0x0D) {
        _lineBuf += String.fromCharCode(b);
        if (_lineBuf.length > 256) _lineBuf = '';
      }

      await Future<void>.delayed(Duration.zero);
    }
  }

  void _dispatchLine(String line) {
    final event = DeviceEvent.tryParse(line);
    if (event != null && !_evtCtrl.isClosed) _evtCtrl.add(event);
  }
}


// ═════════════════════════════════════════════════════════════════════════════
// Win32SerialService — Windows  (serial_port_win32)
// ═════════════════════════════════════════════════════════════════════════════
//
// A background _readLoop() demuxes the byte stream:
//   0x06 / 0x15 / 0x1B  →  _pendingResponseByte  (polled by readResponseByte)
//   printable ASCII      →  line buffer → _dispatchLine → deviceEvents
//
// readResponseByte() polls _pendingResponseByte in memory — it never touches
// the port directly, so there is no race with _readLoop during packet sends.
//
// ── Why COMMTIMEOUTS matter ───────────────────────────────────────────────────
//
// The original code set all three COMMTIMEOUTS to 0:
//     ReadIntervalTimeout:        0
//     ReadTotalTimeoutConstant:   0   ← together these mean "block forever"
//     ReadTotalTimeoutMultiplier: 0
//
// Per MSDN: "If all three members are zero, read operations are not timed out."
// ReadFile blocks the OS thread indefinitely waiting for the requested byte.
// serial_port_win32's readBytes() applies a Dart-level deadline on top, but
// the blocked Win32 thread cannot be unblocked without closing the handle.
// After the Dart timeout fires, the thread is still stuck, and the next call
// to readBytes stacks on top — leading to a permanently degraded reader that
// never captures the firmware's ACK byte → 8 s timeout every time.
//
// FIX: ReadIntervalTimeout: 0xFFFFFFFF (Win32 MAXDWORD), others 0.
// MSDN: "A read operation returns immediately with the bytes already received,
// even if no bytes have been received." This is true non-blocking mode.
// _readLoop handles pacing with Dart-level sleeps, which is correct.
//
// ─────────────────────────────────────────────────────────────────────────────

// Win32 MAXDWORD — signals non-blocking reads to the OS kernel.
// ReadFile returns immediately with whatever bytes are already in the buffer
// (or empty Uint8List if none). This avoids blocking the native OS thread.
const int _kWin32MaxDword = 0xFFFFFFFF;

const int      _kWin32ChunkSize      = 4096;
const int      _kWin32WriteTimeoutMs = 500;
// readBytes() takes Duration? — keep as Duration to match the API.
const Duration _kWin32ReadTimeout    = Duration(milliseconds: 20);

// Durations used with Future.delayed:
const Duration _kWin32ResponsePollInterval = Duration(milliseconds: 10);
const Duration _kWin32IdleSleep            = Duration(milliseconds: 16);
const Duration _kWin32ErrorBackoff         = Duration(milliseconds: 100);

class Win32SerialService implements SerialService {
  spw.SerialPort? _port;
  String?         _portName;

  final StreamController<DeviceEvent> _evtCtrl =
      StreamController<DeviceEvent>.broadcast();
  int?   _pendingResponseByte;
  String _lineBuf    = '';
  bool   _loopActive = false;

  @override
  Stream<DeviceEvent> get deviceEvents => _evtCtrl.stream;

  @override
  Future<List<PortInfo>> availablePorts() async {
    try {
      final infos = spw.SerialPort.getPortsWithFullMessages();
      return infos
          .map((i) => PortInfo(
                name:         i.portName,
                description:  i.friendlyName,
                manufacturer: i.hardwareID,
              ))
          .toList(growable: false);
    } catch (_) {
      final names = spw.SerialPort.getAvailablePorts();
      return names.map((n) => PortInfo(name: n)).toList(growable: false);
    }
  }

  @override
  Future<void> connect(String portName, {int baudRate = 921600}) async {
    await disconnect();

    spw.SerialPort? port;
    try {
      port = spw.SerialPort(
        portName,
        openNow:  false,
        BaudRate: baudRate,
        ByteSize: 8,
        // FIX: was (0, 0, 0) = "block OS thread forever" per Win32 COMMTIMEOUTS.
        // MAXDWORD + 0 + 0 = "return immediately with buffered bytes" (non-blocking).
        // _readLoop handles pacing via Dart-level Future.delayed sleeps.
        ReadIntervalTimeout:        _kWin32MaxDword,
        ReadTotalTimeoutConstant:   0,
        ReadTotalTimeoutMultiplier: 0,
      );

      await port.open();
      port.setFlowControlSignal(spw.SerialPort.CLRDTR);
      port.setFlowControlSignal(spw.SerialPort.CLRRTS);

      if (!port.isOpened) {
        throw SerialException('Could not open $portName (handle invalid).');
      }

      _port     = port;
      _portName = portName;
    } catch (e) {
      try { port?.close(); } catch (_) {}
      _port = null; _portName = null;
      if (e is SerialException) rethrow;
      throw SerialException('Could not open $portName: $e');
    }

    _lineBuf             = '';
    _pendingResponseByte = null;
    _loopActive          = true;
    _readLoop();
  }

  @override
  Future<void> disconnect() async {
    _loopActive = false;
    final port  = _port;
    _port       = null;
    _portName   = null;
    if (port == null) return;
    try { if (port.isOpened) port.close(); } catch (_) {}
  }

  @override
  Future<void> send(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    int sent = 0;
    while (sent < data.length) {
      final port = _port;
      if (port == null || !port.isOpened) {
        throw const SerialException('Connection lost during send');
      }

      final int       end   = (sent + _kWin32ChunkSize).clamp(0, data.length);
      final Uint8List chunk = data.sublist(sent, end);

      final bool ok = await port.writeBytesFromUint8List(
        chunk,
        timeout: _kWin32WriteTimeoutMs,
      );
      if (!ok) {
        throw SerialException(
          'Write timed out at byte $sent of ${data.length}. '
          'USB cable may be disconnected.',
        );
      }

      sent += chunk.length;
      onProgress?.call(sent / data.length);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<int?> readResponseByte({int timeoutMs = 15000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final pending = _pendingResponseByte;
      if (pending != null) {
        _pendingResponseByte = null;
        return pending;
      }
      if (_port == null) return null;
      await Future<void>.delayed(_kWin32ResponsePollInterval);
    }
    return null;
  }

  @override
  bool    get isConnected  => _port?.isOpened ?? false;
  @override
  String? get connectedPort => _portName;

  // ── Background reader ──────────────────────────────────────────────────────
  //
  // With COMMTIMEOUTS set to non-blocking (MAXDWORD + 0 + 0), readBytes()
  // returns immediately with whatever is in the Win32 buffer. When the buffer
  // is empty it returns an empty Uint8List; _readLoop then sleeps one display
  // frame (16 ms) before trying again — a ~60 Hz polling rate that is fast
  // enough to capture the firmware ACK without spinning microtasks.
  //
  // On a transient native exception (e.g. momentary USB hiccup): back off
  // 100 ms and retry. Only exit cleanly when disconnect() sets _loopActive
  // to false or nulls _port.

  Future<void> _readLoop() async {
    while (_loopActive) {
      final port = _port;
      if (port == null || !port.isOpened) break;

      Uint8List bytes;
      try {
        bytes = await port.readBytes(1, timeout: _kWin32ReadTimeout);
      } catch (e) {
        // Transient native error — back off and retry.
        // Only break if disconnect() was called while we were suspended.
        if (_port == null || !_loopActive) break;
        await Future<void>.delayed(_kWin32ErrorBackoff);
        continue;
      }

      if (bytes.isEmpty) {
        // Non-blocking read returned nothing — sleep one frame and poll again.
        await Future<void>.delayed(_kWin32IdleSleep);
        continue;
      }

      final int b = bytes[0];

      // Binary protocol response → slot for readResponseByte()
      if (b == kFirmwareAck || b == kFirmwareNak || b == kFirmwareErr) {
        _pendingResponseByte = b;
        continue;
      }

      // ASCII line accumulation → deviceEvents stream
      if (b == 0x0A) {          // '\n'
        final line = _lineBuf.trimRight();
        _lineBuf = '';
        if (line.isNotEmpty) _dispatchLine(line);
      } else if (b != 0x0D) {  // skip '\r'
        _lineBuf += String.fromCharCode(b);
        if (_lineBuf.length > 256) _lineBuf = '';
      }

      // Yield after each byte to keep the event loop responsive during bursts.
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _dispatchLine(String line) {
    final event = DeviceEvent.tryParse(line);
    if (event != null && !_evtCtrl.isClosed) _evtCtrl.add(event);
  }
}