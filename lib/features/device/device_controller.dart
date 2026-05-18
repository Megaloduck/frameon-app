// lib/features/device/device_controller.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DeviceController — manages scan → connect → send → disconnect lifecycle.
//
// This revision restores the clock / pomodoro / Spotify state extraction
// that was missing from the earlier simplified version, which is what
// caused those features to stop appearing on the device after sync.
//
// Approach: extract everything off the providers on the main isolate, bundle
// it into a single record, and pass that record through compute() to the
// builder. Records are sendable across isolates in Dart 3, so this keeps
// CRC-16 computation off the UI thread without giving up the rich state
// the firmware needs.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';
import '../../engine/widgets/pomodoro_widget.dart';
import '../../features/export/frame_exporter.dart';
import '../../services/serial/serial_service.dart';
import '../../services/serial/serial_desktop.dart';
import '../../shared/providers/providers.dart';
import '../settings/settings_dialog.dart';
import 'connection_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Retry policy and timeout calculation
// ─────────────────────────────────────────────────────────────────────────────

const int _kMaxAttempts = 2;
const int _kBaudRate = 921600;
const int _kBitsPerByte = 10;
const int _kResponseFixedOverheadMs = 5000;
const int _kResponseMinTimeoutMs = 8000;

int _responseTimeoutFor(int packetBytes) {
  final int transmissionMs =
      (packetBytes * _kBitsPerByte * 1000) ~/ _kBaudRate;
  final int total = transmissionMs + _kResponseFixedOverheadMs;
  return total < _kResponseMinTimeoutMs ? _kResponseMinTimeoutMs : total;
}

const Duration _kPortSettleDelay = Duration(milliseconds: 200);
const Duration _kPortReconnectDelay = Duration(milliseconds: 100);

// ─────────────────────────────────────────────────────────────────────────────
// Provider wiring
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
// Packet build input — bundled state for compute()
//
// A record because Dart 3 records are sendable across isolate boundaries
// without any custom serialization. This is how we pass clock / pomodoro /
// Spotify state to the build isolate even though compute() takes a single
// argument.
// ─────────────────────────────────────────────────────────────────────────────

typedef _PacketBuildInput = ({
  Timeline timeline,
  int startPositionMs,
  int trackDurationMs,
  SpotifyLayout? spotifyLayout,
  bool showProgress,
  Color progressColor,
  ClockLayer? clockLayer,
  DateTime? clockCommitTime,
  PomodoroLayer? pomodoroLayer,
  PomodoroTimerState? pomodoroState,
});

// ─────────────────────────────────────────────────────────────────────────────
// Top-level packet builders — required by compute()
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _buildPacketFull(_PacketBuildInput input) {
  return const FrameExporter().export(
    input.timeline,
    startPositionMs: input.startPositionMs,
    trackDurationMs: input.trackDurationMs,
    layout: input.spotifyLayout,
    showProgress: input.showProgress,
    progressColor: input.progressColor,
    clockLayer: input.clockLayer,
    clockCommitTime: input.clockCommitTime,
    pomodoroLayer: input.pomodoroLayer,
    pomodoroState: input.pomodoroState,
  );
}

