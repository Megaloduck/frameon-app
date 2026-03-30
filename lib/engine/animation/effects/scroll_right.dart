import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Scrolls pixels toward the right and wraps content around at the edge.
class ScrollRightEffect extends AnimationEffectProcessor {
  final double pixelsPerSecond;

  const ScrollRightEffect({this.pixelsPerSecond = 20});

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int offset = ((elapsedMs * pixelsPerSecond) / 1000).floor();
    final int width = src.width;

    if (width <= 0) {
      dst.clear();
      return;
    }

    final int normalized = offset % width;

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcX = (x - normalized) % width;
        final int wrapped = srcX < 0 ? srcX + width : srcX;
        dst.setPixel(x, y, src.getPixel(wrapped, y));
      }
    }
  }
}