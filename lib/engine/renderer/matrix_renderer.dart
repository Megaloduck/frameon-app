import 'dart:typed_data';
import 'dart:ui';

import '../scene/layer.dart';
import '../scene/scene.dart';
import '../scene/timeline.dart';
import '../widgets/clock_widget.dart';
import '../widgets/gif_widget.dart';
import '../widgets/pomodoro_widget.dart';
import '../widgets/spotify_widget.dart';
import '../widgets/text_widget.dart';
import '../widgets/finance_widget.dart';
import '../widgets/slot_machine_widget.dart';
import '../../services/finance/finance_service.dart';
import 'gif_decoder.dart';
import 'pixel_buffer.dart';
import 'rgb565_encoder.dart';

/// Central compositing engine. No dart:io — runs on all platforms.
///
/// Two rendering modes:
///
///   1. [renderFrameBuffer] — renders a single frame at [elapsedMs] into a
///      [PixelBuffer]. Used by the live preview. No RGB565 encoding, no frame
///      count needed, no cap. Always reflects the current state of live layers
///      (clock, Spotify, Pomodoro).
///
///   2. [render] — pre-renders a fixed-length [Timeline] of RGB565-encoded
///      frames for device export. The ESP32 loops through these independently
///      after receiving them over serial.
///
///      Clock layers: each frame is rendered with a per-frame [DateTime]
///      snapshot (now + i * frameDurationMs) so that seconds advance correctly
///      across the baked loop, with no risk of running backwards on loop reset.
///
///      IMPORTANT: [render] yields to the event loop after every frame via
///      `await Future.delayed(Duration.zero)`. Without this, the method
///      occupies the UI thread for the full render duration (potentially
///      hundreds of frames × pixel blending + RGB565 encoding), causing the
///      app to freeze and Flutter to report "frame time older than last one".
class MatrixRenderer {
  MatrixRenderer();

  static const _text     = TextWidget();
  static const _clock    = ClockWidget();
  static const _gif      = GifWidget();
  static const _spotify  = SpotifyWidget();
  static const _finance = FinanceWidget();
  static const _pomodoro = PomodoroWidget();
  static const _slotMachine = SlotMachineWidget();
  static const _decoder  = GifDecoder();

  final Rgb565Encoder _enc = const Rgb565Encoder();
  late Uint8List _encoded;

  // ── Asset registry ────────────────────────────────────────────────────────

  final Map<String, GifAsset?> _assetCache = {};

  void addAssetBytes(String key, Uint8List bytes, {bool force = false}) {
    if (!force && _assetCache[key] != null) return;
    _assetCache[key] = _decoder.decodeBytes(bytes);
  }

  void addAsset(String key, GifAsset? asset) {
    _assetCache[key] = asset;
  }

  void removeAsset(String key) => _assetCache.remove(key);

  // ── Live service state ────────────────────────────────────────────────────

  SpotifyTrack? currentTrack;
  FinanceData? currentFinance;
  PomodoroTimerState? currentPomodoroState;
  SlotMachineRuntimeState? currentSlotMachineState;

  // ── Live preview — single frame ───────────────────────────────────────────

  /// Render one frame at [elapsedMs] directly into a [PixelBuffer].
  ///
  /// This is the fast path used by the matrix preview. It avoids:
  ///   - RGB565 encoding then immediate decoding (wasteful round-trip)
  ///   - Pre-computing a frame count or loop length
  ///   - Any hard cap on animation length
  ///
  /// [currentTrack] and [currentPomodoroState] must be set before calling
  /// this if Spotify or Pomodoro layers are present.
  PixelBuffer renderFrameBuffer(Scene scene, int elapsedMs) {
    _ensureEntries(scene);
    final int w = scene.matrixWidth;
    final int h = scene.matrixHeight;
    final composite = PixelBuffer(width: w, height: h);
    for (final layer in scene.visibleLayers) {
      final lb = PixelBuffer(width: w, height: h);
      _renderLayer(layer, lb, elapsedMs);
      composite.blendOver(lb);
    }
    return composite;
  }

