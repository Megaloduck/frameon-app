import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../scene/layer.dart';
import '../scene/scene.dart';
import '../scene/timeline.dart';
import 'pixel_buffer.dart';
import 'rgb565_encoder.dart';

/// The [MatrixRenderer] is the core compositing engine.
///
/// It takes a [Scene], renders each layer into a [PixelBuffer] using
/// the appropriate widget renderer, composites them together (back-to-front),
/// applies animation effects over time, then encodes each frame to RGB565
/// and stores it in a [Timeline].
///
/// ## Usage
///
/// ```dart
/// final renderer = MatrixRenderer();
/// final timeline = await renderer.render(scene);
/// ```
///
/// The [render] method is async because image/GIF decoding involves I/O.
class MatrixRenderer {
  final Rgb565Encoder _encoder = const Rgb565Encoder();

  /// Pre-allocated output byte buffer — reused every frame to reduce GC load.
  late Uint8List _encodedFrame;

  /// Render [scene] into a new [Timeline].
  ///
  /// [frameDurationMs] — how long each frame is displayed (default 100 ms = 10 fps).
  /// [frameCount]      — how many frames to render (for animated output).
  Future<Timeline> render(
    Scene scene, {
    int frameDurationMs = 100,
    int frameCount = 33,
  }) async {
    final timeline = Timeline();
    final int w = scene.matrixWidth;
    final int h = scene.matrixHeight;
    _encodedFrame = Uint8List(w * h * 2);

    // Pre-load any image/GIF data needed by layers
    final assets = await _preloadAssets(scene);

    for (int frameIdx = 0; frameIdx < frameCount; frameIdx++) {
      final int elapsedMs = frameIdx * frameDurationMs;

      // Composite buffer — start with black background
      final composite = PixelBuffer(width: w, height: h);

      // Render each visible layer back-to-front
      for (final layer in scene.visibleLayers) {
        final layerBuffer = PixelBuffer(width: w, height: h);
        await _renderLayer(
          layer: layer,
          buffer: layerBuffer,
          elapsedMs: elapsedMs,
          assets: assets,
        );
        composite.blendOver(layerBuffer);
      }

      // Encode to RGB565
      _encoder.encodeInto(composite, _encodedFrame);
      timeline.addFrame(
        Frame(
          data: Uint8List.fromList(_encodedFrame),
          durationMs: frameDurationMs,
        ),
      );
    }

    return timeline;
  }

  // ── Layer Dispatch ────────────────────────────────────────────────────────

  Future<void> _renderLayer({
    required Layer layer,
    required PixelBuffer buffer,
    required int elapsedMs,
    required Map<String, dynamic> assets,
  }) async {
    switch (layer.type) {
      case LayerType.text:
        _renderTextLayer(layer as TextLayer, buffer, elapsedMs);
      case LayerType.clock:
        _renderClockLayer(layer as ClockLayer, buffer, elapsedMs);
      case LayerType.gif:
        await _renderGifLayer(layer as GifLayer, buffer, elapsedMs, assets);
      case LayerType.spotify:
        _renderSpotifyLayer(layer as SpotifyLayer, buffer, elapsedMs, assets);
      case LayerType.pomodoro:
        _renderPomodoroLayer(layer as PomodoroLayer, buffer, elapsedMs);
    }
  }

  // ── Text Renderer ─────────────────────────────────────────────────────────

  void _renderTextLayer(
    TextLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
  ) {
    // Animation: blink — hide on odd 500 ms windows
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    // Text scroll offset for scrollLeft / scrollRight
    int scrollOffsetX = 0;
    if (layer.effect == AnimationEffect.scrollLeft) {
      // Scroll one pixel every 50 ms
      scrollOffsetX = -(elapsedMs ~/ 50) % (buffer.width + 60);
    } else if (layer.effect == AnimationEffect.scrollRight) {
      scrollOffsetX = (elapsedMs ~/ 50) % (buffer.width + 60);
    }

    // Pixel-font rendering — delegates to the PixelFont utility (stub).
    // In the full implementation this calls PixelFont.render(text, ...) which
    // returns a tiny PixelBuffer for the glyphs, then blits it onto [buffer].
    _drawTextStub(
      buffer: buffer,
      text: layer.text,
      color: layer.color,
      xOffset: scrollOffsetX + layer.offset.dx.round(),
      yOffset: layer.offset.dy.round(),
    );
  }

