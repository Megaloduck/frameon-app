// lib/features/device/device_controller.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DeviceController — spec-correct controller action routing.
//
// Controller actions per Frameon_Controller_actions.xlsx
// ──────────────────────────────────────────────────────
//
//  Encoder  CW          → Preset switch +         (_switchPresetBy)
//  Encoder  CCW         → Preset switch −          (_switchPresetBy)
//  Encoder  short tap   → Check preset number     (no-op — UI already shows it)
//  Encoder  long hold   → Lock / Unlock display    (deviceLocked toggle)
//
//  BTN1  short tap      → Sync display             (sendToDevice)
//  BTN1  long hold      → Reset to default         (newScene + sendToDevice)
//  BTN2  short tap      → Disconnect
//  BTN2  long hold      → Reconnect
//
//  Joy X right/left     → Opacity +/−              (all layers, app-side)
//  Joy Y up/down        → Brightness +/−           (ALL layers, FIRMWARE-side)
//                         brightness field in HID report mirrors the value
//  Joy short tap        → context-sensitive:
//                           Spotify     → Refresh now playing
//                           Slot machine→ Spin roulette
//                           Others      → no-op (spec: NaN)
//  Joy long hold        → context-sensitive:
//                           Spotify     → Shuffle / Unshuffle
//                           Others      → Edit / Save layer (select for editing)
//
//  BTN3-5 (Pomodoro context)
//    BTN3 short → Reset timer
//    BTN4 short → Start / Pause
//    BTN5 short → Next session
//
//  BTN3-5 (Spotify context)
//    BTN3 short → Previous song
//    BTN3 long  → Volume −
//    BTN4 short → Play / Pause
//    BTN5 short → Next song
//    BTN5 long  → Volume +
//
// ── FIX SUMMARY ──────────────────────────────────────────────────────────────
//
//  Bug 1 (FIXED): serialServiceProvider created LibSerialPortService() on all
//    desktop platforms, but LibSerialPortService was aliased to Win32SerialService
//    in serial_desktop.dart, so macOS/Linux got the wrong (Windows-only) driver.
//    Now: Platform.isWindows → Win32SerialService
//         Platform.isMacOS || Platform.isLinux → LibSerialPortService
//         web / other → StubSerialService
//
//  Bug 2 (FIXED): sendToDevice() returned silently with no UI feedback when
//    deviceLocked == true. It now sets an error message so the user knows why
//    the send was rejected.
//
//  Bug 3 (FIXED): older code-path called compute(_buildPacket, timeline) where
//    _buildPacket ignored clock / Spotify / Pomodoro state. Only
//    compute(_buildPacketFull, input) is used now, so the full header is always
//    assembled with live state from every active layer type.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';
import '../../engine/widgets/pomodoro_widget.dart';
import '../../features/export/frame_exporter.dart';
import '../../services/hid/hid_service.dart';
import '../../services/hid/hid_report.dart';
import '../../services/serial/serial_service.dart';
import '../../services/serial/serial_desktop.dart';
import '../../shared/providers/preset_provider.dart';
import '../../shared/providers/providers.dart';
import '../settings/settings_dialog.dart';
import 'connection_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Policy constants
// ─────────────────────────────────────────────────────────────────────────────

const int _kMaxAttempts             = 2;
const int _kBaudRate                = 921600;
const int _kBitsPerByte             = 10;
const int _kResponseFixedOverheadMs = 5000;
const int _kResponseMinTimeoutMs    = 8000;

/// Compute a response-wait timeout that scales with packet size.
///
/// At 921600 baud, 1.2 MB takes ~10 s to transmit; we add a 5 s overhead
/// for firmware CRC computation and USB scheduling jitter. The minimum of
/// 8 s covers small packets (clock-only or single-frame content).
int _responseTimeoutFor(int packetBytes) {
  final int txMs  = (packetBytes * _kBitsPerByte * 1000) ~/ _kBaudRate;
  final int total = txMs + _kResponseFixedOverheadMs;
  return total < _kResponseMinTimeoutMs ? _kResponseMinTimeoutMs : total;
}

const Duration _kPortSettleDelay    = Duration(milliseconds: 200);
const Duration _kPortReconnectDelay = Duration(milliseconds: 100);
const Duration _kPresetSendDebounce = Duration(milliseconds: 400);
const Duration _kJoySendDebounce    = Duration(milliseconds: 100);

/// Opacity delta per HID report tick (20 ms) → full sweep in ~1 s.
const double _kOpacityStep = 0.05;

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

