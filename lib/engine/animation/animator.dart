import '../scene/layer.dart';
import '../renderer/pixel_buffer.dart';
import 'font_effects/base_effect.dart';
import 'font_effects/blink_effect.dart';
import 'font_effects/burst_effect.dart';
import 'font_effects/fade_effect.dart';
import 'font_effects/leftscroll_effect.dart';
import 'font_effects/pulse_effect.dart';
import 'font_effects/rightscroll_effect.dart';

/// Resolves the correct [AnimationEffectProcessor] for a given [Layer]
/// and applies it during rendering.
///
/// The [Animator] is stateless — it is instantiated once and reused
/// across all render calls.
class Animator {
  const Animator();

  /// Return the [AnimationEffectProcessor] for [layer], or `null` if
  /// the layer has no animation effect.
  ///
  /// Currently only [TextLayer] supports animation effects. Other layer
  /// types return null intentionally.
  /// TODO: extend this when ImageLayer or other layer types gain effect support.
  AnimationEffectProcessor? effectFor(Layer layer) {
    if (layer is TextLayer) {
      return _resolve(layer.effect);
    }
    return null;
  }

  /// Apply the effect for [layer] from [src] into [dst] at [elapsedMs].
  ///
  /// If the layer has no effect, [dst] is simply populated from [src].
  void applyEffect(
    Layer layer,
    PixelBuffer src,
    PixelBuffer dst,
    int elapsedMs,
  ) {
    final effect = effectFor(layer);
    if (effect == null) {
      dst.copyFrom(src);
    } else {
      effect.apply(src, dst, elapsedMs);
    }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  AnimationEffectProcessor? _resolve(AnimationEffect effect) {
    switch (effect) {
      case AnimationEffect.none:
        return null;
      case AnimationEffect.blink:
        return const BlinkEffect(periodMs: 1000);
      case AnimationEffect.scrollLeft:
        return const ScrollLeftEffect(pixelsPerSecond: 20);
      case AnimationEffect.scrollRight:
        return const ScrollRightEffect(pixelsPerSecond: 20);
      case AnimationEffect.pulse:
        return const PulseEffect(periodMs: 2000, minOpacity: 0.08);
      case AnimationEffect.fade:
        return const FadeEffect(holdMs: 1200, fadeMs: 600);
      case AnimationEffect.burst:
        return const BurstEffect(periodMs: 1500, flashMs: 400, dimOpacity: 0.12);
    }
  }
}