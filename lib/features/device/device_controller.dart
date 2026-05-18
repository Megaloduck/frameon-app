// lib/features/device/device_controller.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DeviceController — manages scan → connect → send → disconnect lifecycle.
//
// Fixes applied (vs. previous revision):
//
//   1. Response timeout is now COMPUTED from packet size, not a 15 s constant.
//      At 921600 baud a full 1.2 MB packet takes ~13.65 s just to transmit;
//      the old 15 s budget had only ~1.4 s for CRC, flush, USB return and
//      scheduling jitter, and the host would time out moments before the
//      firmware's ACK arrived. The new formula: transmission_time + 5 s
//      overhead, with an 8 s floor for small packets.
//
//   2. Send failures now perform an explicit, awaited disconnect + 200 ms
//      settle delay before transitioning to the error state. This forces
//      flutter_libserialport's native sp_port* struct to actually be freed
//      and Windows' CDC stack to release the COM handle, so the next
//      connect() attempt doesn't fail with "Could not open COMx".
//
//   3. connect() always disconnects first (with a 100 ms settle), and uses
//      direct DeviceConnectionState() construction in the "clean" states
//      so a stale errorMessage from a previous failure cannot leak through
//      the copyWith chain. (The existing copyWith uses `?? this.errorMessage`
//      which means `errorMessage: null` is a no-op — direct construction
//      is the only way to truly clear it without modifying connection_state.dart.)
//
//   4. The "no response" error message now includes the packet size and the
//      actual timeout that was applied, so future failures are diagnosable
//      at a glance.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/timeline.dart';
import '../../features/export/frame_exporter.dart';
import '../../services/serial/serial_service.dart';
import '../../services/serial/serial_desktop.dart';
import '../../shared/providers/providers.dart';
import '../settings/settings_dialog.dart';
import 'connection_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Retry policy and timeout calculation
// ─────────────────────────────────────────────────────────────────────────────

/// Maximum number of send attempts before surfacing an error.
/// 1 initial attempt + 1 automatic retry on NAK = 2 total.
const int _kMaxAttempts = 2;

/// Serial line speed — must match the firmware's Serial.begin(921600).
const int _kBaudRate = 921600;

/// Bits per UART frame at 8N1 (1 start + 8 data + 1 stop = 10).
const int _kBitsPerByte = 10;

/// Fixed overhead added to the transmission-time estimate to cover:
///   • CRC-16 over up to ~1.2 MB on the ESP32 (~150 ms at 240 MHz)
///   • Serial.flush() drain on the ESP32 UART TX FIFO
///   • CH340N USB return latency (variable, up to ~500 ms on Windows)
///   • Host-side event-loop scheduling jitter under load
const int _kResponseFixedOverheadMs = 5000;

/// Absolute floor — small packets (clock-only, pomodoro-only) should still
/// get a reasonable response window even if their transmission time is
/// effectively zero.
const int _kResponseMinTimeoutMs = 8000;

/// Compute the response timeout (in ms) for a packet of [packetBytes] bytes.
///
/// transmission_ms = packetBytes * 10 * 1000 / 921600
///
/// We add [_kResponseFixedOverheadMs] for everything that happens after the
/// last byte hits the UART. For a full 1.2 MB packet this yields ~18.6 s of
/// budget vs. the old hard-coded 15 s — exactly the slack the protocol needs.
int _responseTimeoutFor(int packetBytes) {
  final int transmissionMs =
      (packetBytes * _kBitsPerByte * 1000) ~/ _kBaudRate;
  final int total = transmissionMs + _kResponseFixedOverheadMs;
  return total < _kResponseMinTimeoutMs ? _kResponseMinTimeoutMs : total;
}

/// Settling time the Windows CDC stack needs between releasing one COM
/// handle and granting another on the same port. Empirically validated.
/// On macOS and Linux the handle is released synchronously, so this is
/// effectively wasted time on those platforms — but 200 ms is small enough
/// not to matter.
const Duration _kPortSettleDelay = Duration(milliseconds: 200);