/// FIX: previously returned LibSerialPortService() on ALL desktop platforms,
/// but LibSerialPortService was aliased to Win32SerialService — so macOS/Linux
/// silently got the Windows-only serial driver.
///
/// Now the dispatch is explicit and correct:
///   Windows          → Win32SerialService   (serial_port_win32)
///   macOS / Linux    → LibSerialPortService (flutter_libserialport)
///   web / other      → StubSerialService    (no-op)
final serialServiceProvider = Provider<SerialService>((ref) {
  if (!kIsWeb) {
    if (Platform.isWindows) return Win32SerialService();
    if (Platform.isMacOS || Platform.isLinux) return LibSerialPortService();
  }
  return StubSerialService();
});

final availablePortsProvider = FutureProvider<List<PortInfo>>((ref) async {
  return ref.watch(serialServiceProvider).availablePorts();
});

// ─────────────────────────────────────────────────────────────────────────────
// Packet build types and top-level isolate functions
//
// compute() spawns a background isolate. Only top-level or static functions
// can be passed to compute() — closures and instance methods are not sendable
// across isolate boundaries.
// ─────────────────────────────────────────────────────────────────────────────

typedef _PacketBuildInput = ({
  Timeline            timeline,
  int                 startPositionMs,
  int                 trackDurationMs,
  SpotifyLayout?      spotifyLayout,
  bool                showProgress,
  Color               progressColor,
  ClockLayer?         clockLayer,
  DateTime?           clockCommitTime,
  PomodoroLayer?      pomodoroLayer,
  PomodoroTimerState? pomodoroState,
});

/// Builds a full FRM packet including clock, Spotify, and Pomodoro header
/// fields. Used by [DeviceController.sendToDevice].
///
/// FIX: the old codebase had a bare _buildPacket(Timeline) that ignored all
/// layer state. This function always receives the full _PacketBuildInput so
/// the firmware header is populated correctly for every layer type.
Uint8List _buildPacketFull(_PacketBuildInput i) =>
    const FrameExporter().export(
      i.timeline,
      startPositionMs: i.startPositionMs,
      trackDurationMs: i.trackDurationMs,
      layout:          i.spotifyLayout,
      showProgress:    i.showProgress,
      progressColor:   i.progressColor,
      clockLayer:      i.clockLayer,
      clockCommitTime: i.clockCommitTime,
      pomodoroLayer:   i.pomodoroLayer,
      pomodoroState:   i.pomodoroState,
    );

/// Builds an FRM packet for the "next song" transition animation.
/// Only Spotify fields are relevant; clock/pomodoro fields are zeroed.
Uint8List _buildNextSongPacket(_PacketBuildInput i) =>
    const FrameExporter().exportNext(
      i.timeline,
      startPositionMs: i.startPositionMs,
      trackDurationMs: i.trackDurationMs,
      layout:          i.spotifyLayout,
      showProgress:    i.showProgress,
      progressColor:   i.progressColor,
    );

// ─────────────────────────────────────────────────────────────────────────────
// DeviceController
// ─────────────────────────────────────────────────────────────────────────────

class DeviceController extends Notifier<DeviceConnectionState> {

  final FrameonHidService _hid = FrameonHidService();
  StreamSubscription<FrameonHidReport>? _hidSub;

  Timer? _presetSendTimer;
  Timer? _joySendTimer;
  bool   _pendingSend = false;

  // Joystick X centre — auto-calibrated from the first 30 idle reports.
  // Joystick Y is handled entirely by firmware (brightness).
  int _joyCentreX = 2047;
  int _calibN     = 0;

  @override
  DeviceConnectionState build() {
    ref.onDispose(() {
      _hidSub?.cancel();
      _hid.close();
      _presetSendTimer?.cancel();
      _joySendTimer?.cancel();
    });
    return const DeviceConnectionState();
  }

  SerialService get _serial => ref.read(serialServiceProvider);

  // ── Public API ─────────────────────────────────────────────────────────────

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

