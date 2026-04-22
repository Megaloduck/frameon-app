import '../../renderer/pixel_buffer.dart';
import 'base_fonteffect.dart';

/// LED matrix-style left-scrolling effect.
/// Content scrolls continuously from right edge to left edge
/// with seamless wrap-around (classic LED marquee).
class ScrollLeftEffect extends AnimationEffectProcessor {
  final double pixelsPerSecond;

  const ScrollLeftEffect({this.pixelsPerSecond = 30});

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int w = src.width;
    final int h = src.height;

    if (w <= 0) {
      dst.clear();
      return;
    }

    // Calculate total pixels shifted left since start
    final double scrollDistance = (elapsedMs * pixelsPerSecond) / 1000;
    final int shift = scrollDistance.floor();
    final int effectiveShift = shift % w;

    dst.clear();

    // Shift left with wrap-around: source pixel comes from the right
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // (x + effectiveShift) % w creates seamless wrap-around
        final int srcX = (x + effectiveShift) % w;
        dst.setPixel(x, y, src.getPixel(srcX, y));
      }
    }
  }
}