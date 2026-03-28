import 'dart:typed_data';
import 'dart:ui' as ui;

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// A single decoded GIF/image frame ready for compositing.
class DecodedFrame {
  /// ARGB32 pixel data, row-major, [width × height] entries.
  final Uint32List pixels;
  final int width;
  final int height;
  /// How long this frame should be displayed (milliseconds).
  final int durationMs;

  const DecodedFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.durationMs,
  });
}

/// Cache entry stored per [GifLayer.filePath].
class GifAsset {
  final List<DecodedFrame> frames;
  const GifAsset({required this.frames});

  bool get isEmpty => frames.isEmpty;

  /// Return the frame that should be displayed at [elapsedMs].
  DecodedFrame frameAt(int elapsedMs) {
    if (frames.length == 1) return frames.first;
    int t = elapsedMs;
    for (final frame in frames) {
      t -= frame.durationMs;
      if (t <= 0) return frame;
    }
    return frames.last;
  }
}

/// Renders a [GifLayer] into a [PixelBuffer].
///
/// Accepts a pre-decoded [GifAsset] from the renderer's asset cache.
/// When [asset] is null (not yet loaded), the buffer is left transparent.
///
/// Supported transforms (applied in order):
/// 1. Layout scaling (letterbox / fill / stretch)
/// 2. Grayscale conversion
/// 3. Color invert
/// 4. Ordered dithering (2×2 Bayer matrix) — reduces 8-bit color to the
///    effective precision of RGB565 while preserving perceived gradients.
class GifWidget extends MatrixWidget<GifLayer> {
  const GifWidget();

  /// Render [layer] using [asset] decoded frames.
  /// Call this overload from [MatrixRenderer] after asset pre-loading.
  void renderWithAsset(
    GifLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    GifAsset? asset,
  ) {
    if (asset == null || asset.isEmpty) return;
    final DecodedFrame frame = asset.frameAt(elapsedMs);
    _blit(frame, layer, buffer);
  }

  @override
  void render(GifLayer layer, PixelBuffer buffer, int elapsedMs) {
    // Called when no asset cache is available (e.g. during unit tests).
    // In production, MatrixRenderer calls renderWithAsset() directly.
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _blit(DecodedFrame src, GifLayer layer, PixelBuffer dst) {
    final (int dstX, int dstY, int drawW, int drawH) =
        _layoutRect(src.width, src.height, dst.width, dst.height, layer.layout);

    final double scaleX = src.width / drawW;
    final double scaleY = src.height / drawH;

    // 2×2 Bayer dither matrix (normalised to ±0.5 range for RGB565 precision).
    const List<List<int>> bayer = [
      [0, 2],
      [3, 1],
    ];

    for (int dy = 0; dy < drawH; dy++) {
      for (int dx = 0; dx < drawW; dx++) {
        final int sx = (dx * scaleX).toInt().clamp(0, src.width - 1);
        final int sy = (dy * scaleY).toInt().clamp(0, src.height - 1);

        int argb = src.pixels[sy * src.width + sx];
        int a = (argb >> 24) & 0xFF;
        int r = (argb >> 16) & 0xFF;
        int g = (argb >> 8) & 0xFF;
        int b = argb & 0xFF;

        // Grayscale
        if (layer.grayscale) {
          final int lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
          r = g = b = lum;
        }

        // Invert
        if (layer.invertColor) {
          r = 255 - r;
          g = 255 - g;
          b = 255 - b;
        }

        // Ordered dither (adds subtle noise to prevent RGB565 banding)
        if (layer.dithering) {
          final int d = bayer[dy % 2][dx % 2] * 8 - 16;
          r = (r + d).clamp(0, 255);
          g = (g + d).clamp(0, 255);
          b = (b + d).clamp(0, 255);
        }

        final int px = dstX + dx;
        final int py = dstY + dy;
        dst.setPixel(px, py, (a << 24) | (r << 16) | (g << 8) | b);
      }
    }
  }

  /// Compute destination rect for the given [layout].
  (int x, int y, int w, int h) _layoutRect(
    int srcW,
    int srcH,
    int dstW,
    int dstH,
    MediaLayout layout,
  ) {
    switch (layout) {
      case MediaLayout.stretch:
        return (0, 0, dstW, dstH);

      case MediaLayout.fill:
        // Scale to fill, centred (may crop).
        final double scale =
            (dstW / srcW).clamp(dstH / srcH, double.infinity);
        final int w = (srcW * scale).round();
        final int h = (srcH * scale).round();
        return ((dstW - w) ~/ 2, (dstH - h) ~/ 2, w, h);

      case MediaLayout.letterbox:
        // Scale to fit, centred (may pillarbox/letterbox).
        final double scale =
            (dstW / srcW).clamp(0, dstH / srcH);
        final int w = (srcW * scale).round();
        final int h = (srcH * scale).round();
        return ((dstW - w) ~/ 2, (dstH - h) ~/ 2, w, h);
    }
  }
}