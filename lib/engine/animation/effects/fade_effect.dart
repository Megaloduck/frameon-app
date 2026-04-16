import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Linear fade-in / fade-out cycle.
///
/// The layer spends [holdMs] fully visible, then fades out over [fadeMs],
/// holds fully invisible for [holdMs], and fades back in over [fadeMs].
///
/// Total period = holdMs + fadeMs + holdMs + fadeMs.
class FadeEffect extends AnimationEffectProcessor {
  /// Duration of the fully-visible hold phase in ms.
  final int holdMs;

  /// Duration of each fade transition in ms.
  final int fadeMs;

  const FadeEffect({
    this.holdMs = 1200,
    this.fadeMs = 600,
  });

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final int period = holdMs * 2 + fadeMs * 2;
    final int t = elapsedMs % period;

    double opacity;

    if (t < holdMs) {
      // Phase 1 — fully visible hold
      opacity = 1.0;
    } else if (t < holdMs + fadeMs) {
      // Phase 2 — fade out
      opacity = 1.0 - (t - holdMs) / fadeMs;
    } else if (t < holdMs * 2 + fadeMs) {
      // Phase 3 — fully invisible hold
      opacity = 0.0;
    } else {
      // Phase 4 — fade in
      opacity = (t - (holdMs * 2 + fadeMs)) / fadeMs;
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