import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';
import '../../engine/widgets/pomodoro_widget.dart';
import '../../features/export/frame_exporter.dart';
import '../../features/settings/settings_dialog.dart';
import '../../services/serial/serial_service.dart';
import '../../services/serial/serial_desktop.dart';
import '../../services/serial/port_info.dart';
import '../../shared/providers/providers.dart';
import 'connection_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Retry policy
// ─────────────────────────────────────────────────────────────────────────────

const int _kMaxAttempts       = 2;
const int _kResponseTimeoutMs = 15000;

// ─────────────────────────────────────────────────────────────────────────────
// Serial service provider
// ─────────────────────────────────────────────────────────────────────────────

final serialServiceProvider = Provider<SerialService>((ref) {
  if (!kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return LibSerialPortService();
  }
  return StubSerialService();
});

final availablePortsProvider = FutureProvider<List<PortInfo>>((ref) async {
  final service = ref.watch(serialServiceProvider);
  return service.availablePorts();
});

// ─────────────────────────────────────────────────────────────────────────────
// Isolate-safe packet builder args
//
// compute() requires top-level or static functions.
// We pass a _PacketArgs record so all metadata travels to the background
// isolate together — including clock (v1.5) and pomodoro state (v1.8).
// ─────────────────────────────────────────────────────────────────────────────

class _PacketArgs {
  final Timeline            timeline;
  final int                 startPositionMs;
  final int                 trackDurationMs;
  final SpotifyLayout?      layout;
  final bool                showProgress;
  final Color               progressColor;
  final bool                isNext;
  final ClockLayer?         clockLayer;
  final DateTime?           clockCommitTime;
  // v1.8 — Pomodoro live overdraw
  final PomodoroLayer?      pomodoroLayer;
  final PomodoroTimerState? pomodoroState;

  const _PacketArgs({
    required this.timeline,
    required this.startPositionMs,
    required this.trackDurationMs,
    this.layout,
    this.showProgress    = false,
    this.progressColor   = const Color(0xFF21C32C),
    this.isNext          = false,
    this.clockLayer,
    this.clockCommitTime,
    this.pomodoroLayer,
    this.pomodoroState,
  });
}

