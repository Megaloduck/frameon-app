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
  static const _pomodoro = PomodoroWidget();
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

  SpotifyTrack?       currentTrack;
  PomodoroTimerState? currentPomodoroState;

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
  /// loops through it independently. Dynamic layers (clock, Spotify, Pomodoro)
  /// are baked in at the moment of export — the device will show stale data
  /// until the next send.
  ///
  /// ## Why the await is here
  ///
  /// Each frame involves:
  ///   - Allocating a [PixelBuffer] per visible layer
  ///   - Alpha-blending 2048 pixels per layer (Porter-Duff, per-pixel math)
  ///   - RGB565-encoding 2048 pixels into the wire format
  ///
  /// For 300 frames × multiple layers this is millions of integer operations.
  /// Without yielding, the entire loop runs synchronously on the UI thread,
  /// starving Flutter's frame scheduler and causing the freeze + the
  /// "Reported frame time is older than the last one; clamping" error.
  ///
  /// `await Future.delayed(Duration.zero)` after each frame costs nothing
  /// measurable (one microtask queue drain) but lets Flutter paint a UI frame
  /// between each render step — the app stays responsive throughout.
  Future<Timeline> render(
    Scene scene, {
    int frameDurationMs = 100,
    int frameCount = 33,
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
        _renderLayer(layer, lb, t);
        composite.blendOver(lb);
      }
      _enc.encodeInto(composite, _encoded);
      timeline.addFrame(
        Frame(data: Uint8List.fromList(_encoded), durationMs: frameDurationMs),
      );

      // Yield to the event loop after every frame.
      //
      // This allows Flutter's frame scheduler to run between render steps,
      // keeping the UI thread responsive and preventing the freeze +
      // "frame time older than last one" error in the debug console.
      await Future<void>.delayed(Duration.zero);
    }
    return timeline;
  }

  // ── Layer dispatch ────────────────────────────────────────────────────────

  void _renderLayer(Layer layer, PixelBuffer buf, int t) {
    switch (layer.type) {
      case LayerType.text:
        _text.render(layer as TextLayer, buf, t);
      case LayerType.clock:
        _clock.render(layer as ClockLayer, buf, t);
      case LayerType.gif:
        final g = layer as GifLayer;
        _gif.renderWithAsset(
          g, buf, t,
          g.filePath != null ? _assetCache[g.filePath] : null,
        );
      case LayerType.spotify:
        _spotify.renderWithTrack(
          layer as SpotifyLayer,
          buf,
          t,
          currentTrack ?? SpotifyTrack.empty,
        );
      case LayerType.pomodoro:
        final p = layer as PomodoroLayer;
        final s = currentPomodoroState;
        if (s != null) {
          _pomodoro.renderWithState(p, buf, t, s);
        } else {
          _pomodoro.render(p, buf, t);
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