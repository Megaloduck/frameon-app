import '../scene/layer.dart';
import '../renderer/pixel_buffer.dart';
import 'effects/base_effect.dart';
import 'effects/blink.dart';
import 'effects/scroll_left.dart';
import 'effects/scroll_right.dart';

/// Resolves the correct [AnimationEffectProcessor] for a given [Layer]
/// and applies it during rendering.
///
/// The [Animator] is stateless — it is instantiated once and reused
/// across all render calls.
class Animator {
  const Animator();

  /// Return the [AnimationEffectProcessor] for [layer], or `null` if
  /// the layer has no animation effect.
  AnimationEffectProcessor? effectFor(Layer layer) {
    // Currently only TextLayer exposes an effect field.
    // Other layers (e.g. SpotifyLayer) may add effects in future iterations.
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