  // ── Device export — pre-rendered timeline ─────────────────────────────────

  /// Pre-render [frameCount] frames into an RGB565-encoded [Timeline].
  ///
  /// Used exclusively for device export. The ESP32 receives this packet and
  /// loops through it independently.
  ///
  /// Clock layers (v1.5): ClockWidget renders a transparent (blank) buffer
  /// during export — no clock pixels are baked. Instead the clock descriptor
  /// (epoch, timezone, flags, colors) travels in the packet header and the
  /// firmware renders the clock live via overdrawClock() on every frame using
  /// millis(). This means seconds, minutes, hours, blink-colon, and date are
  /// always accurate with no latency compensation and no loop-reset issues.
  Future<Timeline> render(
    Scene scene, {
    int frameDurationMs = 100,
    int frameCount = 33,
    ClockLayer? clockLayer,
    DateTime? clockCommitTime,
  }) async {
    final int w = scene.matrixWidth;
    final int h = scene.matrixHeight;
    _encoded = Uint8List(w * h * 2);
    _ensureEntries(scene);

    final timeline = Timeline();
    for (int i = 0; i < frameCount; i++) {
      final int t = i * frameDurationMs;

      final composite = PixelBuffer(width: w, height: h);
      for (final layer in scene.visibleLayers) {
        final lb = PixelBuffer(width: w, height: h);
        _renderLayer(layer, lb, t, isExport: true);
        composite.blendOver(lb);
      }
      _enc.encodeInto(composite, _encoded);
      timeline.addFrame(
        Frame(data: Uint8List.fromList(_encoded), durationMs: frameDurationMs),
      );

      // Yield to the event loop after every frame so Flutter's frame
      // scheduler can run and the UI stays responsive.
      await Future<void>.delayed(Duration.zero);
    }
    return timeline;
  }

  // ── Layer dispatch — live preview ─────────────────────────────────────────

  void _renderLayer(Layer layer, PixelBuffer buf, int t,
      {bool isExport = false}) {
    switch (layer.type) {
      case LayerType.text:
        _text.render(layer as TextLayer, buf, t);
      case LayerType.clock:
        // Live preview: ClockWidget reads DateTime.now() for accurate display.
        // Export path: isExport=true makes render() a no-op — the firmware
        // renders the clock live from the header descriptor (v1.5).
        _clock.render(layer as ClockLayer, buf, t, isExport: isExport);
      case LayerType.gif:
        final g = layer as GifLayer;
        _gif.renderWithAsset(
          g, buf, t,
          g.filePath != null ? _assetCache[g.filePath] : null,
        );
        case LayerType.spotify:
        final track = currentTrack;
        if (track != null) {
           _spotify.renderWithTrack(layer as SpotifyLayer, buf, t, track);
             } else {
                  // No Spotify connection — render() shows the idle animation
    // (pulsing music note + "SPOTIFY / NOT CONNECTED" scrolling text).
    _spotify.render(layer as SpotifyLayer, buf, t);
  }
  case LayerType.finance:
  _finance.renderWithData(
    layer as FinanceLayer,
    buf,
    t,
    currentFinance,
  );
  
      case LayerType.pomodoro:
        final p = layer as PomodoroLayer;
        final s = currentPomodoroState;
        if (s != null) {
          _pomodoro.renderWithState(p, buf, t, s, isExport: isExport);
        } else {
          _pomodoro.render(p, buf, t, isExport: isExport);
        }


      case LayerType.slotMachine:
  final s = currentSlotMachineState;
  if (s != null) {
    _slotMachine.renderWithState(
      layer as SlotMachineLayer, buf, t, s,
      isExport: isExport,
    );
  } else {
    _slotMachine.render(layer as SlotMachineLayer, buf, t);
  }
    }
  }

  void _ensureEntries(Scene scene) {
    for (final layer in scene.layers) {
      if (layer is GifLayer && layer.filePath != null) {
        _assetCache.putIfAbsent(layer.filePath!, () => null);
      }
    }
  }
}