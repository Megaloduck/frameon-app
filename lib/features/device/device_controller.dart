// lib/features/device/device_controller.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DeviceController — v3
//
// Encoder (preset switcher)
// ─────────────────────────
//   Each encoder step fires _switchPresetBy(±1) which updates the preset
//   state immediately for instant UI feedback, then arms a 400 ms debounce
//   timer.  Only when the timer fires (user stops turning) is sendToDevice()
//   called.  This prevents the "two presets overlapping" bug caused by
//   mechanical bounce firing 2–3 events per click and sending multiple
//   partially-overlapping FRM packets to the device.
//
// Joystick (display modifier — layer z-order + opacity)
// ──────────────────────────────────────────────────────
//   joyLayerPrev → bringForward(selectedLayer) → debouncedSend (100 ms)
//   joyLayerNext → sendBackward(selectedLayer) → debouncedSend (100 ms)
//   opacityUp    → opacity + 0.1 on selected layer → debouncedSend
//   opacityDown  → opacity − 0.1 on selected layer → debouncedSend
//   joyPress     → toggleVisibility(selectedLayer)  → debouncedSend
//
//   A short 100 ms send-debounce on the joystick prevents a flood of FRM
//   packets when the user holds the joystick — only one packet per gesture.
//
// Push buttons (fixed controls)
// ─────────────────────────────
//   btn1Sync       → sendToDevice() immediately
//   btn1Reset      → newScene() + send
//   btn2Disconnect → disconnect()
//   btn2Reconnect  → connect(lastPort)
//   btn3-5         → ephemeral; Pomodoro / Spotify feature widgets subscribe
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
import '../../services/serial/serial_service.dart';
import '../../services/serial/serial_desktop.dart';
import '../../shared/providers/preset_provider.dart';
import '../../shared/providers/providers.dart';
import '../settings/settings_dialog.dart';
import 'connection_state.dart';
import 'device_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Policy constants
// ─────────────────────────────────────────────────────────────────────────────

const int _kMaxAttempts             = 2;
const int _kBaudRate                = 921600;
const int _kBitsPerByte             = 10;
const int _kResponseFixedOverheadMs = 5000;
const int _kResponseMinTimeoutMs    = 8000;

int _responseTimeoutFor(int packetBytes) {
  final int txMs = (packetBytes * _kBitsPerByte * 1000) ~/ _kBaudRate;
  final int total = txMs + _kResponseFixedOverheadMs;
  return total < _kResponseMinTimeoutMs ? _kResponseMinTimeoutMs : total;
}

const Duration _kPortSettleDelay    = Duration(milliseconds: 200);
const Duration _kPortReconnectDelay = Duration(milliseconds: 100);

/// How long after the last encoder step before sending the packet.
/// Prevents mechanical bounce from triggering multiple sends per click.
const Duration _kPresetSendDebounce = Duration(milliseconds: 400);

/// How long after the last joystick movement before sending the packet.
/// Prevents a flood of FRM packets while the joystick is held.
const Duration _kJoySendDebounce    = Duration(milliseconds: 100);

/// Opacity step applied per joystick X tick.
const double _kOpacityStep = 0.1;

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

Uint8List _buildPacketFull(_PacketBuildInput input) =>
    const FrameExporter().export(
      input.timeline,
      startPositionMs: input.startPositionMs,
      trackDurationMs: input.trackDurationMs,
      layout:          input.spotifyLayout,
      showProgress:    input.showProgress,
      progressColor:   input.progressColor,
      clockLayer:      input.clockLayer,
      clockCommitTime: input.clockCommitTime,
      pomodoroLayer:   input.pomodoroLayer,
      pomodoroState:   input.pomodoroState,
    );

Uint8List _buildNextSongPacket(_PacketBuildInput input) =>
    const FrameExporter().exportNext(
      input.timeline,
      startPositionMs: input.startPositionMs,
      trackDurationMs: input.trackDurationMs,
      layout:          input.spotifyLayout,
      showProgress:    input.showProgress,
      progressColor:   input.progressColor,
    );

