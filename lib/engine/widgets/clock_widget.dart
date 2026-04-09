import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../renderer/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

class ClockWidget extends MatrixWidget<ClockLayer> {
  const ClockWidget();

  // ── Spacing Configuration ─────────────────────────────
  static const int spacingBeforeColon = 2;
  static const int spacingAfterColon = 0  ;
  static const int spacingGeneral = 1;

  // 🔧 Visual fix for colon glyph imbalance
  // Try -1 or +1 depending on your font
  static const int colonVisualOffset = -1;

  @override
  void render(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final now = DateTime.now();

    // Blink without affecting layout
    final bool colonOn = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final String colonStr = ':';
    final double colonOpacity = colonOn ? layer.opacity : 0.0;

    final hoursStr = _buildHoursStr(now, layer);
    final minutesStr = _pad(now.minute);
    final secondsStr = layer.showSeconds ? _pad(now.second) : '';
    final dateStr = layer.showDate
        ? '${_pad(now.day)}.${_pad(now.month)}.${now.year % 100}'
        : '';
    final ampmStr = (layer.format != ClockFormat.h24)
        ? (now.hour < 12 ? 'AM' : 'PM')
        : '';

    final bool hasDate = dateStr.isNotEmpty;
    final bool hasSeconds = secondsStr.isNotEmpty;
    final bool hasAmPm = ampmStr.isNotEmpty;

    // ── Vertical Layout ─────────────────────────────────
    int totalHeight = PixelFont.glyphHeight;
    if (hasDate) totalHeight += PixelFont.glyphHeight + 2;

    final int startY = (buffer.height - totalHeight) ~/ 2;
    int currentY = startY;

    // ── DATE ────────────────────────────────────────────
    if (hasDate) {
      _drawAlignedText(
        buffer: buffer,
        text: dateStr,
        color: layer.dateColor,
        alignment: layer.alignment,
        offsetX: layer.offset.dx.round(),
        y: currentY,
        opacity: layer.opacity,
        bufferWidth: buffer.width,
      );
      currentY += PixelFont.glyphHeight + 2;
    }

    // ── WIDTH CALCULATION ───────────────────────────────
    final int totalWidth = _calculateTimeWidth(
      hoursStr,
      minutesStr,
      secondsStr,
      hasAmPm,
      ampmStr,
    );

    int currentX = _getStartX(
      buffer,
      totalWidth,
      layer.alignment,
      layer.offset.dx.round(),
    );

    // ── HOURS ───────────────────────────────────────────
    _drawText(buffer, hoursStr, layer.hoursColor, currentX, currentY, layer.opacity);
    currentX += PixelFont.measureWidth(hoursStr);

    // ── FIRST COLON ─────────────────────────────────────
    currentX += spacingBeforeColon;

    _drawText(
      buffer,
      colonStr,
      layer.colonColor,
      currentX + colonVisualOffset, // 👈 visual fix here
      currentY,
      colonOpacity,
    );

    currentX += PixelFont.measureWidth(colonStr);
    currentX += spacingAfterColon;

    // ── MINUTES ─────────────────────────────────────────
    _drawText(buffer, minutesStr, layer.minutesColor, currentX, currentY, layer.opacity);
    currentX += PixelFont.measureWidth(minutesStr);

    // ── SECONDS ─────────────────────────────────────────
    if (hasSeconds) {
      currentX += spacingBeforeColon;

      _drawText(
        buffer,
        colonStr,
        layer.colonColor,
        currentX + colonVisualOffset, // 👈 same fix here
        currentY,
        colonOpacity,
      );

      currentX += PixelFont.measureWidth(colonStr);
      currentX += spacingAfterColon;

      _drawText(buffer, secondsStr, layer.secondsColor, currentX, currentY, layer.opacity);
      currentX += PixelFont.measureWidth(secondsStr);
    }

    // ── AM/PM ───────────────────────────────────────────
    if (hasAmPm) {
      currentX += spacingGeneral;

      _drawText(buffer, ampmStr, layer.minutesColor, currentX, currentY, layer.opacity);
    }
  }

  // ── Helpers ──────────────────────────────────────────

  String _buildHoursStr(DateTime now, ClockLayer layer) {
    if (layer.format == ClockFormat.h24) {
      return _pad(now.hour);
    } else {
      final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
      return h.toString();
    }
  }

  int _calculateTimeWidth(
    String hours,
    String minutes,
    String seconds,
    bool hasAmPm,
    String ampm,
  ) {
    int width = PixelFont.measureWidth(hours);

    width += spacingBeforeColon;
    width += PixelFont.measureWidth(':');
    width += spacingAfterColon;

    width += PixelFont.measureWidth(minutes);

    if (seconds.isNotEmpty) {
      width += spacingBeforeColon;
      width += PixelFont.measureWidth(':');
      width += spacingAfterColon;

      width += PixelFont.measureWidth(seconds);
    }

    if (hasAmPm) {
      width += spacingGeneral;
      width += PixelFont.measureWidth(ampm);
    }

    return width;
  }

  int _getStartX(
    PixelBuffer buffer,
    int totalWidth,
    ClockAlignment alignment,
    int offsetX,
  ) {
    switch (alignment) {
      case ClockAlignment.left:
        return offsetX;
      case ClockAlignment.center:
        return ((buffer.width - totalWidth) ~/ 2) + offsetX;
      case ClockAlignment.right:
        return buffer.width - totalWidth + offsetX;
    }
  }

  void _drawAlignedText({
    required PixelBuffer buffer,
    required String text,
    required Color color,
    required ClockAlignment alignment,
    required int offsetX,
    required int y,
    required double opacity,
    required int bufferWidth,
  }) {
    if (text.isEmpty) return;

    switch (alignment) {
      case ClockAlignment.left:
        PixelFont.draw(
          buffer: buffer,
          text: text,
          color: color,
          x: offsetX,
          y: y,
          opacity: opacity,
        );
        break;

      case ClockAlignment.center:
        PixelFont.drawCentered(
          buffer: buffer,
          text: text,
          color: color,
          bufferWidth: bufferWidth,
          y: y,
          opacity: opacity,
        );
        break;

      case ClockAlignment.right:
        PixelFont.drawRight(
          buffer: buffer,
          text: text,
          color: color,
          rightEdge: bufferWidth + offsetX,
          y: y,
          opacity: opacity,
        );
        break;
    }
  }

  void _drawText(
    PixelBuffer buffer,
    String text,
    Color color,
    int x,
    int y,
    double opacity,
  ) {
    if (text.isEmpty) return;

    PixelFont.draw(
      buffer: buffer,
      text: text,
      color: color,
      x: x,
      y: y,
      opacity: opacity,
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}