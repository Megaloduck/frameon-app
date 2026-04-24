import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/timeline.dart';
import '../../features/export/frame_exporter.dart';
import '../../services/serial/serial_service.dart';
import '../../services/serial/serial_desktop.dart';
import '../../shared/providers/providers.dart';
import 'connection_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Retry policy
// ─────────────────────────────────────────────────────────────────────────────

/// Maximum number of send attempts before surfacing an error.
/// 1 initial attempt + 1 automatic retry on NAK = 2 total.
const int _kMaxAttempts = 2;

/// How long to wait for the firmware's ACK/NAK/ERR byte after a full send.
/// 15 s is very generous — CRC computation on 1.2 MB at 240 MHz is < 100 ms.
const int _kResponseTimeoutMs = 15000;

// ─────────────────────────────────────────────────────────────────────────────
// Serial service provider
// ─────────────────────────────────────────────────────────────────────────────

/// Provides the correct [SerialService] implementation for the current platform.
///
/// Desktop (macOS / Windows / Linux) → [LibSerialPortService] (real hardware).
/// Web / other                       → [StubSerialService]    (UI development).
final serialServiceProvider = Provider<SerialService>((ref) {
  if (!kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return LibSerialPortService();
  }
  return StubSerialService();
});

// ─────────────────────────────────────────────────────────────────────────────
// Available ports provider
// ─────────────────────────────────────────────────────────────────────────────

final availablePortsProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(serialServiceProvider);
  return service.availablePorts();
});

// ─────────────────────────────────────────────────────────────────────────────
// DeviceController
// ─────────────────────────────────────────────────────────────────────────────

/// Manages the full device lifecycle: scan → connect → send → disconnect.
///
/// ## Send flow
///
/// 1. Export the current [Timeline] to a binary packet via [FrameExporter].
/// 2. Stream the packet to the device in 4 KB chunks (progress 0 → 1).
/// 3. Wait up to [_kResponseTimeoutMs] ms for a 1-byte firmware response:
///    - `0x06` ACK → success, update state to connected.
///    - `0x15` NAK → CRC mismatch; automatically retry from step 2 (once).
///    - `0x1B` ERR → device rejected the header; surface error immediately.
///    - `null`     → timeout; surface error.
/// 4. If the retry also NAKs, surface a CRC error.
///
/// The UI reads [deviceConnectionProvider] for reactive state and calls
/// methods on the notifier to drive transitions.
class DeviceController extends Notifier<DeviceConnectionState> {
  @override
  DeviceConnectionState build() => const DeviceConnectionState();

  SerialService get _serial => ref.read(serialServiceProvider);
  FrameExporter get _exporter => const FrameExporter();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Refresh the list of available ports.
  Future<List<String>> scanPorts() async {
    state = state.copyWith(status: DeviceConnectionStatus.scanning);
    try {
      final ports = await _serial.availablePorts();
      state = state.copyWith(status: DeviceConnectionStatus.disconnected);
      ref.invalidate(availablePortsProvider);
      return ports;
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: 'Scan failed: $e',
      );
      return [];
    }
  }

  /// Connect to [portName].
  Future<void> connect(String portName) async {
    state = state.copyWith(
      status: DeviceConnectionStatus.connecting,
      portName: portName,
    );
    try {
      await _serial.connect(portName);
      state = state.copyWith(status: DeviceConnectionStatus.connected);
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: 'Connect failed: $e',
      );
    }
  }

  /// Disconnect from the current port.
  Future<void> disconnect() async {
    await _serial.disconnect();
    state = const DeviceConnectionState();
  }

  /// Export the current timeline and send it to the connected device.
  ///
  /// Automatically retries once on NAK (CRC mismatch).
  /// Surfaces a human-readable error on ERR, second NAK, or timeout.
  Future<void> sendToDevice() async {
    if (!state.isConnected) return;

    final Timeline? timeline = ref.read(timelineProvider).value;
    if (timeline == null || timeline.frameCount == 0) return;

    state = state.copyWith(
      status: DeviceConnectionStatus.sending,
      sendProgress: 0,
    );

    try {
      final Uint8List packet = _exporter.export(timeline);
      await _sendWithRetry(packet);

      state = state.copyWith(
        status: DeviceConnectionStatus.connected,
        sendProgress: 1.0,
      );
    } on SerialException catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: 'Unexpected error: $e',
      );
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Send [packet] with automatic NAK retry.
  ///
  /// Attempts up to [_kMaxAttempts] times. On each attempt:
  ///   1. Streams the full packet with progress callbacks.
  ///   2. Reads the 1-byte device response within [_kResponseTimeoutMs] ms.
  ///
  /// Throws [SerialException] if all attempts fail or a hard error occurs.
  Future<void> _sendWithRetry(Uint8List packet) async {
    for (int attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      final bool isRetry = attempt > 1;

      if (isRetry) {
        // Reset progress indicator for the retry pass.
        state = state.copyWith(sendProgress: 0);
      }

      // ── Stream packet ────────────────────────────────────────────────────
      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );

      // ── Read firmware response ───────────────────────────────────────────
      final int? response = await _serial.readResponseByte(
        timeoutMs: _kResponseTimeoutMs,
      );

      switch (response) {
        case kFirmwareAck:
          // Success — let the caller update state.
          return;

        case kFirmwareNak:
          if (attempt < _kMaxAttempts) {
            // NAK on first attempt — retry automatically.
            continue;
          }
          // NAK after all retries — give up.
          throw const SerialException(
            'CRC mismatch after retry. '
            'Check the USB cable or try re-sending.',
          );

        case kFirmwareErr:
          // Hard error — device rejected the header. Retrying won't help.
          throw const SerialException(
            'Device rejected the packet (wrong dimensions or protocol '
            'version). Update the firmware and try again.',
          );

        case null:
          throw SerialException(
            'No response from device within '
            '${_kResponseTimeoutMs ~/ 1000} s. '
            'Check the connection and try again.',
          );

        default:
          throw SerialException(
            'Unexpected response byte: '
            '0x${response!.toRadixString(16).toUpperCase()}',
          );
      }
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);