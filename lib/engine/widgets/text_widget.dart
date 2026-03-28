import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Renders a [TextLayer] into a [PixelBuffer].
///
/// Handles:
/// - Blink effect (hides on odd 500 ms windows)
/// - Scroll-left / scroll-right offset computation
/// - Delegating glyph drawing to [_drawText] (pixel-font stub;
///   replace with a real PixelFont.render() call in the next phase)
class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    // ── Blink effect ─────────────────────────────────────────────────────
    if (layer.effect == AnimationEffect.blink) {
      // Hide during the second half of every 1-second cycle.
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    // ── Scroll offset ────────────────────────────────────────────────────
    // Content width: each glyph is 5px wide + 1px spacing (6px/char).
    // Scroll period = contentWidth + canvasWidth so the text fully exits
    // before wrapping, avoiding a visual snap.
    final int contentWidth = layer.text.length * 6;
    final int period = contentWidth + buffer.width;
    int xOffset = layer.offset.dx.round();

    if (layer.effect == AnimationEffect.scrollLeft) {
      // 1 pixel per [effectSpeedMs] ms — slower speed = larger value.
      final int speed = layer.effectSpeedMs.clamp(20, 500);
      xOffset += -(elapsedMs ~/ speed) % period;
    } else if (layer.effect == AnimationEffect.scrollRight) {
      final int speed = layer.effectSpeedMs.clamp(20, 500);
      xOffset += (elapsedMs ~/ speed) % period;
    }

    _drawText(
      buffer: buffer,
      text: layer.text,
      color: layer.color,
      xOffset: xOffset,
      yOffset: layer.offset.dy.round(),
      alignment: layer.alignment,
    );
  }

  // ── Pixel font stub ───────────────────────────────────────────────────────
  //
  // Approximates each glyph as a 5×7 filled rectangle.
  // Replace with PixelFont.render(text, style, color) → PixelBuffer
  // once the bitmap font atlas is implemented.

  void _drawText({
    required PixelBuffer buffer,
    required String text,
    required Color color,
    required int xOffset,
    required int yOffset,
    required TextAlignment alignment,
  }) {
    const int charW = 5;
    const int charH = 7;
    const int spacing = 1;
    final int totalW = text.length * (charW + spacing) - spacing;

    int startX;
    switch (alignment) {
      case TextAlignment.left:
        startX = xOffset;
      case TextAlignment.right:
        startX = buffer.width - totalW + xOffset;
      case TextAlignment.center:
        startX = ((buffer.width - totalW) ~/ 2) + xOffset;
    }

    final int startY = ((buffer.height - charH) ~/ 2) + yOffset;

    for (int i = 0; i < text.length; i++) {
      final int cx = startX + i * (charW + spacing);
      buffer.fillRect(cx, startY, charW, charH, color);
    }
  }
}