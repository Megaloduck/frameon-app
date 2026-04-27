import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../../engine/scene/layer.dart';
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

final availablePortsProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(serialServiceProvider);
  return service.availablePorts();
});

// ─────────────────────────────────────────────────────────────────────────────
// Isolate-safe packet builders
//
// compute() requires top-level or static functions.
// We pass a _PacketArgs record so both the timeline and the position metadata
// travel to the background isolate together.
// ─────────────────────────────────────────────────────────────────────────────

class _PacketArgs {
  final Timeline      timeline;
  final int           startPositionMs;
  final int           trackDurationMs;
  final SpotifyLayout? layout;
  final bool          showProgress;
  final Color         progressColor;
  final bool          isNext;
  const _PacketArgs({
    required this.timeline,
    required this.startPositionMs,
    required this.trackDurationMs,
    this.layout,
    this.showProgress = false,
    this.progressColor = const Color(0xFF21C32C),
    this.isNext = false,
  });
}

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
        )
      : exporter.export(
          args.timeline,
          startPositionMs: args.startPositionMs,
          trackDurationMs: args.trackDurationMs,
          layout:          args.layout,
          showProgress:    args.showProgress,
          progressColor:   args.progressColor,
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

  Future<void> disconnect() async {
    await _serial.disconnect();
    state = const DeviceConnectionState();
  }

  /// Export the current timeline and send it to the device as a normal packet.
  ///
  /// Reads [spotifyServiceProvider] to embed the live song position into the
  /// packet header, enabling the firmware's progress-bar prediction feature.
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
    final int startPos  = spotify.isConnected
        ? spotify.livePosition.inMilliseconds
        : 0;
    final int trackDur  = spotify.isConnected
        ? spotify.currentDuration.inMilliseconds
        : 0;

    // Derive bar geometry from the active Spotify layer (if any).
    final scene         = ref.read(sceneProvider);
    final spotifyLayer  = scene.visibleLayers
        .whereType<SpotifyLayer>()
        .cast<SpotifyLayer?>()
        .firstOrNull;
    final spotifyLayout   = spotifyLayer?.layout;
    final showProgress    = spotifyLayer?.showProgress ?? false;
    final progressColor   = spotifyLayer?.progressColor ?? const Color(0xFF21C32C);

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

  /// Send a next-song preload packet to the firmware.
  ///
  /// The firmware stores it in a separate buffer and swaps it in automatically
  /// 10 s before the current track ends — no visible gap or manual re-send.
  ///
  /// Called by [spotifyServiceProvider] ~10 s before song end (when
  /// [currentPosition] >= [currentDuration] - 12 s, giving ~1.8 s build time
  /// + ~1.8 s transfer time before the 10 s swap threshold triggers).
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

        default:
          throw SerialException(
            'Unexpected response byte: '
            '0x${response!.toRadixString(16).toUpperCase()}.',
          );
      }
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);