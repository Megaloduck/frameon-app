import 'dart:typed_data';

import '../scene/layer.dart';
import '../scene/scene.dart';
import '../scene/timeline.dart';
import '../widgets/clock_widget.dart';
import '../widgets/gif_widget.dart';
import '../widgets/pomodoro_widget.dart';
import '../widgets/spotify_widget.dart';
import '../widgets/text_widget.dart';
import 'pixel_buffer.dart';
import 'rgb565_encoder.dart';

/// The [MatrixRenderer] is the central compositing engine.
///
/// It takes a [Scene], renders each visible [Layer] into a [PixelBuffer]
/// via the appropriate [MatrixWidget], composites them back-to-front using
/// Porter-Duff SRC_OVER blending, encodes each composite to RGB565, and
/// accumulates the result into a [Timeline].
///
/// ## Thread safety
/// [render] is `async` because asset loading (GIFs, album art) involves I/O.
/// All pixel operations run on the calling isolate — move to a compute isolate
/// if frame-rate suffers on large scenes.
class MatrixRenderer {
  MatrixRenderer();

  // ── Widget singletons (stateless — safe to share) ──────────────────────
  static const _textWidget     = TextWidget();
  static const _clockWidget    = ClockWidget();
  static const _gifWidget      = GifWidget();
  static const _spotifyWidget  = SpotifyWidget();
  static const _pomodoroWidget = PomodoroWidget();

  final Rgb565Encoder _encoder = const Rgb565Encoder();

  /// Reused output buffer — avoids one allocation per frame.
  late Uint8List _encoded;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Render [scene] into a [Timeline].
  ///
  /// [frameDurationMs] — display time per frame (default 100 ms = 10 fps).
  /// [frameCount]      — number of frames to produce (default 33 ≈ 3.3 s).
  Future<Timeline> render(
    Scene scene, {
    int frameDurationMs = 100,
    int frameCount = 33,
  }) async {
    final int w = scene.matrixWidth;
    final int h = scene.matrixHeight;
    _encoded = Uint8List(w * h * 2);

    final timeline = Timeline();
    final assets = await _preloadAssets(scene);

    for (int frameIdx = 0; frameIdx < frameCount; frameIdx++) {
      final int elapsedMs = frameIdx * frameDurationMs;

      final composite = PixelBuffer(width: w, height: h); // starts transparent

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
        final gifLayer = layer as GifLayer;
        final asset = gifLayer.filePath != null
            ? assets.gifs[gifLayer.filePath]
            : null;
        _gifWidget.renderWithAsset(gifLayer, buffer, elapsedMs, asset);

      case LayerType.spotify:
        // Live track is injected by the Spotify service provider at runtime.
        // During offline render (export), we use a placeholder track.
        _spotifyWidget.renderWithTrack(
          layer as SpotifyLayer,
          buffer,
          elapsedMs,
          assets.spotifyTrack ?? SpotifyTrack.empty,
        );

      case LayerType.pomodoro:
        // Timer state is injected by the Pomodoro service at runtime.
        // During export, we render the static configured duration.
        if (assets.pomodoroState != null) {
          _pomodoroWidget.renderWithState(
            layer as PomodoroLayer,
            buffer,
            elapsedMs,
            assets.pomodoroState!,
          );
        } else {
          _pomodoroWidget.render(layer as PomodoroLayer, buffer, elapsedMs);
        }
    }
  }

  // ── Asset pre-loading ─────────────────────────────────────────────────────

  Future<_AssetCache> _preloadAssets(Scene scene) async {
    final cache = _AssetCache();

    for (final layer in scene.layers) {
      if (layer is GifLayer && layer.filePath != null) {
        final path = layer.filePath!;
        if (!cache.gifs.containsKey(path)) {
          // TODO: decode using the `image` package:
          //   final img = decodeGif(await File(path).readAsBytes());
          //   cache.gifs[path] = GifAsset(frames: img.frames.map(...).toList());
          cache.gifs[path] = null; // placeholder until decoder is wired
        }
      }
    }

    return cache;
  }
}

// ── Internal asset cache ──────────────────────────────────────────────────────

class _AssetCache {
  /// Decoded GIF frames keyed by file path. Null value = decode pending.
  final Map<String, GifAsset?> gifs = {};

  /// Current Spotify track — injected from SpotifyService at render time.
  SpotifyTrack? spotifyTrack;

  /// Current Pomodoro state — injected from PomodoroService at render time.
  PomodoroTimerState? pomodoroState;
}