/// Shorter settle delay applied between an explicit disconnect and a new
/// connect (no I/O error has occurred, so the native state should be clean
/// already).
const Duration _kPortReconnectDelay = Duration(milliseconds: 100);

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

final availablePortsProvider = FutureProvider<List<PortInfo>>((ref) async {
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
///    running on a background isolate via compute().
/// 2. Stream the packet to the device in 4 KB chunks (progress 0 → 1).
/// 3. Wait up to [_responseTimeoutFor]( packet.length ) ms for the firmware's
///    1-byte response:
///       0x06 ACK → success, status → connected.
///       0x15 NAK → CRC mismatch; automatically retry from step 2 (once).
///       0x1B ERR → device rejected the header; surface error immediately.
///       null     → timeout; surface error with size and timeout in message.
/// 4. If the retry also NAKs, surface a CRC error.
///
/// All failure paths route through [_failGracefully], which awaits a full
/// disconnect before transitioning to error state — this is what prevents
/// the "Could not open COM5" issue on subsequent reconnect attempts.
class DeviceController extends Notifier<DeviceConnectionState> {
  @override
  DeviceConnectionState build() => const DeviceConnectionState();

  SerialService get _serial => ref.read(serialServiceProvider);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Refresh the list of available ports.
  Future<List<PortInfo>> scanPorts() async {
    state = state.copyWith(status: DeviceConnectionStatus.scanning);
    try {
      final ports = await _serial.availablePorts();
      // Drop back to a clean disconnected state — direct construction so any
      // stale errorMessage from a previous failure is wiped out.
      state = const DeviceConnectionState();
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
  /// Always tears down any prior connection first. This is critical on
  /// Windows: if a previous session left a deferred dispose pending (or the
  /// app is recovering from a send-error state), the underlying COM handle
  /// may still be held and the open will fail with "Could not open COMx".
  Future<void> connect(String portName) async {
    // Force-release any prior native state. We swallow errors here because a
    // failed disconnect during cleanup is non-fatal — the goal is just to
    // get to a clean slate.
    try {
      await _serial.disconnect();
    } catch (_) {}
    await Future<void>.delayed(_kPortReconnectDelay);

    // Direct construction — copyWith would preserve any stale errorMessage
    // from a previous failure because of how DeviceConnectionState.copyWith
    // handles null fallback. We want a guaranteed-clean connecting state.
    state = DeviceConnectionState(
      status: DeviceConnectionStatus.connecting,
      portName: portName,
    );

    try {
      final int baudRate = ref.read(settingsProvider).baudRate;
      await _serial.connect(portName, baudRate: baudRate);
      state = DeviceConnectionState(
        status: DeviceConnectionStatus.connected,
        portName: portName,
      );
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: 'Connect failed: $e',
      );
    }
  }

  /// Disconnect from the current port.
  Future<void> disconnect() async {
    try {
      await _serial.disconnect();
    } catch (_) {
      // Disconnect failures during user-initiated teardown are non-fatal.
    }
    state = const DeviceConnectionState();
  }

  /// Export the current timeline and send it to the connected device.
  ///
  /// Automatically retries once on NAK (CRC mismatch).
  /// Surfaces a human-readable error on ERR, second NAK, or timeout.
  Future<void> sendToDevice() async {
    if (!state.isConnected) return;

    final Timeline? timeline = ref.read(timelineProvider).value;
    if (timeline == null || timeline.frameCount == 0) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage:
            'Nothing to send — add some content to the canvas first.',
      );
      return;
    }

    // Direct construction wipes any prior errorMessage so the UI reflects
    // a clean "sending" state instead of "sending + previous error text".
    state = DeviceConnectionState(
      status: DeviceConnectionStatus.sending,
      portName: state.portName,
      sendProgress: 0,
    );

    try {
      // Build the FRM packet on a background isolate. This keeps CRC-16
      // computation (~1.2 MB) off the UI thread, preventing freezes.
      final Uint8List packet = await compute(_buildPacket, timeline);

      await _sendWithRetry(packet);

      // Success — clean transition back to connected, no error message.
      state = DeviceConnectionState(
        status: DeviceConnectionStatus.connected,
        portName: state.portName,
        sendProgress: 1.0,
      );
    } on SerialException catch (e) {
      await _failGracefully(e.message);
    } catch (e) {
      await _failGracefully('Unexpected error: $e');
    }
  }

  /// Send a next-song preload packet (Spotify integration).
  ///
  /// Fire-and-forget — failures here MUST NOT disrupt the visible connection
  /// state for the user, because this is a background optimisation rather
  /// than a user-driven action.
  ///
  /// The current [_buildPacket] signature only takes the [Timeline], so
  /// [startPositionMs] and [trackDurationMs] are accepted but the FrameExporter
  /// is expected to read them from the Timeline's embedded Spotify state.
  /// If your FrameExporter takes them explicitly, adapt this method to call
  /// the matching overload.
  Future<void> sendNextSong(
    Timeline timeline, {
    required int startPositionMs,
    required int trackDurationMs,
  }) async {
    if (!state.isConnected) return;
    if (timeline.frameCount == 0) return;
    if (state.isSending) return; // never overlap with a user-initiated send

    try {
      final Uint8List packet = await compute(_buildPacket, timeline);
      await _sendWithRetry(packet);
      // No state change — this is a background preload, not a user action.
    } catch (_) {
      // Silently swallow: next-song preload is best-effort. If it fails,
      // the next regular sendToDevice() will pick up the slack.
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Tear the port down cleanly after a send failure, then transition to
  /// error state.
  ///
  /// This is the path that previously left native sp_port* structs alive
  /// on Windows, holding the COM handle and blocking the next open() with
  /// "Could not open COMx". The explicit awaited disconnect plus the
  /// 200 ms settle delay forces the native library to fully release the
  /// handle before any reconnect attempt.
  ///
  /// portName is set to null on failure so the UI surfaces "disconnected"
  /// rather than "still pretending to be on COM5".
  Future<void> _failGracefully(String message) async {
    try {
      await _serial.disconnect();
    } catch (_) {
      // Don't let cleanup errors mask the original failure message.
    }
    await Future<void>.delayed(_kPortSettleDelay);

    state = DeviceConnectionState(
      status: DeviceConnectionStatus.error,
      errorMessage: message,
      sendProgress: 0,
    );
  }

  /// Send [packet] with automatic NAK retry.
  ///
  /// The response timeout is computed from packet size so a full 1.2 MB
  /// commit gets ~18.6 s and a small clock-only commit gets the 8 s floor.
  ///
  /// Attempts up to [_kMaxAttempts] times. On each attempt:
  ///   1. Streams the full packet with progress callbacks.
  ///   2. Reads the 1-byte device response within the computed timeout.
  ///
  /// Throws [SerialException] if all attempts fail or a hard error occurs.
  Future<void> _sendWithRetry(Uint8List packet) async {
    final int timeoutMs = _responseTimeoutFor(packet.length);

    for (int attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      if (attempt > 1) {
        // Reset progress indicator for the retry pass.
        state = state.copyWith(sendProgress: 0);
      }

      // ── Stream packet ────────────────────────────────────────────────────
      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );

      // ── Read firmware response ───────────────────────────────────────────
      final int? response =
          await _serial.readResponseByte(timeoutMs: timeoutMs);

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
          // Timeout — include packet size and applied timeout in the
          // message so future failures are diagnosable at a glance.
          final mb = (packet.length / 1024 / 1024).toStringAsFixed(2);
          throw SerialException(
            'No response from device within '
            '${timeoutMs ~/ 1000} s '
            '(packet $mb MB). '
            'Check the cable and try again.',
          );

        default:
          // Unknown byte — likely a firmware debug Serial.print() that
          // slipped through the readResponseByte filter. Surface so the
          // user knows the firmware is misbehaving rather than silently
          // pretending nothing happened.
          throw SerialException(
            'Unexpected response byte: '
            '0x${response.toRadixString(16).toUpperCase()}. '
            'This may be a firmware debug message on the serial line.',
          );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);