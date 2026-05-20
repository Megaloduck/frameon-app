// lib/services/serial/serial_desktop.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// Win32SerialService — Windows-native serial via serial_port_win32.
//
// v2 — Two-way communication.
//
// A single background _readLoop() consumes every incoming byte:
//
//   0x06 / 0x15 / 0x1B  →  _pendingResponseByte  (polled by readResponseByte)
//   printable ASCII      →  line buffer; on '\n' → _dispatchLine
//
// readResponseByte() never touches the port directly — it polls the slot
// the background loop fills.  No pausing is needed during packet sends
// because the device doesn't send anything mid-transfer except the final
// ACK/NAK/ERR byte, which is correctly routed.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart' as spw;

import '../../features/device/device_event.dart';
import 'serial_service.dart';

const int      _kChunkSize        = 4096;
const int      _kWriteTimeoutMs   = 500;
const Duration _kReadTimeout      = Duration(milliseconds: 20);
const Duration _kResponsePollInterval = Duration(milliseconds: 10);

class Win32SerialService implements SerialService {
  spw.SerialPort? _port;
  String?         _portName;

  // ── Background reader state ────────────────────────────────────────────────
  final StreamController<DeviceEvent> _evtCtrl =
      StreamController<DeviceEvent>.broadcast();
  int?   _pendingResponseByte;
  String _lineBuf    = '';
  bool   _loopActive = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  @override
  Stream<DeviceEvent> get deviceEvents => _evtCtrl.stream;

  @override
  Future<List<PortInfo>> availablePorts() async {
    try {
      final infos = spw.SerialPort.getPortsWithFullMessages();
      return infos
          .map((i) => PortInfo(name: i.portName, description: i.friendlyName, manufacturer: i.hardwareID))
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
        openNow: false,
        BaudRate: baudRate,
        ByteSize: 8,
        ReadIntervalTimeout: 0,
        ReadTotalTimeoutConstant: 0,
        ReadTotalTimeoutMultiplier: 0,
      );

      await port.open();
      port.setFlowControlSignal(spw.SerialPort.CLRDTR);
      port.setFlowControlSignal(spw.SerialPort.CLRRTS);

      if (!port.isOpened) throw SerialException('Could not open $portName (handle invalid).');

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
  Future<void> send(Uint8List data, {void Function(double progress)? onProgress}) async {
    int sent = 0;
    while (sent < data.length) {
      final port = _port;
      if (port == null || !port.isOpened) throw const SerialException('Connection lost during send');

      final end   = (sent + _kChunkSize).clamp(0, data.length);
      final chunk = data.sublist(sent, end);

      final bool ok = await port.writeBytesFromUint8List(chunk, timeout: _kWriteTimeoutMs);
      if (!ok) throw SerialException('Write timed out at byte $sent of ${data.length}. USB cable may be disconnected.');

      sent += chunk.length;
      onProgress?.call(sent / data.length);
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Polls [_pendingResponseByte] until the background loop fills it or
  /// the deadline elapses.  Never reads the port directly.
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
      await Future<void>.delayed(_kResponsePollInterval);
    }
    return null;
  }

  @override
  bool    get isConnected  => _port?.isOpened ?? false;
  @override
  String? get connectedPort => _portName;

  // ── Background reader ──────────────────────────────────────────────────────

  // Sleep duration when no byte arrived — one display frame.
  // Keeps the loop at ~60 Hz when idle so Flutter's frame scheduler is
  // never starved by a tight microtask loop.
  static const Duration _kIdleSleep = Duration(milliseconds: 16);

  Future<void> _readLoop() async {
    while (_loopActive) {
      final port = _port;
      if (port == null || !port.isOpened) break;

      Uint8List bytes;
      try {
        bytes = await port.readBytes(1, timeout: _kReadTimeout);
      } catch (_) {
        break;
      }

      if (bytes.isEmpty) {
        // ── Critical: prevent microtask starvation ──────────────────────
        // When the port is idle, readBytes returns an already-completed
        // Future(empty).  Awaiting a pre-completed Future schedules the
        // continuation as a *microtask*, which drains before Flutter gets
        // to render a frame.  A tight loop of microtasks locks the UI solid.
        //
        // Future.delayed uses a Timer internally — a *macrotask* — so it
        // yields to the Flutter engine for frames and input between reads.
        await Future<void>.delayed(_kIdleSleep);
        continue;
      }

      final int b = bytes[0];

      // Binary protocol response bytes → slot for readResponseByte
      if (b == kFirmwareAck || b == kFirmwareNak || b == kFirmwareErr) {
        _pendingResponseByte = b;
        continue;
      }

      // ASCII line accumulation
      if (b == 0x0A) {           // '\n'
        final line = _lineBuf.trimRight();
        _lineBuf = '';
        if (line.isNotEmpty) _dispatchLine(line);
      } else if (b != 0x0D) {   // skip '\r'
        _lineBuf += String.fromCharCode(b);
        if (_lineBuf.length > 256) _lineBuf = ''; // guard against garbage
      }

      // Yield after each received byte so the event loop stays live
      // during bursts (e.g. a long boot message from the firmware).
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _dispatchLine(String line) {
    final event = DeviceEvent.tryParse(line);
    if (event != null && !_evtCtrl.isClosed) _evtCtrl.add(event);
  }
}

// Backward-compat alias
typedef LibSerialPortService = Win32SerialService;