Uint8List _buildNextSongPacket(_PacketBuildInput input) {
  return const FrameExporter().exportNext(
    input.timeline,
    startPositionMs: input.startPositionMs,
    trackDurationMs: input.trackDurationMs,
    layout: input.spotifyLayout,
    showProgress: input.showProgress,
    progressColor: input.progressColor,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceController
// ─────────────────────────────────────────────────────────────────────────────

class DeviceController extends Notifier<DeviceConnectionState> {
  @override
  DeviceConnectionState build() => const DeviceConnectionState();

  SerialService get _serial => ref.read(serialServiceProvider);

  // ── Public API ────────────────────────────────────────────────────────────

  Future<List<PortInfo>> scanPorts() async {
    state = state.copyWith(status: DeviceConnectionStatus.scanning);
    try {
      final ports = await _serial.availablePorts();
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

  Future<void> connect(String portName) async {
    try {
      await _serial.disconnect();
    } catch (_) {}
    await Future<void>.delayed(_kPortReconnectDelay);

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

  Future<void> disconnect() async {
    try {
      await _serial.disconnect();
    } catch (_) {}
    state = const DeviceConnectionState();
  }

  /// Export the current timeline and send it to the connected device.
  ///
  /// Pulls clock / pomodoro / Spotify state off the providers and bundles
  /// it with the timeline before handing the build to the compute isolate.
  /// This is what makes the clock tick, the pomodoro count down, and the
  /// Spotify progress bar advance on the device — all of those are driven
  /// by descriptor fields in the packet header.
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

    state = DeviceConnectionState(
      status: DeviceConnectionStatus.sending,
      portName: state.portName,
      sendProgress: 0,
    );

    try {
      // Extract everything the FrameExporter needs from the providers,
      // on the main isolate (where ref is valid).
      final _PacketBuildInput input = _gatherPacketState(timeline);

      // Hand the bundle to the build isolate. Records ride across isolates
      // natively in Dart 3, so no custom serialization is needed.
      final Uint8List packet = await compute(_buildPacketFull, input);

      await _sendWithRetry(packet);

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
  /// The Spotify service calls this with a synthetic timeline already
  /// rendered for the upcoming track. We pull the live position / duration
  /// out of the caller's arguments rather than the provider because the
  /// "next song" hasn't started playing yet — its position is always 0.
  Future<void> sendNextSong(
    Timeline timeline, {
    required int startPositionMs,
    required int trackDurationMs,
  }) async {
    if (!state.isConnected) return;
    if (timeline.frameCount == 0) return;
    if (state.isSending) return;

    try {
      // Re-use the same extraction helper but override the position/duration
      // with the values the caller supplied for the next track.
      final base = _gatherPacketState(timeline);
      final _PacketBuildInput input = (
        timeline: base.timeline,
        startPositionMs: startPositionMs,
        trackDurationMs: trackDurationMs,
        spotifyLayout: base.spotifyLayout,
        showProgress: base.showProgress,
        progressColor: base.progressColor,
        clockLayer: base.clockLayer,
        clockCommitTime: base.clockCommitTime,
        pomodoroLayer: base.pomodoroLayer,
        pomodoroState: base.pomodoroState,
      );

      final Uint8List packet = await compute(_buildNextSongPacket, input);
      await _sendWithRetry(packet);
    } catch (_) {
      // Best-effort; never propagate next-song preload failures.
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Extract clock, pomodoro, and Spotify state from the providers and
  /// bundle it with [timeline] into a single record.
  ///
  /// MUST be called on the main isolate — touches `ref`.
  _PacketBuildInput _gatherPacketState(Timeline timeline) {
    final scene = ref.read(sceneProvider);
    final spotify = ref.read(spotifyServiceProvider);

    // Active Spotify layer (if any) — drives the progress bar geometry.
    final SpotifyLayer? spotifyLayer = scene.visibleLayers
        .whereType<SpotifyLayer>()
        .cast<SpotifyLayer?>()
        .firstOrNull;

    // Active Clock layer — the firmware will tick it live via
    // overdrawClock() if the clockEpochSec field is non-zero.
    final ClockLayer? clockLayer = scene.visibleLayers
        .whereType<ClockLayer>()
        .cast<ClockLayer?>()
        .firstOrNull;
    // Capture commit time NOW so the firmware's epoch matches host wall-clock.
    final DateTime? clockCommitTime =
        clockLayer != null ? DateTime.now() : null;

    // Active Pomodoro layer — the firmware will count down via
    // overdrawPomodoro() if pomodoroFlags has bit0 set.
    final PomodoroLayer? pomodoroLayer = scene.visibleLayers
        .whereType<PomodoroLayer>()
        .cast<PomodoroLayer?>()
        .firstOrNull;
    final PomodoroTimerState? pomodoroState =
        pomodoroLayer != null ? ref.read(pomodoroServiceProvider) : null;

    return (
      timeline: timeline,
      startPositionMs:
          spotify.isConnected ? spotify.livePosition.inMilliseconds : 0,
      trackDurationMs:
          spotify.isConnected ? spotify.currentDuration.inMilliseconds : 0,
      spotifyLayout: spotifyLayer?.layout,
      showProgress: spotifyLayer?.showProgress ?? false,
      progressColor: spotifyLayer?.progressColor ?? const Color(0xFF21C32C),
      clockLayer: clockLayer,
      clockCommitTime: clockCommitTime,
      pomodoroLayer: pomodoroLayer,
      pomodoroState: pomodoroState,
    );
  }

  Future<void> _failGracefully(String message) async {
    try {
      await _serial.disconnect();
    } catch (_) {}
    await Future<void>.delayed(_kPortSettleDelay);

    state = DeviceConnectionState(
      status: DeviceConnectionStatus.error,
      errorMessage: message,
      sendProgress: 0,
    );
  }

  Future<void> _sendWithRetry(Uint8List packet) async {
    final int timeoutMs = _responseTimeoutFor(packet.length);

    for (int attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      if (attempt > 1) {
        state = state.copyWith(sendProgress: 0);
      }

      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );

      final int? response =
          await _serial.readResponseByte(timeoutMs: timeoutMs);

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
          final mb = (packet.length / 1024 / 1024).toStringAsFixed(2);
          throw SerialException(
            'No response from device within '
            '${timeoutMs ~/ 1000} s '
            '(packet $mb MB). '
            'Check the cable and try again.',
          );

        default:
          throw SerialException(
            'Unexpected response byte: '
            '0x${response.toRadixString(16).toUpperCase()}. '
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