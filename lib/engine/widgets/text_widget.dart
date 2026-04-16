import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Renders a [TextLayer] into a [PixelBuffer] using the active [LedFont].
///
/// ## Effect responsibilities
///
/// | Effect          | Handled by          | How                                    |
/// |-----------------|---------------------|----------------------------------------|
/// | none            | TextWidget          | Draw static text                       |
/// | blink           | TextWidget          | Early-exit on odd 500 ms tick          |
/// | scrollLeft      | TextWidget          | Marquee x-offset calculation           |
/// | scrollRight     | TextWidget          | Marquee x-offset calculation           |
/// | pulse           | Animator (post)     | TextWidget draws at full opacity;      |
/// |                 |                     | Animator modulates alpha per-pixel     |
/// | fade            | Animator (post)     | Same — linear fade applied post-draw   |
/// | burst           | Animator (post)     | Same — exponential decay post-draw     |
///
/// For pulse / fade / burst, TextWidget draws the text normally at full
/// opacity. The [Animator] then runs [AnimationEffectProcessor.apply] on the
/// resulting [PixelBuffer], modulating per-pixel alpha to produce the effect.
/// This clean split means the text layout logic never needs to know about
/// opacity math.
class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);

    // ── Blink — early exit so the Animator sees a blank src buffer ─────────
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    final int contentW = font.textWidth(layer.text);
    final int canvasW  = buffer.width;

    // ── Vertical centre ───────────────────────────────────────────────────
    final int yOff =
        layer.offset.dy.round() + (buffer.height - font.charHeight) ~/ 2;

    // ── Marquee scroll (scrollLeft / scrollRight) ─────────────────────────
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

    // ── Static draw (none / blink-visible / pulse / fade / burst) ─────────
    //
    // For pulse, fade and burst, we draw at full layer.opacity here.
    // The Animator post-processes the buffer to apply the alpha modulation.
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