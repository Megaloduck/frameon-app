import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Marquee scroll with wrap-around — content scrolls left and re-enters from the right.
/// This creates an endless looping effect like a classic LED marquee.
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

    // Calculate how many pixels to shift left, then wrap to buffer width
    final int shift = ((elapsedMs * pixelsPerSecond) / 1000).floor();
    final int effectiveShift = shift % w;

    dst.clear();

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Source pixel comes from ahead (shifted left) with wrap-around:
        // (x + effectiveShift) % w ensures seamless looping
        final int srcX = (x + effectiveShift) % w;
        dst.setPixel(x, y, src.getPixel(srcX, y));
      }
    }
  }
}