// ─────────────────────────────────────────────────────────────────────────────
// DeviceController
// ─────────────────────────────────────────────────────────────────────────────

class DeviceController extends Notifier<DeviceConnectionState> {
  StreamSubscription<DeviceEvent>? _eventSub;

  /// Debounce timer for encoder preset switching.
  /// Arms on each step; fires sendToDevice() when user stops turning.
  Timer? _presetSendTimer;

  /// Debounce timer for joystick layer / opacity changes.
  /// Arms on each joystick movement; fires sendToDevice() when joystick rests.
  Timer? _joySendTimer;

  /// Set to true when sendToDevice() is called while a send is already in
  /// progress.  The running send checks this flag on completion and re-triggers
  /// so no controller action is silently dropped.
  bool _pendingSend = false;

  @override
  DeviceConnectionState build() {
    ref.onDispose(() {
      _cancelEventSub();
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

      await _cancelEventSub();
      _eventSub = _serial.deviceEvents.listen(
        _onDeviceEvent,
        onError: (_) {},
        cancelOnError: false,
      );
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
    await _cancelEventSub();
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

    // ── Guard: if a send is already running, mark as pending and return.
    // The running send will re-trigger when it finishes (see below).
    // This ensures no controller action is silently dropped — the LAST
    // requested state always makes it to the device.
    if (state.isSending) {
      _pendingSend = true;
      return;
    }

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

      // ── Re-trigger if a controller action arrived while we were sending.
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

  // ── EVT event handler ──────────────────────────────────────────────────────

  void _onDeviceEvent(DeviceEvent event) {
    switch (event.kind) {

      // ── Encoder: preset navigation ────────────────────────────────────────
      case DeviceEventKind.presetNext:
        _switchPresetBy(1);

      case DeviceEventKind.presetPrev:
        _switchPresetBy(-1);

      case DeviceEventKind.presetCheck:
        break; // preset name already visible in UI

      case DeviceEventKind.lockToggle:
        state = state.copyWith(deviceLocked: event.value == 1);

      // ── Joystick Y-axis: layer z-order ────────────────────────────────────
      case DeviceEventKind.joyLayerPrev:
        // Joystick UP → bringForward the selected layer (moves it toward front)
        _applyLayerZOrder(forward: true);

      case DeviceEventKind.joyLayerNext:
        // Joystick DOWN → sendBackward the selected layer (moves it toward back)
        _applyLayerZOrder(forward: false);

      // ── Joystick X-axis: selected layer opacity ────────────────────────────
      case DeviceEventKind.opacityUp:
        _applyLayerOpacity(_kOpacityStep);

      case DeviceEventKind.opacityDown:
        _applyLayerOpacity(-_kOpacityStep);

      // ── Joystick button ───────────────────────────────────────────────────
      case DeviceEventKind.joyPress:
        // Toggle visibility of the selected (or topmost) layer
        _applyLayerToggleVisibility();

      case DeviceEventKind.joyHold:
        // Save/confirm — treat as an immediate sync
        sendToDevice();

      case DeviceEventKind.joyCenter:
        break; // no action; joystick returned to rest

      // ── BTN1 / BTN2 — Global ─────────────────────────────────────────────
      case DeviceEventKind.btn1Sync:
        sendToDevice();

      case DeviceEventKind.btn1Reset:
        ref.read(sceneProvider.notifier).newScene();
        sendToDevice();

      case DeviceEventKind.btn2Disconnect:
        disconnect();

      case DeviceEventKind.btn2Reconnect:
        final port = state.portName;
        if (port != null) connect(port);

      // ── BTN3-5 — Ephemeral; feature widgets subscribe to deviceEvents ─────
      case DeviceEventKind.btn3Short:
      case DeviceEventKind.btn3Long:
      case DeviceEventKind.btn4Short:
      case DeviceEventKind.btn4Long:
      case DeviceEventKind.btn5Short:
      case DeviceEventKind.btn5Long:
        break;
    }
  }

  // ── Encoder helpers ────────────────────────────────────────────────────────

  /// Update the preset selection immediately (instant UI feedback), then arm
  /// the debounce timer.  The actual send happens only after the user stops
  /// turning the encoder for [_kPresetSendDebounce].  This prevents the
  /// "two presets overlapping" bug from mechanical bounce.
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

    // Arm (or restart) the send-debounce timer.
    _presetSendTimer?.cancel();
    _presetSendTimer = Timer(_kPresetSendDebounce, sendToDevice);
  }

  // ── Joystick helpers ───────────────────────────────────────────────────────

  /// Returns the ID of the joystick target layer:
  ///   1. The layer selected in the layer panel  (selectedLayerIdProvider)
  ///   2. Fallback: the topmost visible layer in the scene
  String? _joystickTargetLayerId() {
    // selectedLayerIdProvider is a separate provider — SceneNotifier does not
    // expose selectedLayerId directly.
    final selectedId = ref.read(selectedLayerIdProvider);
    if (selectedId != null) return selectedId;

    // Fall back to the topmost visible layer.
    final visible = ref.read(sceneProvider).visibleLayers;
    return visible.isNotEmpty ? visible.last.id : null;
  }

  /// Move the joystick-targeted layer forward or backward in z-order.
  ///
  /// SceneNotifier only exposes reorderLayer(from, to) which applies
  /// Flutter's ReorderableListView off-by-one adjustment internally.
  /// To avoid that ambiguity we work directly on the immutable Scene model
  /// (scene.bringForward / scene.sendBackward) and then push the new scene
  /// via loadScene + re-select — two synchronous state writes that Riverpod
  /// batches into a single frame.
  void _applyLayerZOrder({required bool forward}) {
    final targetId = _joystickTargetLayerId();
    if (targetId == null) return;

    final scene    = ref.read(sceneProvider);
    final newScene = forward ? scene.bringForward(targetId) : scene.sendBackward(targetId);

    // identical() is true when the layer was already at the boundary —
    // skip the write and the send in that case.
    if (identical(newScene, scene)) return;

    final notifier = ref.read(sceneProvider.notifier);
    notifier.loadScene(newScene);       // applies the reordered layer list
    notifier.selectLayer(targetId);     // restore selection (loadScene clears it)
    _armJoySend();
  }

  /// Adjust the opacity of the joystick-targeted layer by [delta] (±0.1),
  /// clamped to [0.0, 1.0], then arm the send debounce.
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

  /// Toggle visibility of the joystick-targeted layer, then send immediately.
  void _applyLayerToggleVisibility() {
    final targetId = _joystickTargetLayerId();
    if (targetId == null) return;
    ref.read(sceneProvider.notifier).toggleVisibility(targetId);
    sendToDevice();
  }

  /// Arms (or restarts) the 100 ms joystick send-debounce timer.
  void _armJoySend() {
    _joySendTimer?.cancel();
    _joySendTimer = Timer(_kJoySendDebounce, sendToDevice);
  }

  Future<void> _cancelEventSub() async {
    await _eventSub?.cancel();
    _eventSub = null;
  }

  // ── Packet state ──────────────────────────────────────────────────────────

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
    await _cancelEventSub();
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

      final int? response =
          await _serial.readResponseByte(timeoutMs: timeoutMs);

      switch (response) {
        case kFirmwareAck:
          return;
        case kFirmwareNak:
          if (attempt < _kMaxAttempts) continue;
          throw const SerialException('CRC mismatch after retry. Check the USB cable or try re-sending.');
        case kFirmwareErr:
          throw const SerialException('Device rejected the packet (wrong dimensions or protocol version). Update the firmware and try again.');
        case null:
          final mb = (packet.length / 1024 / 1024).toStringAsFixed(2);
          throw SerialException('No response within ${timeoutMs ~/ 1000} s (packet $mb MB). Check the cable and try again.');
        default:
          throw SerialException('Unexpected response byte: 0x${response.toRadixString(16).toUpperCase()}.');
      }
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);