  Future<void> connect(String portName) async {
    try { await _serial.disconnect(); } catch (_) {}
    await Future<void>.delayed(_kPortReconnectDelay);

    state = state.copyWith(
      status:       DeviceConnectionStatus.connecting,
      portName:     portName,
      errorMessage: null,
    );

    try {
      final int baudRate = ref.read(settingsProvider).baudRate;
      await _serial.connect(portName, baudRate: baudRate);
      state = state.copyWith(status: DeviceConnectionStatus.connected);

      // Subscribe to HID reports (physical controller input).
      await _hidSub?.cancel();
      final hidOk = await _hid.open();
      if (hidOk) {
        _hidSub = _hid.reports.listen(_onHidReport, cancelOnError: false);
      }
    } catch (e) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
        errorMessage: 'Connect failed: $e',
      );
    }
  }

  Future<void> disconnect() async {
    _presetSendTimer?.cancel();
    _joySendTimer?.cancel();
    await _hidSub?.cancel();
    _hidSub = null;
    await _hid.close();
    try { await _serial.disconnect(); } catch (_) {}
    state = state.copyWith(
      status:           DeviceConnectionStatus.disconnected,
      portName:         null,
      errorMessage:     null,
      sendProgress:     0,
      deviceLocked:     false,   // FIX: reset lock on disconnect; firmware resets on reconnect
      deviceBrightness: 128,     // FIX: reset to DEFAULT_BRIGHTNESS; stale value confused the UI
    );
  }

  /// Export the current timeline and stream it to the connected device.
  ///
  /// ## Why compute() is used
  ///
  /// [FrameExporter.export] builds the full binary packet synchronously:
  ///   - Copies all RGB565 frame data (up to ~1.2 MB) into one Uint8List
  ///   - Runs CRC-16/CCITT over every byte in a tight CPU loop
  ///
  /// Running this on the UI thread freezes the app and produces the
  /// "Reported frame time is older than the last one" debug error.
  /// `compute(_buildPacketFull, input)` offloads it to a background isolate.
  ///
  /// ## Retry policy
  ///
  /// - 1 initial attempt + 1 automatic retry on NAK = 2 total ([_kMaxAttempts]).
  /// - Human-readable error on ERR, second NAK, or response timeout.
  Future<void> sendToDevice() async {
    // FIX: previously returned silently when locked, giving the user no
    // feedback. Now sets a visible error so they know why nothing happened.
    if (state.deviceLocked) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
        errorMessage: 'Display is locked. Long-hold the encoder to unlock.',
      );
      return;
    }

    if (state.isSending) {
      _pendingSend = true;
      return;
    }

    if (!state.isConnected) return;

    final Timeline? timeline = ref.read(timelineProvider).value;
    if (timeline == null || timeline.frameCount == 0) {
      state = state.copyWith(
        status:       DeviceConnectionStatus.error,
        errorMessage: 'Nothing to send — add content to the canvas first.',
      );
      return;
    }

    state = state.copyWith(
      status:       DeviceConnectionStatus.sending,
      sendProgress: 0,
      errorMessage: null,
    );

    try {
      // FIX: always use _buildPacketFull so clock / Spotify / Pomodoro header
      // fields are populated. The old _buildPacket(timeline) path that stripped
      // all layer state has been removed.
      final _PacketBuildInput input = _gatherPacketState(timeline);
      final Uint8List packet        = await compute(_buildPacketFull, input);

      await _sendWithRetry(packet);

      state = state.copyWith(
        status:       DeviceConnectionStatus.connected,
        sendProgress: 1.0,
        errorMessage: null,
      );

      if (_pendingSend) {
        _pendingSend = false;
        sendToDevice();
      }
    } on SerialException catch (e) {
      _pendingSend = false;
      await _failGracefully(e.message);
    } catch (e) {
      _pendingSend = false;
      await _failGracefully('Unexpected error: $e');
    }
  }

  Future<void> sendNextSong(
    Timeline timeline, {
    required int startPositionMs,
    required int trackDurationMs,
  }) async {
    if (!state.isConnected)       return;
    if (timeline.frameCount == 0) return;
    if (state.isSending)          return;
    try {
      final base = _gatherPacketState(timeline);
      final _PacketBuildInput input = (
        timeline:        base.timeline,
        startPositionMs: startPositionMs,
        trackDurationMs: trackDurationMs,
        spotifyLayout:   base.spotifyLayout,
        showProgress:    base.showProgress,
        progressColor:   base.progressColor,
        clockLayer:      base.clockLayer,
        clockCommitTime: base.clockCommitTime,
        pomodoroLayer:   base.pomodoroLayer,
        pomodoroState:   base.pomodoroState,
      );
      final Uint8List packet = await compute(_buildNextSongPacket, input);
      await _sendWithRetry(packet);
    } catch (_) {}
  }

  // ── HID report handler ─────────────────────────────────────────────────────

  void _onHidReport(FrameonHidReport r) {
    // Auto-calibrate joystick X centre from the first 30 idle samples.
    if (_calibN < 30 && r.encDelta == 0 && r.buttons == 0 && r.taps == 0) {
      _joyCentreX = ((_joyCentreX * _calibN + r.joyX) / (_calibN + 1)).round();
      _calibN++;
    }

    // ── Encoder: preset navigation ──────────────────────────────────────────
    if (r.encDelta != 0) _switchPresetBy(r.encDelta > 0 ? 1 : -1);

    // Encoder long: toggle display lock. Firmware already applied it;
    // we mirror it here so sendToDevice() can check state.deviceLocked.
    if (r.encLong) state = state.copyWith(deviceLocked: !state.deviceLocked);

    // ── Brightness: mirror firmware-applied value ──────────────────────────
    if (r.brightness != state.deviceBrightness) {
      state = state.copyWith(deviceBrightness: r.brightness);
    }

    // ── Joystick X → opacity (all layers) ──────────────────────────────────
    final normX = r.normJoyX(_joyCentreX);
    if (normX > 0.5)        _applyLayerOpacity(_kOpacityStep);
    else if (normX < -0.5)  _applyLayerOpacity(-_kOpacityStep);

    // ── Joystick tap / long hold ────────────────────────────────────────────
    if (r.joyTap)  _handleJoyTap();
    if (r.joyLong) _handleJoyHold();

    // ── BTN1: Sync display (short) / Reset to default (long) ───────────────
    if (r.btn1Tap) sendToDevice();
    if (r.btn1Long) {
      ref.read(sceneProvider.notifier).newScene();
      sendToDevice();
    }

    // ── BTN2: Disconnect (short) / Reconnect (long) ─────────────────────────
    if (r.btn2Tap) disconnect();
    if (r.btn2Long) {
      final p = state.portName;
      if (p != null) connect(p);
    }

    // ── BTN3-5: Pomodoro or Spotify context ────────────────────────────────
    _handleContextButtons(r);
  }

  // ── Context-sensitive joystick tap ─────────────────────────────────────────

  void _handleJoyTap() {
    final scene = ref.read(sceneProvider);
    final spotifyLayers = scene.visibleLayers.whereType<SpotifyLayer>();
    final slotLayers    = scene.visibleLayers.whereType<SlotMachineLayer>();

    if (spotifyLayers.isNotEmpty) {
      ref.read(spotifyServiceProvider.notifier).refresh();
    } else if (slotLayers.isNotEmpty) {
      ref.read(slotMachineServiceProvider.notifier).spin(slotLayers.first);
    }
    // Other layers: spec says NaN — no action.
  }

  // ── Context-sensitive joystick long hold ───────────────────────────────────

  void _handleJoyHold() {
    final scene      = ref.read(sceneProvider);
    final hasSpotify = scene.visibleLayers.whereType<SpotifyLayer>().isNotEmpty;

    if (hasSpotify) {
      ref.read(spotifyServiceProvider.notifier).toggleShuffle();
    } else {
      final targetId = _joystickTargetLayerId();
      if (targetId != null) {
        ref.read(sceneProvider.notifier).selectLayer(targetId);
      }
    }
  }

  // ── Context-sensitive BTN3-5 ───────────────────────────────────────────────

  void _handleContextButtons(FrameonHidReport r) {
    final scene = ref.read(sceneProvider);

    // Pomodoro takes priority when a Pomodoro layer is visible.
    final pomodoroLayers = scene.visibleLayers.whereType<PomodoroLayer>();
    if (pomodoroLayers.isNotEmpty) {
      final layer = pomodoroLayers.first;
      final pomo  = ref.read(pomodoroServiceProvider.notifier);
      if (r.btn3Tap) pomo.reset(layer);
      if (r.btn4Tap) pomo.togglePlayPause(layer);
      if (r.btn5Tap) pomo.skip(layer);
      return;
    }

    // Spotify context.
    final hasSpotify = scene.visibleLayers.whereType<SpotifyLayer>().isNotEmpty;
    if (hasSpotify) {
      final spotify = ref.read(spotifyServiceProvider.notifier);
      if (r.btn3Tap)  spotify.skipPrevious();
      if (r.btn3Long) spotify.volumeDown();
      if (r.btn4Tap)  spotify.togglePlayPause();
      if (r.btn5Tap)  spotify.skipNext();
      if (r.btn5Long) spotify.volumeUp();
    }
    // Other layers: BTN3-5 unassigned.
  }

  // ── Preset navigation ──────────────────────────────────────────────────────

  void _switchPresetBy(int delta) {
    final preset     = ref.read(presetProvider);
    final slots      = preset.slots;
    final currentIdx = slots.indexOf(preset.activeSlot);
    if (currentIdx == -1) return;

    final nextIdx = (currentIdx + delta).clamp(0, slots.length - 1);
    if (nextIdx == currentIdx) return;

    final nextSlot = slots[nextIdx];
    final scene    = ref.read(presetProvider.notifier).switchTo(nextSlot);
    if (scene != null) {
      ref.read(sceneProvider.notifier).loadScene(scene);
    }

    // Debounce the send so rapid encoder spins don't spam the device.
    _presetSendTimer?.cancel();
    _presetSendTimer = Timer(_kPresetSendDebounce, sendToDevice);
  }

  // ── Joystick opacity helpers ───────────────────────────────────────────────

  String? _joystickTargetLayerId() {
    final selectedId = ref.read(selectedLayerIdProvider);
    if (selectedId != null) return selectedId;
    final visible = ref.read(sceneProvider).visibleLayers;
    return visible.isNotEmpty ? visible.last.id : null;
  }

  void _applyLayerOpacity(double delta) {
    final targetId = _joystickTargetLayerId();
    if (targetId == null) return;

    final scene = ref.read(sceneProvider);
    final layer = scene.layerById(targetId);
    if (layer == null) return;

    final newOpacity = (layer.opacity + delta).clamp(0.0, 1.0);
    ref.read(sceneProvider.notifier).updateLayer(layer.copyWith(opacity: newOpacity));
    _armJoySend();
  }

  void _armJoySend() {
    _joySendTimer?.cancel();
    _joySendTimer = Timer(_kJoySendDebounce, sendToDevice);
  }

  // ── Packet state gathering ─────────────────────────────────────────────────

  _PacketBuildInput _gatherPacketState(Timeline timeline) {
    final scene   = ref.read(sceneProvider);
    final spotify = ref.read(spotifyServiceProvider);

    final SpotifyLayer? spotifyLayer = scene.visibleLayers
        .whereType<SpotifyLayer>().cast<SpotifyLayer?>().firstOrNull;
    final ClockLayer? clockLayer = scene.visibleLayers
        .whereType<ClockLayer>().cast<ClockLayer?>().firstOrNull;
    final DateTime? clockCommitTime =
        clockLayer != null ? DateTime.now() : null;
    final PomodoroLayer? pomodoroLayer = scene.visibleLayers
        .whereType<PomodoroLayer>().cast<PomodoroLayer?>().firstOrNull;
    final PomodoroTimerState? pomodoroState =
        pomodoroLayer != null ? ref.read(pomodoroServiceProvider) : null;

    return (
      timeline:        timeline,
      startPositionMs: spotify.isConnected
          ? spotify.livePosition.inMilliseconds
          : 0,
      trackDurationMs: spotify.isConnected
          ? spotify.currentDuration.inMilliseconds
          : 0,
      spotifyLayout:   spotifyLayer?.layout,
      showProgress:    spotifyLayer?.showProgress ?? false,
      progressColor:   spotifyLayer?.progressColor ?? const Color(0xFF21C32C),
      clockLayer:      clockLayer,
      clockCommitTime: clockCommitTime,
      pomodoroLayer:   pomodoroLayer,
      pomodoroState:   pomodoroState,
    );
  }

  // ── Error handling ─────────────────────────────────────────────────────────

  Future<void> _failGracefully(String message) async {
    try { await _serial.disconnect(); } catch (_) {}
    await Future<void>.delayed(_kPortSettleDelay);
    state = state.copyWith(
      status:       DeviceConnectionStatus.error,
      errorMessage: message,
      sendProgress: 0,
    );
  }

  // ── Send with retry ────────────────────────────────────────────────────────

  Future<void> _sendWithRetry(Uint8List packet) async {
    final int timeoutMs = _responseTimeoutFor(packet.length);

    for (int attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      if (attempt > 1) state = state.copyWith(sendProgress: 0);

      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );

      final int? response = await _serial.readResponseByte(
        timeoutMs: timeoutMs,
      );

      switch (response) {
        case kFirmwareAck:
          return; // success — caller updates state

        case kFirmwareNak:
          if (attempt < _kMaxAttempts) continue; // retry once
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
            '${timeoutMs ~/ 1000} s. '
            'Check the connection and try again.',
          );

        default:
          throw SerialException(
            'Unexpected response byte: '
            '0x${response!.toRadixString(16).toUpperCase()}. '
            'This is likely a firmware debug message on the serial line.',
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