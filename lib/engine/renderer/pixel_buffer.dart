import 'dart:typed_data';
import 'dart:ui';

/// A 64×32 RGBA pixel buffer used as the intermediate compositing surface.
/// Each pixel is stored as a 32-bit integer: 0xAARRGGBB.
class PixelBuffer {
  final int width;
  final int height;
  late Uint32List _pixels;

  PixelBuffer({this.width = 64, this.height = 32}) {
    _pixels = Uint32List(width * height);
  }

  /// Creates a copy of another buffer (used for double-buffering).
  PixelBuffer.from(PixelBuffer other)
      : width = other.width,
        height = other.height {
    _pixels = Uint32List.fromList(other._pixels);
  }

  /// Raw pixel data as ARGB32.
  Uint32List get pixels => _pixels;

  /// Get a single pixel at (x, y). Returns 0x00000000 if out of bounds.
  int getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 0;
    return _pixels[y * width + x];
  }

  /// Set a single pixel at (x, y). No-op if out of bounds.
  void setPixel(int x, int y, int argb) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    _pixels[y * width + x] = argb;
  }

  /// Set a pixel using a Flutter [Color].
  void setPixelColor(int x, int y, Color color) {
    setPixel(x, y, color.value);
  }

  /// Composite [src] over this buffer using standard alpha blending (Porter-Duff SRC_OVER).
  void blendOver(PixelBuffer src) {
    assert(src.width == width && src.height == height,
        'Buffer dimensions must match for blending.');
    for (int i = 0; i < _pixels.length; i++) {
      final int s = src._pixels[i];
      final int sa = (s >> 24) & 0xFF;
      if (sa == 0) continue; // fully transparent — skip
      if (sa == 255) {
        _pixels[i] = s; // fully opaque — fast path
        continue;
      }
      final int d = _pixels[i];
      final int da = (d >> 24) & 0xFF;
      final int invSa = 255 - sa;

      final int outA = sa + ((da * invSa) >> 8);
      final int outR =
          ((((s >> 16) & 0xFF) * sa + (((d >> 16) & 0xFF) * invSa)) >> 8);
      final int outG =
          ((((s >> 8) & 0xFF) * sa + (((d >> 8) & 0xFF) * invSa)) >> 8);
      final int outB =
          (((s & 0xFF) * sa + ((d & 0xFF) * invSa)) >> 8);

      _pixels[i] = (outA.clamp(0, 255) << 24) |
          (outR.clamp(0, 255) << 16) |
          (outG.clamp(0, 255) << 8) |
          outB.clamp(0, 255);
    }
  }

  /// Fill entire buffer with a single [color].
  void fill(Color color) => _pixels.fillRange(0, _pixels.length, color.value);

  /// Clear the buffer to transparent black.
  void clear() => _pixels.fillRange(0, _pixels.length, 0x00000000);

  /// Copy [src] buffer contents into this buffer (no blending).
  void copyFrom(PixelBuffer src) {
    assert(src.width == width && src.height == height);
    _pixels.setAll(0, src._pixels);
  }

  /// Draw a filled rectangle.
  void fillRect(int x, int y, int w, int h, Color color) {
    final int argb = color.value;
    for (int row = y; row < y + h; row++) {
      for (int col = x; col < x + w; col++) {
        setPixel(col, row, argb);
      }
    }
  }

  /// Blit a sub-region from [src] into this buffer at offset (dx, dy).
  void blit(PixelBuffer src, {int dx = 0, int dy = 0}) {
    for (int row = 0; row < src.height; row++) {
      final int dstRow = dy + row;
      if (dstRow < 0 || dstRow >= height) continue;
      for (int col = 0; col < src.width; col++) {
        final int dstCol = dx + col;
        if (dstCol < 0 || dstCol >= width) continue;
        final int s = src._pixels[row * src.width + col];
        final int sa = (s >> 24) & 0xFF;
        if (sa == 0) continue;
        if (sa == 255) {
          _pixels[dstRow * width + dstCol] = s;
        } else {
          setPixel(dstCol, dstRow, s);
        }
      }
    }
  }

  /// Convert pixel at index [i] to a Flutter [Color].
  Color colorAt(int i) => Color(_pixels[i]);

  @override
  String toString() => 'PixelBuffer(${width}x$height)';
}