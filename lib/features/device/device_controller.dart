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

int _responseTimeoutFor(int packetBytes) {
  final int tx    = (packetBytes * _kBitsPerByte * 1000) ~/ _kBaudRate;
  final int total = tx + _kResponseFixedOverheadMs;
  return total < _kResponseMinTimeoutMs ? _kResponseMinTimeoutMs : total;
}

const Duration _kPortSettleDelay    = Duration(milliseconds: 200);
const Duration _kPortReconnectDelay = Duration(milliseconds: 100);
const Duration _kPresetSendDebounce = Duration(milliseconds: 400);
const Duration _kJoySendDebounce    = Duration(milliseconds: 100);
const double   _kOpacityStep        = 0.05; // per HID report (20 ms → 0→1 in ~1 s)

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final serialServiceProvider = Provider<SerialService>((ref) {
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return LibSerialPortService();
  }
  return StubSerialService();
});

final availablePortsProvider = FutureProvider<List<PortInfo>>((ref) async {
  return ref.watch(serialServiceProvider).availablePorts();
});

// ─────────────────────────────────────────────────────────────────────────────
// Packet build types
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

  // Joystick X centre — auto-calibrated from first idle reports.
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
        status: DeviceConnectionStatus.error,
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
      status:       DeviceConnectionStatus.disconnected,
      portName:     null,
      errorMessage: null,
      sendProgress: 0,
    );
  }

  Future<void> sendToDevice() async {
    if (state.deviceLocked) return;

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
      final _PacketBuildInput input = _gatherPacketState(timeline);
      final Uint8List packet = await compute(_buildPacketFull, input);
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
    // (Y is handled by firmware — no calibration needed on app side.)
    if (_calibN < 30 && r.encDelta == 0 && r.buttons == 0 && r.taps == 0) {
      _joyCentreX = ((_joyCentreX * _calibN + r.joyX) / (_calibN + 1)).round();
      _calibN++;
    }

    // ── Encoder: preset navigation ─────────────────────────────────────────
    if (r.encDelta != 0)  _switchPresetBy(r.encDelta > 0 ? 1 : -1);
    // Encoder long: toggle display lock (firmware already applied it;
    // we mirror it here so the app respects the lock).
    if (r.encLong) state = state.copyWith(deviceLocked: !state.deviceLocked);

    // ── Brightness: mirror firmware-applied value into connection state ────
    // Firmware owns brightness; we just reflect it so the UI indicator stays
    // in sync with what the matrix is actually showing.
    if (r.brightness != state.deviceBrightness) {
      state = state.copyWith(deviceBrightness: r.brightness);
    }

    // ── Joystick X → opacity (all layers) ─────────────────────────────────
    final normX = r.normJoyX(_joyCentreX);
    if (normX > 0.5)       _applyLayerOpacity(_kOpacityStep);
    else if (normX < -0.5) _applyLayerOpacity(-_kOpacityStep);

    // ── Joystick tap → context-sensitive (spec: NaN / Spotify / SlotMachine)
    if (r.joyTap)  _handleJoyTap();

    // ── Joystick long hold → context-sensitive (Edit/Save or Spotify shuffle)
    if (r.joyLong) _handleJoyHold();

    // ── BTN1: Sync display (short) / Reset to default (long) ──────────────
    if (r.btn1Tap)  sendToDevice();
    if (r.btn1Long) {
      ref.read(sceneProvider.notifier).newScene();
      sendToDevice();
    }

    // ── BTN2: Disconnect (short) / Reconnect (long) ────────────────────────
    if (r.btn2Tap)  disconnect();
    if (r.btn2Long) { final p = state.portName; if (p != null) connect(p); }

    // ── BTN3-5: Pomodoro or Spotify context ───────────────────────────────
    _handleContextButtons(r);
  }

  // ── Context-sensitive joystick tap ─────────────────────────────────────────
  void _handleJoyTap() {
    final scene = ref.read(sceneProvider);

    final spotifyLayers    = scene.visibleLayers.whereType<SpotifyLayer>();
    final slotLayers       = scene.visibleLayers.whereType<SlotMachineLayer>();

    if (spotifyLayers.isNotEmpty) {
      // Spotify: Refresh now playing
      ref.read(spotifyServiceProvider.notifier).refresh();
    } else if (slotLayers.isNotEmpty) {
      // Slot machine: Spin roulette
      ref.read(slotMachineServiceProvider.notifier).spin(slotLayers.first);
    }
    // Other layers: spec says NaN — no action.
  }

  // ── Context-sensitive joystick long hold ───────────────────────────────────
  void _handleJoyHold() {
    final scene      = ref.read(sceneProvider);
    final hasSpotify = scene.visibleLayers.whereType<SpotifyLayer>().isNotEmpty;

    if (hasSpotify) {
      // Spotify: Shuffle / Unshuffle
      ref.read(spotifyServiceProvider.notifier).toggleShuffle();
    } else {
      // All other layers: Edit / Save layer
      // — selects the joystick-target layer in the editor panel.
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
      if (r.btn3Tap) pomo.reset(layer);           // Reset timer
      if (r.btn4Tap) pomo.togglePlayPause(layer); // Start / Pause
      if (r.btn5Tap) pomo.skip(layer);            // Next session
      return;
    }

    // Spotify context.
    final hasSpotify = scene.visibleLayers.whereType<SpotifyLayer>().isNotEmpty;
    if (hasSpotify) {
      final spotify = ref.read(spotifyServiceProvider.notifier);
      if (r.btn3Tap)  spotify.skipPrevious();    // Previous song
      if (r.btn3Long) spotify.volumeDown();      // Volume −
      if (r.btn4Tap)  spotify.togglePlayPause(); // Play / Pause
      if (r.btn5Tap)  spotify.skipNext();        // Next song
      if (r.btn5Long) spotify.volumeUp();        // Volume +
    }
    // Other layers: BTN3-5 unassigned (spec has no entry).
  }

  // ── Encoder debounce ───────────────────────────────────────────────────────

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
    final DateTime? clockCommitTime = clockLayer != null ? DateTime.now() : null;
    final PomodoroLayer? pomodoroLayer = scene.visibleLayers
        .whereType<PomodoroLayer>().cast<PomodoroLayer?>().firstOrNull;
    final PomodoroTimerState? pomodoroState =
        pomodoroLayer != null ? ref.read(pomodoroServiceProvider) : null;

    return (
      timeline:        timeline,
      startPositionMs: spotify.isConnected ? spotify.livePosition.inMilliseconds : 0,
      trackDurationMs: spotify.isConnected ? spotify.currentDuration.inMilliseconds : 0,
      spotifyLayout:   spotifyLayer?.layout,
      showProgress:    spotifyLayer?.showProgress ?? false,
      progressColor:   spotifyLayer?.progressColor ?? const Color(0xFF21C32C),
      clockLayer:      clockLayer,
      clockCommitTime: clockCommitTime,
      pomodoroLayer:   pomodoroLayer,
      pomodoroState:   pomodoroState,
    );
  }

  Future<void> _failGracefully(String message) async {
    try { await _serial.disconnect(); } catch (_) {}
    await Future<void>.delayed(_kPortSettleDelay);
    state = state.copyWith(
      status:       DeviceConnectionStatus.error,
      errorMessage: message,
      sendProgress: 0,
    );
  }

  Future<void> _sendWithRetry(Uint8List packet) async {
    final int timeoutMs = _responseTimeoutFor(packet.length);
    for (int attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      if (attempt > 1) state = state.copyWith(sendProgress: 0);
      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );
      final int? response = await _serial.readResponseByte(timeoutMs: timeoutMs);
      switch (response) {
        case kFirmwareAck:
          return;
        case kFirmwareNak:
          if (attempt < _kMaxAttempts) continue;
          throw const SerialException('CRC mismatch after retry. Check the USB cable.');
        case kFirmwareErr:
          throw const SerialException('Device rejected the packet. Update firmware.');
        case null:
          throw SerialException('No response within ${timeoutMs ~/ 1000} s.');
        default:
          throw SerialException(
            'Unexpected response: 0x${response.toRadixString(16).toUpperCase()}.');
      }
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);