import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Renders a [TextLayer] into a [PixelBuffer] using the active [LedFont].
///
/// Scroll behaviour: text enters from off-screen and exits fully before
/// repeating. Period = contentWidth + canvasWidth, so there is always a
/// full canvas gap between repetitions.
class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);

    // ── Blink ─────────────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    final int contentW = font.textWidth(layer.text);
    final int canvasW  = buffer.width;

    // ── Vertical centre ───────────────────────────────────────────────────
    final int yOff =
        layer.offset.dy.round() + (buffer.height - font.charHeight) ~/ 2;

    // ── Marquee scroll ────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.scrollLeft ||
        layer.effect == AnimationEffect.scrollRight) {
      final int speed  = layer.effectSpeedMs.clamp(20, 500);
      final int period = contentW + canvasW;
      final int rawTick = (elapsedMs ~/ speed) % period;

      int startX;
      if (layer.effect == AnimationEffect.scrollLeft) {
        startX = canvasW - rawTick;
      } else {
        startX = -contentW + rawTick;
      }
      startX += layer.offset.dx.round();

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

    // ── Static alignment ──────────────────────────────────────────────────
    final int xOff = layer.offset.dx.round();

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
        font.drawCentered(
          buffer:      buffer,
          text:        layer.text,
          color:       layer.color,
          bufferWidth: canvasW,
          y:           yOff,
          opacity:     layer.opacity,
        );
      case TextAlignment.right:
        font.drawRight(
          buffer:    buffer,
          text:      layer.text,
          color:     layer.color,
          rightEdge: canvasW + xOff,
          y:         yOff,
          opacity:   layer.opacity,
        );
    }
  }
}