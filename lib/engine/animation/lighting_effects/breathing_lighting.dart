// lib/engine/animation/lighting/breathing_effect.dart
//
// Breathing — smooth sine-wave opacity modulation, like a sleeping LED.
// The entire buffer fades between [minOpacity] and [maxOpacity] over [periodMs].
// This maps to the "Breathing" option in the Lighting Effect dropdown.

import 'dart:math' as math;

import '../../renderer/pixel_buffer.dart';
import 'base_lighting.dart';

class BreathingEffect extends LightingEffectProcessor {
  /// Full inhale → exhale cycle in milliseconds. Default: 2000 ms (0.5 Hz).
  final int periodMs;

  /// Opacity floor at the trough (fully exhaled). Default: 0.08.
  final double minOpacity;

  /// Opacity ceiling at the peak (fully inhaled). Default: 1.0.
  final double maxOpacity;

  const BreathingEffect({
    this.periodMs   = 2000,
    this.minOpacity = 0.08,
    this.maxOpacity = 1.0,
  });

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    // Sine oscillates −1 → +1; map to 0 → 1 → 0 (one breath per period)
    final double phase   = (elapsedMs % periodMs) / periodMs; // 0.0–1.0
    final double sine    = (math.sin(phase * 2 * math.pi) + 1) / 2; // 0.0–1.0
    final double opacity = (minOpacity + sine * (maxOpacity - minOpacity))
        .clamp(0.0, 1.0);
    final int alpha = (opacity * 255).round();

    for (int i = 0; i < src.pixels.length; i++) {
      final int px   = src.pixels[i];
      final int srcA = (px >> 24) & 0xFF;
      if (srcA == 0) { dst.pixels[i] = 0; continue; }
      final int outA = ((srcA * alpha) >> 8).clamp(0, 255);
      dst.pixels[i] = (outA << 24) | (px & 0x00FFFFFF);
    }
  }
}