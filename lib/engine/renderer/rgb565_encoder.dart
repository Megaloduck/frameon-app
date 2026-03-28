import 'dart:typed_data';
import 'pixel_buffer.dart';

/// Encodes a [PixelBuffer] into the RGB565 wire format expected by the
/// LED matrix hardware.
///
/// RGB565 packs each pixel into 2 bytes (big-endian):
///   RRRRR GGG GGG BBBBB
///   [15:11] red (5 bits), [10:5] green (6 bits), [4:0] blue (5 bits)
///
/// The device expects pixels in row-major order starting from (0, 0).
class Rgb565Encoder {
  const Rgb565Encoder();

  /// Encode the full buffer into a [Uint8List] of length width * height * 2.
  Uint8List encode(PixelBuffer buffer) {
    final int pixelCount = buffer.width * buffer.height;
    final Uint8List out = Uint8List(pixelCount * 2);
    int outIdx = 0;

    for (int i = 0; i < pixelCount; i++) {
      final int argb = buffer.pixels[i];
      final int r = (argb >> 16) & 0xFF;
      final int g = (argb >> 8) & 0xFF;
      final int b = argb & 0xFF;

      final int rgb565 = _toRgb565(r, g, b);

      // Big-endian: high byte first
      out[outIdx++] = (rgb565 >> 8) & 0xFF;
      out[outIdx++] = rgb565 & 0xFF;
    }

    return out;
  }

  /// Encode into a pre-allocated [Uint8List]. Useful for real-time rendering
  /// to avoid GC pressure — reuse the same output buffer across frames.
  void encodeInto(PixelBuffer buffer, Uint8List out) {
    assert(
      out.length >= buffer.width * buffer.height * 2,
      'Output buffer too small: need ${buffer.width * buffer.height * 2} bytes',
    );
    final int pixelCount = buffer.width * buffer.height;
    int outIdx = 0;
    for (int i = 0; i < pixelCount; i++) {
      final int argb = buffer.pixels[i];
      final int rgb565 =
          _toRgb565((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
      out[outIdx++] = (rgb565 >> 8) & 0xFF;
      out[outIdx++] = rgb565 & 0xFF;
    }
  }

  /// Decode a single RGB565 word back to 8-bit components.
  /// Useful for round-trip testing and reading device state.
  ({int r, int g, int b}) decodePixel(int rgb565) {
    // Expand 5-bit red: multiply by 255/31 ≈ shift left 3 and OR top bits
    final int r = ((rgb565 >> 11) & 0x1F) << 3;
    final int g = ((rgb565 >> 5) & 0x3F) << 2;
    final int b = (rgb565 & 0x1F) << 3;
    return (r: r, g: g, b: b);
  }

  /// Decode a full RGB565 byte stream into a new [PixelBuffer].
  PixelBuffer decode(Uint8List data, {int width = 64, int height = 32}) {
    assert(data.length == width * height * 2,
        'Data length mismatch for ${width}x$height buffer');
    final buffer = PixelBuffer(width: width, height: height);
    for (int i = 0; i < width * height; i++) {
      final int hi = data[i * 2];
      final int lo = data[i * 2 + 1];
      final int rgb565 = (hi << 8) | lo;
      final decoded = decodePixel(rgb565);
      buffer.pixels[i] =
          0xFF000000 | (decoded.r << 16) | (decoded.g << 8) | decoded.b;
    }
    return buffer;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  /// Pack 8-bit R, G, B into a 16-bit RGB565 word.
  int _toRgb565(int r, int g, int b) {
    final int r5 = (r >> 3) & 0x1F;
    final int g6 = (g >> 2) & 0x3F;
    final int b5 = (b >> 3) & 0x1F;
    return (r5 << 11) | (g6 << 5) | b5;
  }
}