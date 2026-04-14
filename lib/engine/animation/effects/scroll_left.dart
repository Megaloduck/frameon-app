import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Scrolls pixels toward the left infinitely with seamless wrapping.
class ScrollLeftEffect extends AnimationEffectProcessor {
  final double pixelsPerSecond;

  const ScrollLeftEffect({this.pixelsPerSecond = 20});

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int width = src.width;
    
    if (width <= 0) {
      dst.clear();
      return;
    }

    final int offset = ((elapsedMs * pixelsPerSecond) / 1000).floor();
    final int scrollPosition = offset % width;

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < width; x++) {
        // Add width to ensure we never get negative numbers (balanced with right scroll)
        final int srcX = (x + scrollPosition + width) % width;
        dst.setPixel(x, y, src.getPixel(srcX, y));
      }
    }
  }
}