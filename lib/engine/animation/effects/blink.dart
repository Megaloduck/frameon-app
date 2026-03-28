import '../../renderer/pixel_buffer.dart';
import 'base_effect.dart';

/// Toggles the layer on/off at [periodMs] intervals.
///
/// The layer is visible for the first half of each period and invisible
/// for the second half (50% duty cycle).
class BlinkEffect extends AnimationEffectProcessor {
  /// Full on/off cycle in milliseconds. Default: 1000 ms (1 Hz blink).
  final int periodMs;

  const BlinkEffect({this.periodMs = 1000});

  @override
  void apply(PixelBuffer src, PixelBuffer dst, int elapsedMs) {
    final bool visible = (elapsedMs % periodMs) < (periodMs ~/ 2);
    if (visible) {
      dst.copyFrom(src);
    } else {
      dst.clear(); // transparent — layer hidden
    }
  }
}