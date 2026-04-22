import '../../renderer/pixel_buffer.dart';
import 'base_fonteffect.dart';

/// Marquee scroll with wrap-around — content scrolls right and re-enters from the left.
/// This creates an endless looping effect like a classic LED marquee.
class ScrollRightEffect extends AnimationEffectProcessor {
  final double pixelsPerSecond;

  const ScrollRightEffect({this.pixelsPerSecond = 20});

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int w = src.width;
    final int h = src.height;

    if (w <= 0) {
      dst.clear();
      return;
    }

    // Calculate how many pixels to shift right, then wrap to buffer width
    final int shift = ((elapsedMs * pixelsPerSecond) / 1000).floor();
    final int effectiveShift = shift % w;

    dst.clear();

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Source pixel comes from the left side (shifted right) with wrap-around:
        // (x - effectiveShift + w) % w ensures we never go negative
        final int srcX = (x - effectiveShift + w) % w;
        dst.setPixel(x, y, src.getPixel(srcX, y));
      }
    }
  }
}