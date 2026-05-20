// lib/services/serial/serial_service.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart' as spw;

import '../../features/device/device_event.dart';
import 'port_info.dart';
export 'port_info.dart';
export '../../features/device/device_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firmware response constants
// ─────────────────────────────────────────────────────────────────────────────

const int kFirmwareAck = 0x06;
const int kFirmwareNak = 0x15;
const int kFirmwareErr = 0x1B;

// ─────────────────────────────────────────────────────────────────────────────
// Abstract serial transport
// ─────────────────────────────────────────────────────────────────────────────

abstract class SerialService {
  Future<List<PortInfo>> availablePorts();
  Future<void> connect(String portName, {int baudRate = 921600});
  Future<void> disconnect();
  Future<void> send(Uint8List data, {void Function(double progress)? onProgress});

  /// Poll for a single firmware response byte (ACK / NAK / ERR).
  /// Returns null on timeout.
  Future<int?> readResponseByte({int timeoutMs = 15000});

  /// Broadcast stream of parsed hardware-input events from the device.
  ///
  /// Emitted by the background reader whenever the firmware sends an
  /// "EVT …\n" line over USB-CDC serial.  Active while the port is open.
  Stream<DeviceEvent> get deviceEvents;

  bool get isConnected;
  String? get connectedPort;
}

// ─────────────────────────────────────────────────────────────────────────────
// SerialException
// ─────────────────────────────────────────────────────────────────────────────

class SerialException implements Exception {
  final String message;
  const SerialException(this.message);
  @override
  String toString() => 'SerialException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// StubSerialService — no-op for web / UI dev
// ─────────────────────────────────────────────────────────────────────────────

class StubSerialService implements SerialService {
  bool _connected = false;
  String? _port;
  Timer? _fakeEvtTimer;

  final StreamController<DeviceEvent> _evtCtrl =
      StreamController<DeviceEvent>.broadcast();

  @override
  Stream<DeviceEvent> get deviceEvents => _evtCtrl.stream;

  @override
  Future<List<PortInfo>> availablePorts() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return [
      PortInfo(name: 'COM3', description: 'Silicon Labs CP210x USB to UART Bridge', manufacturer: 'Silicon Laboratories'),
      PortInfo(name: 'COM4', description: 'USB Serial Device'),
      PortInfo(name: '/dev/ttyUSB0', description: 'CH340 Serial', manufacturer: 'QinHeng Electronics'),
    ];
  }

  @override
  Future<void> connect(String portName, {int baudRate = 921600}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _connected = true;
    _port = portName;
    _startFakeEvents();
  }

  @override
  Future<void> disconnect() async {
    _fakeEvtTimer?.cancel();
    _fakeEvtTimer = null;
    _connected = false;
    _port = null;
  }

  @override
  Future<void> send(Uint8List data, {void Function(double progress)? onProgress}) async {
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

  // Emit alternating layer-nav events in dev mode so UI reacts without HW.
  void _startFakeEvents() {
    bool forward = true;
    _fakeEvtTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_connected) return;
      _evtCtrl.add(DeviceEvent(
        kind: forward ? DeviceEventKind.joyLayerPrev : DeviceEventKind.joyLayerNext,
      ));
      forward = !forward;
    });
  }
}