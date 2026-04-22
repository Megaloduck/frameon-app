import 'dart:math' as math;

import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Burst — a quick bright flash followed by a slow exponential decay to dim.
///
/// Pattern per cycle ([periodMs]):
///   • 0 ms         — instant full brightness (the "burst")
///   • 0 → flashMs  — decay from 1.0 → [dimOpacity] exponentially
///   • flashMs → periodMs — hold at [dimOpacity] until next burst
///
/// This gives the feel of a strobe/camera-flash pulse.
///
/// [dimOpacity] must be > 0.0 — a value of 0.0 would cause log(0) which is
/// undefined. Use a small positive value such as 0.01 for near-black.
class BurstEffect extends AnimationEffectProcessor {
  /// Full cycle length in ms. Default: 1500 ms.
  final int periodMs;

  /// Duration of the decay phase in ms. Default: 400 ms.
  final int flashMs;

  /// Opacity floor — how dim the layer rests between bursts.
  /// Must be > 0.0. Default: 0.12.
  final double dimOpacity;

  const BurstEffect({
    this.periodMs = 1500,
    this.flashMs = 400,
    this.dimOpacity = 0.12,
  }) : assert(dimOpacity > 0.0,
            'dimOpacity must be > 0.0 — a value of 0 causes log(0) which is undefined.');

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int t = elapsedMs % periodMs;

    double opacity;
    if (t <= flashMs) {
      // Exponential decay from 1.0 down to dimOpacity over flashMs
      final double progress = t / flashMs; // 0 → 1
      // e^(−k·progress) shaped to hit dimOpacity at progress=1
      final double k = -math.log(dimOpacity); // k > 0 (safe: dimOpacity > 0)
      opacity = math.exp(-k * progress);
    } else {
      opacity = dimOpacity;
    }

    opacity = opacity.clamp(0.0, 1.0);
    final int alpha = (opacity * 255).round();

    for (int i = 0; i < src.pixels.length; i++) {
      final int px = src.pixels[i];
      final int srcA = (px >> 24) & 0xFF;
      if (srcA == 0) {
        dst.pixels[i] = 0;
        continue;
      }
      final int outA = ((srcA * alpha) >> 8).clamp(0, 255);
      dst.pixels[i] = (outA << 24) | (px & 0x00FFFFFF);
    }
  }
}