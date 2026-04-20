// lib/engine/animation/lightings/lighting_animator.dart
//
// Resolves an [AnimationEffect] (reused enum) to its [LightingEffectProcessor]
// and applies it to a rendered PixelBuffer.
//
// Usage in a layer renderer:
//
//   final lighting = LightingAnimator();
//   final processor = lighting.effectFor(layer.lightingEffect);
//   if (processor != null) {
//     final src = PixelBuffer.from(layerBuffer);
//     processor.apply(src, layerBuffer, elapsedMs);
//   }

import '../../../engine/scene/layer.dart';
import '../../renderer/pixel_buffer.dart';
import 'base_lighting.dart';
import 'breathing_lighting.dart';


class LightingAnimator {
  const LightingAnimator();

  /// Return the [LightingEffectProcessor] for [effect], or null for none/static.
  LightingEffectProcessor? effectFor(AnimationEffect effect) {
    switch (effect) {
      case AnimationEffect.none:
        return null;
      case AnimationEffect.pulse:
        // "Breathing" in the UI dropdown maps to AnimationEffect.pulse
        return const BreathingEffect(periodMs: 2000, minOpacity: 0.08);
 
      default:
        // scrollLeft / scrollRight / burst → no lighting equivalent
        return null;
    }
  }

  /// Apply lighting effect in-place on [buffer] at [elapsedMs].
  void apply(AnimationEffect effect, PixelBuffer buffer, int elapsedMs) {
    final processor = effectFor(effect);
    if (processor == null) return;
    final src = PixelBuffer.from(buffer);
    processor.apply(src, buffer, elapsedMs);
  }
}