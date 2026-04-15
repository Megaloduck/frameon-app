import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Marquee scroll — content enters from the right and exits to the left.
/// Unlike the old wrap-around version, this shifts the entire buffer left by
/// [offset] pixels and fills the vacated right side with transparent black.
/// The [TextWidget] already draws the text at its natural position; this
/// effect then slides that rendered content across the canvas.
class ScrollLeftEffect extends AnimationEffectProcessor {
  final double pixelsPerSecond;

  const ScrollLeftEffect({this.pixelsPerSecond = 20});

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int w = src.width;
    final int h = src.height;

    if (w <= 0) {
      dst.clear();
      return;
    }

    final int shift = ((elapsedMs * pixelsPerSecond) / 1000).floor();

    dst.clear(); // fill with transparent black first

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int srcX = x + shift;
        if (srcX < 0 || srcX >= w) continue; // out of source — leave black
        dst.setPixel(x, y, src.getPixel(srcX, y));
      }
    }
  }
}