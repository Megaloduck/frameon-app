import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/timeline.dart';
import '../../features/export/frame_exporter.dart';
import '../../features/settings/settings_dialog.dart';
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
// Top-level packet builder — required by compute()
//
// compute() spawns a background isolate and calls this function there,
// keeping the CRC-16 computation (which loops over ~1.2 MB of data) off
// the UI thread entirely. Must be a top-level or static function —
// closures and instance methods are not sendable across isolate boundaries.
// ─────────────────────────────────────────────────────────────────────────────

/// Converts a [Timeline] into the binary FRM packet on a background isolate.
///
/// Called via `compute(_buildPacket, timeline)` in [DeviceController.sendToDevice].
/// Includes the 16-byte header, all RGB565 frame data, and the CRC-16/CCITT
/// trailer — exactly the bytes the firmware expects.
Uint8List _buildPacket(Timeline timeline) {
  return const FrameExporter().export(timeline);
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceController
// ─────────────────────────────────────────────────────────────────────────────

/// Manages the full device lifecycle: scan → connect → send → disconnect.
///
/// ## Send flow
///
/// 1. Export the current [Timeline] to a binary packet via [FrameExporter],
///    running on a **background isolate** via `compute()` so the UI thread
///    is never blocked by the CRC-16 computation over ~1.2 MB.
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

  // ── Public API ────────────────────────────────────────────────────────────

  /// Refresh the list of available serial ports.
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
  ///
  /// Reads the baud rate from [settingsProvider] so the setting in the
  /// Device section of Settings is actually applied. Previously this always
  /// used the default 115200 regardless of what the user configured.
  Future<void> connect(String portName) async {
    state = state.copyWith(
      status:       DeviceConnectionStatus.connecting,
      portName:     portName,
      errorMessage: null, // clear any previous error when starting a new connect
    );
    try {
      // FIX: read baud rate from settings instead of always using the default.
      final int baudRate = ref.read(settingsProvider).baudRate;
      await _serial.connect(portName, baudRate: baudRate);
      state = state.copyWith(status: DeviceConnectionStatus.connected);
    } catch (e) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
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
  /// ## Why compute() is used here
  ///
  /// [FrameExporter.export] builds the full binary packet synchronously:
  ///   - Copies all RGB565 frame data (up to ~1.2 MB) into one [Uint8List]
  ///   - Runs CRC-16/CCITT over every byte of that buffer in a tight loop
  ///
  /// Both operations are pure CPU work with no I/O. Running them on the UI
  /// thread causes the app to freeze for a noticeable moment and produces the
  /// "Reported frame time is older than the last one; clamping" error in the
  /// debug console. `compute(_buildPacket, timeline)` offloads this to a
  /// background isolate, leaving the UI thread free to keep painting.
  ///
  /// Automatically retries once on NAK (CRC mismatch).
  /// Surfaces a human-readable error on ERR, second NAK, or timeout.
  Future<void> sendToDevice() async {
    if (!state.isConnected) return;

    final Timeline? timeline = ref.read(timelineProvider).value;
    if (timeline == null || timeline.frameCount == 0) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
        errorMessage: 'Nothing to send — add some content to the canvas first.',
      );
      return;
    }

    state = state.copyWith(
      status:       DeviceConnectionStatus.sending,
      sendProgress: 0,
      errorMessage: null, // clear any previous error at the start of a new send
    );

    try {
      // Build the FRM packet on a background isolate.
      // This keeps CRC-16 computation (~1.2 MB) off the UI thread,
      // preventing the app freeze and the frame-time error.
      final Uint8List packet = await compute(_buildPacket, timeline);

      await _sendWithRetry(packet);

      // FIX: explicitly pass errorMessage: null so copyWith actually clears
      // any error message from a previous failed send. The old code omitted
      // errorMessage here, which left stale error text visible even after a
      // successful send because copyWith's ?? operator can never set it to null.
      // FIX: reset sendProgress to 0 after success so the next send starts
      // from a clean 0% state rather than jumping from 100%.
      state = state.copyWith(
        status:       DeviceConnectionStatus.connected,
        sendProgress: 0,
        errorMessage: null,
      );
    } on SerialException catch (e) {
      final bool portStillOpen = _serial.isConnected;
      // If the port closed during the send, clean it up properly so the next
      // connect() starts with a clean LibSerialPortService state.
      if (!portStillOpen) await _serial.disconnect();
      state = state.copyWith(
        // FIX: if the port dropped, use `lost` status instead of `error` so
        // the UI can show a distinct "connection lost" message and the
        // auto-reconnect logic (if enabled) knows it should attempt reconnect.
        status:       portStillOpen
            ? DeviceConnectionStatus.error
            : DeviceConnectionStatus.lost,
        errorMessage: e.message,
        sendProgress: 0,
      );
    } catch (e) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
        errorMessage: 'Unexpected error: $e',
        sendProgress: 0,
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
          // Unknown byte — likely a firmware debug Serial.print() line that
          // slipped through the protocol filter. Treat as a timeout.
          throw SerialException(
            'Unexpected response byte: '
            '0x${response!.toRadixString(16).toUpperCase()}. '
            'This may be a firmware debug message on the serial line.',
          );
      }
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);