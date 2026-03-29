import 'dart:typed_data';
import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// A single decoded GIF/image frame ready for compositing.
class DecodedFrame {
  final Uint32List pixels;
  final int width;
  final int height;
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
/// Supported transforms applied in order:
/// 1. Layout scaling (letterbox / fill / stretch)
/// 2. Grayscale conversion
/// 3. Color invert
/// 4. Ordered dithering (2×2 Bayer) — reduces banding at RGB565 precision
class GifWidget extends MatrixWidget<GifLayer> {
  const GifWidget();

  void renderWithAsset(
    GifLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    GifAsset? asset,
  ) {
    if (asset == null || asset.isEmpty) return;
    _blit(asset.frameAt(elapsedMs), layer, buffer);
  }

  @override
  void render(GifLayer layer, PixelBuffer buffer, int elapsedMs) {
    // No-op without a decoded asset — MatrixRenderer calls renderWithAsset().
  }

  void _blit(DecodedFrame src, GifLayer layer, PixelBuffer dst) {
    final (int dstX, int dstY, int drawW, int drawH) =
        _layoutRect(src.width, src.height, dst.width, dst.height, layer.layout);
    if (drawW <= 0 || drawH <= 0) return;

    final double scaleX = src.width / drawW;
    final double scaleY = src.height / drawH;
    const List<List<int>> bayer = [[0, 2], [3, 1]];

    for (int dy = 0; dy < drawH; dy++) {
      for (int dx = 0; dx < drawW; dx++) {
        final int sx = (dx * scaleX).toInt().clamp(0, src.width - 1);
        final int sy = (dy * scaleY).toInt().clamp(0, src.height - 1);
        int argb = src.pixels[sy * src.width + sx];
        int a = (argb >> 24) & 0xFF;
        int r = (argb >> 16) & 0xFF;
        int g = (argb >> 8) & 0xFF;
        int b = argb & 0xFF;

        if (layer.grayscale) {
          final int lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
          r = g = b = lum;
        }
        if (layer.invertColor) { r = 255 - r; g = 255 - g; b = 255 - b; }
        if (layer.dithering) {
          final int d = bayer[dy % 2][dx % 2] * 8 - 16;
          r = (r + d).clamp(0, 255);
          g = (g + d).clamp(0, 255);
          b = (b + d).clamp(0, 255);
        }
        dst.setPixel(dstX + dx, dstY + dy, (a << 24) | (r << 16) | (g << 8) | b);
      }
    }
  }

  /// Fixed: letterbox now uses min(wRatio, hRatio) — correct "scale to fit".
  /// Previous version used clamp(0, hRatio) which overflowed for landscape images.
  (int x, int y, int w, int h) _layoutRect(
      int srcW, int srcH, int dstW, int dstH, MediaLayout layout) {
    switch (layout) {
      case MediaLayout.stretch:
        return (0, 0, dstW, dstH);
      case MediaLayout.fill:
        final double s = (dstW / srcW) > (dstH / srcH) ? dstW / srcW : dstH / srcH;
        final int w = (srcW * s).round(), h = (srcH * s).round();
        return ((dstW - w) ~/ 2, (dstH - h) ~/ 2, w, h);
      case MediaLayout.letterbox:
        final double s = (dstW / srcW) < (dstH / srcH) ? dstW / srcW : dstH / srcH;
        final int w = (srcW * s).round(), h = (srcH * s).round();
        return ((dstW - w) ~/ 2, (dstH - h) ~/ 2, w, h);
    }
  }
}