/// Converts a [_PacketArgs] into the binary FRM packet on a background isolate.
///
/// Called via `compute(_buildPacket, args)` in [DeviceController.sendToDevice]
/// and [DeviceController.sendNextSong]. Runs CRC-16/CCITT over ~1.2 MB off
/// the UI thread so the app never freezes during a send.
Uint8List _buildPacket(_PacketArgs args) {
  const exporter = FrameExporter();
  return args.isNext
      ? exporter.exportNext(
          args.timeline,
          startPositionMs: args.startPositionMs,
          trackDurationMs: args.trackDurationMs,
          layout:          args.layout,
          showProgress:    args.showProgress,
          progressColor:   args.progressColor,
          // next-song preload packets do not carry clock or pomodoro descriptors.
        )
      : exporter.export(
          args.timeline,
          startPositionMs: args.startPositionMs,
          trackDurationMs: args.trackDurationMs,
          layout:          args.layout,
          showProgress:    args.showProgress,
          progressColor:   args.progressColor,
          clockLayer:      args.clockLayer,
          clockCommitTime: args.clockCommitTime,
          pomodoroLayer:   args.pomodoroLayer,
          pomodoroState:   args.pomodoroState,
        );
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

  /// Refresh the list of available ports.
  Future<List<PortInfo>> scanPorts() async {
    state = state.copyWith(status: DeviceConnectionStatus.scanning);
    try {
      final ports = await _serial.availablePorts();
      state = state.copyWith(status: DeviceConnectionStatus.disconnected);
      ref.invalidate(availablePortsProvider);
      return ports;
    } catch (e) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
        errorMessage: 'Scan failed: $e',
      );
      return [];
    }
  }

  /// Connect to [portName].
  Future<void> connect(String portName) async {
    state = state.copyWith(
      status:       DeviceConnectionStatus.connecting,
      portName:     portName,
      errorMessage: null,
    );
    try {
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
  /// Reads [spotifyServiceProvider] to embed the live song position into the
  /// packet header, enabling the firmware's progress-bar prediction feature.
  ///
  /// Also extracts any visible [ClockLayer] from the scene and embeds it in
  /// the v1.5 clock descriptor so the firmware can render the clock live via
  /// overdrawClock() — no pixels are baked, time is always accurate.
  ///
  /// Also extracts any visible [PomodoroLayer] + live timer state and embeds
  /// them in the v1.8 pomodoro descriptor so the firmware can tick the
  /// countdown live via overdrawPomodoro().
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

    // Embed current song position so firmware can predict bar position.
    final spotify = ref.read(spotifyServiceProvider);
    final int startPos = spotify.isConnected
        ? spotify.livePosition.inMilliseconds
        : 0;
    final int trackDur = spotify.isConnected
        ? spotify.currentDuration.inMilliseconds
        : 0;

    // Derive bar geometry from the active Spotify layer (if any).
    final scene        = ref.read(sceneProvider);
    final spotifyLayer = scene.visibleLayers
        .whereType<SpotifyLayer>()
        .cast<SpotifyLayer?>()
        .firstOrNull;
    final spotifyLayout  = spotifyLayer?.layout;
    final showProgress   = spotifyLayer?.showProgress ?? false;
    final progressColor  = spotifyLayer?.progressColor ?? const Color(0xFF21C32C);

    // Extract the first visible ClockLayer (if any) for the v1.5 clock
    // descriptor. Capture commit time now — this becomes clockEpochSec.
    final ClockLayer? clockLayer = scene.visibleLayers
        .whereType<ClockLayer>()
        .cast<ClockLayer?>()
        .firstOrNull;
    final DateTime? clockCommitTime =
        clockLayer != null ? DateTime.now() : null;

    // Extract the first visible PomodoroLayer + live timer state (v1.8).
    final PomodoroLayer? pomodoroLayer = scene.visibleLayers
        .whereType<PomodoroLayer>()
        .cast<PomodoroLayer?>()
        .firstOrNull;
    // Snapshot the timer state at this exact moment (the commit instant).
    // The firmware subtracts elapsed millis() from remainingSec each frame.
    final PomodoroTimerState? pomodoroState =
        pomodoroLayer != null ? ref.read(pomodoroServiceProvider) : null;

    state = state.copyWith(
      status:       DeviceConnectionStatus.sending,
      sendProgress: 0,
      errorMessage: null,
    );

    try {
      final Uint8List packet = await compute(
        _buildPacket,
        _PacketArgs(
          timeline:        timeline,
          startPositionMs: startPos,
          trackDurationMs: trackDur,
          layout:          spotifyLayout,
          showProgress:    showProgress,
          progressColor:   progressColor,
          clockLayer:      clockLayer,
          clockCommitTime: clockCommitTime,
          pomodoroLayer:   pomodoroLayer,
          pomodoroState:   pomodoroState,
        ),
      );

      await _sendWithRetry(packet);

      state = state.copyWith(
        status:       DeviceConnectionStatus.connected,
        sendProgress: 0,
        errorMessage: null,
      );
    } on SerialException catch (e) {
      final bool portStillOpen = _serial.isConnected;
      if (!portStillOpen) await _serial.disconnect();
      state = state.copyWith(
        status: portStillOpen
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

  /// Send a next-song preload packet to the firmware.
  ///
  /// The firmware stores it in a separate buffer and swaps it in automatically
  /// 10 s before the current track ends — no visible gap or manual re-send.
  ///
  /// Called by [spotifyServiceProvider] ~12 s before song end.
  Future<void> sendNextSong(
    Timeline timeline, {
    required int startPositionMs,
    required int trackDurationMs,
  }) async {
    if (!state.isConnected || state.isSending) return;

    try {
      final Uint8List packet = await compute(
        _buildPacket,
        _PacketArgs(
          timeline:        timeline,
          startPositionMs: startPositionMs,
          trackDurationMs: trackDurationMs,
          isNext:          true,
          // next-song preload carries no clock or pomodoro descriptor —
          // the firmware keeps the existing overdraw state from the active buffer.
        ),
      );
      await _sendWithRetry(packet);
      // No state change — this is a background preload, not a user action.
    } catch (_) {
      // Silently swallow: next-song preload is best-effort.
      // If it fails, the app will send a normal packet on track change.
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
      if (attempt > 1) {
        state = state.copyWith(sendProgress: 0);
      }

      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );

      final int? response = await _serial.readResponseByte(
        timeoutMs: _kResponseTimeoutMs,
      );

      switch (response) {
        case kFirmwareAck:
          return;

        case kFirmwareNak:
          if (attempt < _kMaxAttempts) continue;
          throw const SerialException(
            'CRC mismatch after retry. '
            'Check the USB cable or try re-sending.',
          );

        case kFirmwareErr:
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
      }
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
        DeviceController.new);