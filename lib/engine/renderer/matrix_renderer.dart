import 'dart:typed_data';

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

/// Central compositing engine.  No dart:io — runs on all platforms.
///
/// GIF bytes must be pre-registered via [addAssetBytes] before rendering.
/// The renderer decodes once and caches the result; subsequent calls with the
/// same key are no-ops unless [force] is true.
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

  /// Register bytes for [key].
  ///
  /// If the key already has a non-null decoded asset the call is a no-op
  /// (avoids re-decoding on every timeline rebuild).  Pass [force] = true
  /// to force re-decode (e.g. after the user replaces the file).
  void addAssetBytes(String key, Uint8List bytes, {bool force = false}) {
    if (!force && _assetCache[key] != null) return; // already decoded
    _assetCache[key] = _decoder.decodeBytes(bytes);
  }

  /// Register a pre-decoded asset directly.
  void addAsset(String key, GifAsset? asset) {
    _assetCache[key] = asset;
  }

  /// Remove a cached asset.
  void removeAsset(String key) => _assetCache.remove(key);

  // ── Live service state ────────────────────────────────────────────────────

  SpotifyTrack?       currentTrack;
  PomodoroTimerState? currentPomodoroState;

  // ── Render ────────────────────────────────────────────────────────────────

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
          Frame(data: Uint8List.fromList(_encoded), durationMs: frameDurationMs));
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
            g, buf, t, g.filePath != null ? _assetCache[g.filePath] : null);
      case LayerType.spotify:
        _spotify.renderWithTrack(
            layer as SpotifyLayer, buf, t, currentTrack ?? SpotifyTrack.empty);
      case LayerType.pomodoro:
        final p = layer as PomodoroLayer;
        final s = currentPomodoroState;
        if (s != null) _pomodoro.renderWithState(p, buf, t, s);
        else _pomodoro.render(p, buf, t);
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