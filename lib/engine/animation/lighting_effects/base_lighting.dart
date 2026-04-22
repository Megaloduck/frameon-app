// lib/engine/animation/lighting/base_lighting_effect.dart
//
// Contract for LED lighting effects — ambient colour modulation applied
// to an entire pixel buffer (background wash, per-pixel brightness, etc.).
// Unlike font AnimationEffects which operate on text glyphs, lighting effects
// can transform any rendered layer buffer post-composite.

import '../../renderer/pixel_buffer.dart';

abstract class LightingEffectProcessor {
  const LightingEffectProcessor();

  /// Apply the lighting effect from [src] into [dst] at [elapsedMs].
  /// [src] is treated as immutable; [dst] receives the full transformed frame.
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs);
}