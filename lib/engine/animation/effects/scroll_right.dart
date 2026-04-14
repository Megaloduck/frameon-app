import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Marquee scroll — content enters from the left and exits to the right.
///
/// Shifts the entire buffer right by [offset] pixels, filling the vacated
/// left side with transparent black.
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

    final int shift = ((elapsedMs * pixelsPerSecond) / 1000).floor();

    dst.clear();

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int srcX = x - shift;
        if (srcX < 0 || srcX >= w) continue;
        dst.setPixel(x, y, src.getPixel(srcX, y));
      }
    }
  }
}