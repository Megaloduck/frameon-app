import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);

    // Blink — early exit so the buffer stays blank for the off-phase.
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    final int contentW = font.textWidth(layer.text);
    final int canvasW  = buffer.width;

    // Vertical position — centred, then shifted by offset.dy.
    final int yOff = layer.offset.dy.round() + (buffer.height - font.charHeight) ~/ 2;

    // Horizontal position — offset.dx applied in every branch.
    final int xOff = layer.offset.dx.round();

    // ── Marquee scroll ────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.scrollLeft ||
        layer.effect == AnimationEffect.scrollRight) {
      final int speed   = layer.effectSpeedMs.clamp(20, 500);
      final int period  = contentW + canvasW;
      final int rawTick = (elapsedMs ~/ speed) % period;

      int startX;
      if (layer.effect == AnimationEffect.scrollLeft) {
        startX = canvasW - rawTick;
      } else {
        startX = -contentW + rawTick;
      }
      startX += xOff;

      font.draw(
        buffer:  buffer,
        text:    layer.text,
        color:   layer.color,
        x:       startX,
        y:       yOff,
        opacity: layer.opacity,
      );
      return;
    }

    // ── Static draw ───────────────────────────────────────────────────────
    // For all three alignment modes, offset.dx shifts the final x position.
    // Previously the `center` branch used drawCentered() which ignores xOff.
    // Now every branch computes x manually so dragging always works.
    switch (layer.alignment) {
      case TextAlignment.left:
        font.draw(
          buffer:  buffer,
          text:    layer.text,
          color:   layer.color,
          x:       xOff,
          y:       yOff,
          opacity: layer.opacity,
        );

      case TextAlignment.center:
        // Compute the centred origin, then shift by the drag offset.
        font.draw(
          buffer:  buffer,
          text:    layer.text,
          color:   layer.color,
          x:       (canvasW - contentW) ~/ 2 + xOff,
          y:       yOff,
          opacity: layer.opacity,
        );

      case TextAlignment.right:
        font.draw(
          buffer:  buffer,
          text:    layer.text,
          color:   layer.color,
          x:       canvasW - contentW + xOff,
          y:       yOff,
          opacity: layer.opacity,
        );
    }
  }
}