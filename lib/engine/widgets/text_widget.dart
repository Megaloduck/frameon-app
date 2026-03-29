import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../renderer/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Renders a [TextLayer] into a [PixelBuffer] using the real 5×7 [PixelFont].
///
/// Handles:
/// - Blink effect  (hide every odd 500 ms window)
/// - Scroll-left / scroll-right  (pixel offset driven by [elapsedMs])
/// - Text alignment  (left / center / right)
/// - Opacity  (forwarded to the font renderer)
class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    // ── Blink ─────────────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    // ── Scroll offset ─────────────────────────────────────────────────────
    final int contentW = PixelFont.measureWidth(layer.text);
    // Period = content width + canvas width so text fully exits before looping.
    final int period = contentW + buffer.width;
    int xOff = layer.offset.dx.round();

    if (layer.effect == AnimationEffect.scrollLeft) {
      final int speed = layer.effectSpeedMs.clamp(20, 500);
      xOff += -(elapsedMs ~/ speed) % period;
    } else if (layer.effect == AnimationEffect.scrollRight) {
      final int speed = layer.effectSpeedMs.clamp(20, 500);
      xOff += (elapsedMs ~/ speed) % period;
    }

    // ── Vertical centre ───────────────────────────────────────────────────
    final int yOff =
        layer.offset.dy.round() + (buffer.height - PixelFont.glyphHeight) ~/ 2;

    // ── Draw ──────────────────────────────────────────────────────────────
    switch (layer.alignment) {
      case TextAlignment.left:
        PixelFont.draw(
          buffer: buffer,
          text: layer.text,
          color: layer.color,
          x: xOff,
          y: yOff,
          opacity: layer.opacity,
        );
      case TextAlignment.center:
        PixelFont.draw(
          buffer: buffer,
          text: layer.text,
          color: layer.color,
          x: ((buffer.width - contentW) ~/ 2) + xOff,
          y: yOff,
          opacity: layer.opacity,
        );
      case TextAlignment.right:
        PixelFont.drawRight(
          buffer: buffer,
          text: layer.text,
          color: layer.color,
          rightEdge: buffer.width + xOff,
          y: yOff,
          opacity: layer.opacity,
        );
    }
  }
}