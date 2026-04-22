import 'dart:math' as math;

import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Sine-wave opacity pulse.
///
/// The layer fades between [minOpacity] and full opacity over [periodMs].
/// One full cycle = fade out → fade in → repeat.
class PulseEffect extends AnimationEffectProcessor {
  /// Full pulse cycle in milliseconds. Default: 2000 ms (0.5 Hz).
  final int periodMs;

  /// Minimum opacity at the trough of the pulse (0.0–1.0).
  final double minOpacity;

  const PulseEffect({
    this.periodMs = 2000,
    this.minOpacity = 0.08,
  });

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final double phase = (elapsedMs % periodMs) / periodMs; // 0.0 → 1.0
    // sin goes −1 → +1; shift to 0 → 1, then scale to minOpacity → 1.0
    final double t = (math.sin(phase * 2 * math.pi) + 1) / 2; // 0.0 → 1.0
    final double opacity = minOpacity + t * (1.0 - minOpacity);

    final int alpha = (opacity * 255).round().clamp(0, 255);

    for (int i = 0; i < src.pixels.length; i++) {
      final int px = src.pixels[i];
      final int srcA = (px >> 24) & 0xFF;
      if (srcA == 0) {
        dst.pixels[i] = 0;
        continue;
      }
      // Blend the source alpha with our pulse opacity
      final int outA = ((srcA * alpha) >> 8).clamp(0, 255);
      dst.pixels[i] = (outA << 24) | (px & 0x00FFFFFF);
    }
  }
}