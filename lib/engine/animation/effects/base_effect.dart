import '../../renderer/pixel_buffer.dart';

/// Applies a time-based transformation from [src] into [dst].
///
/// Implementations should treat [src] as immutable and always write a full
/// frame into [dst].
abstract class AnimationEffectProcessor {
  const AnimationEffectProcessor();

  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs);
}