import 'dart:io';
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

/// Central compositing engine.
///
/// Renders each visible [Layer] via its [MatrixWidget], composites back-to-front
/// using Porter-Duff SRC_OVER, encodes to RGB565, and builds a [Timeline].
///
/// GIF/image assets are decoded once per render call and cached in [_AssetCache].
/// Spotify and Pomodoro live state is injected externally before calling [render].
class MatrixRenderer {
  MatrixRenderer();

  static const _textWidget     = TextWidget();
  static const _clockWidget    = ClockWidget();
  static const _gifWidget      = GifWidget();
  static const _spotifyWidget  = SpotifyWidget();
  static const _pomodoroWidget = PomodoroWidget();
  static const _gifDecoder     = GifDecoder();

  final Rgb565Encoder _encoder = const Rgb565Encoder();
  late Uint8List _encoded;

  /// Optional live state injected by service providers before export.
  SpotifyTrack? currentTrack;
  PomodoroTimerState? currentPomodoroState;

  // ── Public API ────────────────────────────────────────────────────────────

  Future<Timeline> render(
    Scene scene, {
    int frameDurationMs = 100,
    int frameCount = 33,
  }) async {
    final int w = scene.matrixWidth;
    final int h = scene.matrixHeight;
    _encoded = Uint8List(w * h * 2);

    final _AssetCache assets = await _preloadAssets(scene);

    final timeline = Timeline();

    for (int i = 0; i < frameCount; i++) {
      final int elapsedMs = i * frameDurationMs;
      final composite = PixelBuffer(width: w, height: h);

      for (final layer in scene.visibleLayers) {
        final layerBuffer = PixelBuffer(width: w, height: h);
        _renderLayer(layer, layerBuffer, elapsedMs, assets);
        composite.blendOver(layerBuffer);
      }

      _encoder.encodeInto(composite, _encoded);
      timeline.addFrame(Frame(
        data: Uint8List.fromList(_encoded),
        durationMs: frameDurationMs,
      ));
    }

    return timeline;
  }

  // ── Layer dispatch ────────────────────────────────────────────────────────

  void _renderLayer(
    Layer layer,
    PixelBuffer buffer,
    int elapsedMs,
    _AssetCache assets,
  ) {
    switch (layer.type) {
      case LayerType.text:
        _textWidget.render(layer as TextLayer, buffer, elapsedMs);

      case LayerType.clock:
        _clockWidget.render(layer as ClockLayer, buffer, elapsedMs);

      case LayerType.gif:
        final g = layer as GifLayer;
        final asset =
            g.filePath != null ? assets.gifs[g.filePath] : null;
        _gifWidget.renderWithAsset(g, buffer, elapsedMs, asset);

      case LayerType.spotify:
        _spotifyWidget.renderWithTrack(
          layer as SpotifyLayer,
          buffer,
          elapsedMs,
          assets.spotifyTrack ?? SpotifyTrack.empty,
        );

      case LayerType.pomodoro:
        final p = layer as PomodoroLayer;
        final state = assets.pomodoroState;
        if (state != null) {
          _pomodoroWidget.renderWithState(p, buffer, elapsedMs, state);
        } else {
          _pomodoroWidget.render(p, buffer, elapsedMs);
        }
    }
  }

  // ── Asset pre-loading ─────────────────────────────────────────────────────

  Future<_AssetCache> _preloadAssets(Scene scene) async {
    final cache = _AssetCache(
      spotifyTrack:   currentTrack,
      pomodoroState:  currentPomodoroState,
    );

    for (final layer in scene.layers) {
      if (layer is GifLayer && layer.filePath != null) {
        final String path = layer.filePath!;
        if (cache.gifs.containsKey(path)) continue; // already decoded

        final GifAsset? asset =
            await _gifDecoder.decode(File(path));
        cache.gifs[path] = asset; // null = decode failed, renders transparent
      }
    }

    return cache;
  }
}

// ── Internal asset cache ──────────────────────────────────────────────────────

class _AssetCache {
  /// Decoded GIF/image frames keyed by file path.
  /// A null value means the file failed to decode — renders as transparent.
  final Map<String, GifAsset?> gifs = {};

  final SpotifyTrack? spotifyTrack;
  final PomodoroTimerState? pomodoroState;

  _AssetCache({this.spotifyTrack, this.pomodoroState});
}