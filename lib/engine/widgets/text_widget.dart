import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

class TextWidget extends MatrixWidget<TextLayer> {
  const TextWidget();

  // ─────────────────────────────────────────────────────────────────────────
  // Bionic / speed-reading helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Number of leading characters per word rendered at full (fixation) color.
  /// Follows the standard Bionic Reading fixation-point scale.
  static int _fixationLen(int wordLen) {
    if (wordLen <= 3) return 1;
    if (wordLen <= 5) return 2;
    if (wordLen <= 9) return 3;
    return (wordLen / 2).ceil();
  }

  /// Opacity multiplier applied to the non-fixation (trailing) characters.
  static const double _dimFactor = 1;

  /// Draw [text] with bionic emphasis starting at ([x], [y]).
  /// Opacity is on decimal 0.0–1.0 for the fixation part; the remainder is further dimmed by [_dimFactor].
  /// [scale] is 1 for normal rendering, 2 for double-pixel mode.
  /// Width advance per segment = `font.textWidth(seg) * scale + font.charGap * scale`,
  /// which correctly preserves the inter-character gap regardless of scale.
  void _drawBionic({
    required LedFont font,
    required PixelBuffer buffer,
    required String text,
    required Color fixationColor,
    required Color remainderColor,
    required int x,
    required int y,
    required double opacity,
    int scale = 1,
  }) {
    final words = text.split(' ');
    int cx = x;

    for (int wi = 0; wi < words.length; wi++) {
      final word = words[wi];

      if (word.isEmpty) {
        cx += font.textWidth(' ') * scale + font.charGap * scale;
        continue;
      }

      final int fixLen  = _fixationLen(word.length);
      final String fix  = word.substring(0, fixLen);
      final String rest = word.substring(fixLen);

      // Fixation letters — highlight color, full opacity
      _drawSegment(font, buffer, fix, fixationColor, cx, y, opacity, scale);
      cx += font.textWidth(fix) * scale + font.charGap * scale;

      // Remainder letters — base color, dimmed
      if (rest.isNotEmpty) {
        _drawSegment(font, buffer, rest, remainderColor, cx, y, opacity * _dimFactor, scale);
        cx += font.textWidth(rest) * scale + font.charGap * scale;
      }

      // Inter-word space (skip after the last word)
      if (wi < words.length - 1) {
        cx += font.textWidth(' ') * scale + font.charGap * scale;
      }
    }
  }

  /// Draw a text segment — routes to [LedFont.draw] or [LedFont.drawScaled]
  /// depending on [scale].
  void _drawSegment(
    LedFont font,
    PixelBuffer buffer,
    String text,
    Color color,
    int x,
    int y,
    double opacity,
    int scale,
  ) {
    if (scale > 1) {
      font.drawScaled(
        buffer: buffer, text: text, color: color,
        x: x, y: y, scale: scale, opacity: opacity,
      );
    } else {
      font.draw(
        buffer: buffer, text: text, color: color,
        x: x, y: y, opacity: opacity,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void render(TextLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font  = LedFontLibrary.get(layer.fontId);
    final int scale = layer.doublePixel ? 2 : 1;

    // Blink — early exit so the buffer stays blank for the off-phase.
    if (layer.effect == AnimationEffect.blink) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    // Content width and vertical centre both account for the pixel scale.
    final int contentW = font.textWidth(layer.text) * scale;
    final int canvasW  = buffer.width;
    final int yOff     = layer.offset.dy.round() +
        (buffer.height - font.charHeight * scale) ~/ 2;
    final int xOff     = layer.offset.dx.round();

    // Draw at a resolved x using whichever combination of modes is active.
    void drawAt(int x) {
      if (layer.speedReading) {
        _drawBionic(
          font:           font,
          buffer:         buffer,
          text:           layer.text,
          fixationColor:  layer.speedReadingColor,
          remainderColor: layer.color,
          x:              x,
          y:              yOff,
          opacity:        layer.opacity,
          scale:          scale,
        );
      } else {
        _drawSegment(font, buffer, layer.text, layer.color, x, yOff, layer.opacity, scale);
      }
    }

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
      drawAt(startX + xOff);
      return;
    }

    // ── Static draw ───────────────────────────────────────────────────────
    switch (layer.alignment) {
      case TextAlignment.left:
        drawAt(xOff);
      case TextAlignment.center:
        drawAt((canvasW - contentW) ~/ 2 + xOff);
      case TextAlignment.right:
        drawAt(canvasW - contentW + xOff);
    }
  }
}