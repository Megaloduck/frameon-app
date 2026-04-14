import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../renderer/fonts/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Renders a [TextLayer] into a [PixelBuffer] using the 5×7 [PixelFont].
///
/// For scroll effects, the text is drawn at a position that creates a true
/// marquee — the text enters from off-screen and exits fully before repeating.
/// The scroll animation period = contentWidth + canvasWidth, so there is always
/// a gap of one full canvas width between repetitions.
class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    // ── Blink ─────────────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    final int contentW = PixelFont.measureWidth(layer.text);
    final int canvasW  = buffer.width;

    // ── Vertical centre ───────────────────────────────────────────────────
    final int yOff =
        layer.offset.dy.round() + (buffer.height - PixelFont.glyphHeight) ~/ 2;

    // ── Marquee scroll ────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.scrollLeft ||
        layer.effect == AnimationEffect.scrollRight) {
      final int speed = layer.effectSpeedMs.clamp(20, 500);
      // Full loop = text width + canvas width so text is fully off-screen
      // before restarting.
      final int period = contentW + canvasW;
      final int rawTick = (elapsedMs ~/ speed) % period;

      int startX;
      if (layer.effect == AnimationEffect.scrollLeft) {
        // Text starts just off the right edge, moves left, exits left edge.
        startX = canvasW - rawTick;
      } else {
        // Text starts just off the left edge, moves right, exits right edge.
        startX = -contentW + rawTick;
      }

      // Apply manual offset on top of marquee position
      startX += layer.offset.dx.round();

      PixelFont.draw(
        buffer:  buffer,
        text:    layer.text,
        color:   layer.color,
        x:       startX,
        y:       yOff,
        opacity: layer.opacity,
      );
      return;
    }

    // ── Static alignment (no scroll) ──────────────────────────────────────
    final int xOff = layer.offset.dx.round();

    switch (layer.alignment) {
      case TextAlignment.left:
        PixelFont.draw(
          buffer:  buffer,
          text:    layer.text,
          color:   layer.color,
          x:       xOff,
          y:       yOff,
          opacity: layer.opacity,
        );
      case TextAlignment.center:
        PixelFont.draw(
          buffer:  buffer,
          text:    layer.text,
          color:   layer.color,
          x:       ((canvasW - contentW) ~/ 2) + xOff,
          y:       yOff,
          opacity: layer.opacity,
        );
      case TextAlignment.right:
        PixelFont.drawRight(
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