  // ── Clock Renderer ────────────────────────────────────────────────────────

  void _renderClockLayer(
    ClockLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
  ) {
    final now = DateTime.now();
    final bool colonVisible =
        !layer.blinkColon || (now.millisecond < 500);

    final String time = layer.format == ClockFormat.h24
        ? '${_pad(now.hour)}${colonVisible ? ':' : ' '}${_pad(now.minute)}'
        : '${_pad(now.hour > 12 ? now.hour - 12 : now.hour)}${colonVisible ? ':' : ' '}${_pad(now.minute)}';

    _drawTextStub(
      buffer: buffer,
      text: time,
      color: layer.color,
      xOffset: layer.offset.dx.round(),
      yOffset: layer.offset.dy.round(),
    );
  }

  // ── GIF Renderer ──────────────────────────────────────────────────────────

  Future<void> _renderGifLayer(
    GifLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    Map<String, dynamic> assets,
  ) async {
    // In the full implementation: load decoded frames from [assets],
    // select the correct frame by [elapsedMs], apply layout scaling,
    // dithering, grayscale/invert transforms, then blit to [buffer].
    // Stub: fill a region with a placeholder color.
    buffer.fillRect(0, 0, buffer.width, buffer.height,
        const ui.Color(0xFF1A1A2E));
  }

  // ── Spotify Renderer ──────────────────────────────────────────────────────

  void _renderSpotifyLayer(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    Map<String, dynamic> assets,
  ) {
    // Stub: render album art region + scrolling track/artist text.
    // Full implementation reads current track from SpotifyService notifier.
    buffer.fillRect(0, 0, buffer.width ~/ 2, buffer.height,
        const ui.Color(0xFF121212));
  }

  // ── Pomodoro Renderer ─────────────────────────────────────────────────────

  void _renderPomodoroLayer(
    PomodoroLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
  ) {
    // Stub: derive remaining time from PomodoroService state and render digits.
    const int remaining = 15 * 60; // placeholder: 15:00
    final int minutes = remaining ~/ 60;
    final int seconds = remaining % 60;
    final String display = '${_pad(minutes)}:${_pad(seconds)}';
    _drawTextStub(
      buffer: buffer,
      text: display,
      color: layer.focusColor,
      xOffset: layer.offset.dx.round(),
      yOffset: layer.offset.dy.round(),
    );
  }

  // ── Asset Pre-loading ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _preloadAssets(Scene scene) async {
    final Map<String, dynamic> assets = {};
    for (final layer in scene.layers) {
      if (layer is GifLayer && layer.filePath != null) {
        // TODO: decode GIF frames using the `image` package and cache here.
        assets[layer.filePath!] = null;
      }
    }
    return assets;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Minimal text stub — draws a coloured rectangle proportional to text length.
  /// Replace with real PixelFont.render() calls in the full implementation.
  void _drawTextStub({
    required PixelBuffer buffer,
    required String text,
    required ui.Color color,
    int xOffset = 0,
    int yOffset = 0,
  }) {
    // Each character is approximated as a 5×7 glyph with 1px spacing.
    const int charW = 5;
    const int charH = 7;
    const int charSpacing = 1;
    final int totalW = text.length * (charW + charSpacing) - charSpacing;
    final int startX =
        ((buffer.width - totalW) ~/ 2) + xOffset;
    final int startY = ((buffer.height - charH) ~/ 2) + yOffset;

    for (int i = 0; i < text.length; i++) {
      final int cx = startX + i * (charW + charSpacing);
      buffer.fillRect(cx, startY, charW, charH, color);
    }
  }
}