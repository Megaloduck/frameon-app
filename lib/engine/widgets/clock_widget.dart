import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';
import '../../../shared/providers/time_service.dart';

class ClockWidget extends MatrixWidget<ClockLayer> {
  const ClockWidget();

  // ── Glyph spacing constants (shared across text-based styles) ─────────────
  static const int spacingBeforeColon = 2;
  static const int spacingAfterColon  = 0;
  static const int spacingGeneral     = 1;
  static const int colonVisualOffset  = -1;

  // ── Analog defaults ───────────────────────────────────────────────────────
  // Radius 14 fits a 32-row matrix with 1-px breathing room. The left-side
  // face center sits at x=15 so the rim occupies cols 1..29, leaving the
  // right half (cols 32..63) for the digital readout.
  // Half-pixel centre (15.5, 15.5) + radius 13.5 gives symmetric 2 px margins
  // on all four sides of a 32-px panel: round(15.5 ± 13.5) = 2 and 29.
  static const double _analogFaceRadius = 13.5;
  static const double _analogFaceLeftCx = 15.5;

  // ── Weekday short names — DateTime.weekday is 1-7 with Mon=1 ──────────────
  static const List<String> _kWeekdayShort = [
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN',
  ];

  static ProviderContainer? _container;
  static void init(ProviderContainer container) => _container = container;

  /// Render the clock layer into [buffer] for the live preview only.
  ///
  /// During device export this is a no-op — the clock descriptor travels in
  /// the packet header and the firmware renders the clock live via
  /// overdrawClock() using millis().
  ///
  /// [isExport] is set true by the renderer during timeline baking so the
  /// buffer stays transparent.
  @override
  void render(ClockLayer layer, PixelBuffer buffer, int elapsedMs,
      {bool isExport = false}) {
    if (isExport) return;

    switch (layer.layoutStyle) {
      case ClockLayoutStyle.classic:
        _renderClassic(layer, buffer, elapsedMs);
      case ClockLayoutStyle.analog:
        _renderAnalog(layer, buffer, elapsedMs);
      case ClockLayoutStyle.weekdayPrefix:
        _renderWeekdayPrefix(layer, buffer, elapsedMs);
      case ClockLayoutStyle.stacked:
        _renderStacked(layer, buffer, elapsedMs);
      case ClockLayoutStyle.secondsBar:
        _renderSecondsBar(layer, buffer, elapsedMs);
      case ClockLayoutStyle.dualTimezone:
        _renderDualTz(layer, buffer, elapsedMs);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CLASSIC — original behavior, factored
  // ═════════════════════════════════════════════════════════════════════════

  void _renderClassic(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);
    final DateTime now = _getTimeForZone(layer.timezone);

    final bool   colonOn    = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final double colonAlpha = colonOn ? layer.opacity : 0.0;

    final hoursStr   = _buildHoursStr(now, layer);
    final minutesStr = _pad(now.minute);
    final secondsStr = layer.showSeconds ? _pad(now.second) : '';
    final dateStr    = layer.showDate
        ? '${_pad(now.day)}.${_pad(now.month)}.${now.year % 100}'
        : '';
    final ampmStr = layer.format == ClockFormat.h12
        ? (now.hour < 12 ? 'AM' : 'PM')
        : '';

    final bool hasDate    = dateStr.isNotEmpty;
    final bool hasSeconds = secondsStr.isNotEmpty;
    final bool hasAmPm    = ampmStr.isNotEmpty;

    final int totalHeight =
        font.charHeight + (hasDate ? font.charHeight + 2 : 0);
    final int startY =
        (buffer.height - totalHeight) ~/ 2 + layer.offset.dy.round();
    final int timeY  = startY;
    final int dateY  = startY + font.charHeight + 2;

    final int totalWidth = _calcTimeWidth(
        font, hoursStr, minutesStr, secondsStr, hasAmPm, ampmStr);
    int cx = ((buffer.width - totalWidth) ~/ 2) + layer.offset.dx.round();

    font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
        x: cx, y: timeY, opacity: layer.opacity);
    cx += font.textWidth(hoursStr);

    cx += spacingBeforeColon;
    font.draw(buffer: buffer, text: ':', color: layer.colonColor,
        x: cx + colonVisualOffset, y: timeY, opacity: colonAlpha);
    cx += font.textWidth(':') + spacingAfterColon;

    font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
        x: cx, y: timeY, opacity: layer.opacity);
    cx += font.textWidth(minutesStr);

    if (hasSeconds) {
      cx += spacingBeforeColon;
      font.draw(buffer: buffer, text: ':', color: layer.colonColor,
          x: cx + colonVisualOffset, y: timeY, opacity: colonAlpha);
      cx += font.textWidth(':') + spacingAfterColon;
      font.draw(buffer: buffer, text: secondsStr, color: layer.secondsColor,
          x: cx, y: timeY, opacity: layer.opacity);
      cx += font.textWidth(secondsStr);
    }

    if (hasAmPm) {
      cx += spacingGeneral;
      font.draw(buffer: buffer, text: ampmStr, color: layer.ampmColor,
          x: cx, y: timeY, opacity: layer.opacity);
    }

    if (hasDate) {
      final int dateX = (buffer.width - font.textWidth(dateStr)) ~/ 2
          + layer.offset.dx.round();
      font.draw(buffer: buffer, text: dateStr, color: layer.dateColor,
          x: dateX, y: dateY, opacity: layer.opacity);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ANALOG — circular face with hands, optional digital readout
  // ═════════════════════════════════════════════════════════════════════════

  void _renderAnalog(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final DateTime now = _getTimeForZone(layer.timezone);
    final bool showDigital = layer.analogShowDigital;

    // Face centre at half-pixel (15.5, 15.5) → 2 px margin all sides.
    final double faceCx = (showDigital
            ? _analogFaceLeftCx
            : (buffer.width - 1) / 2.0) +
        layer.offset.dx.round();
    final double faceCy =
        (buffer.height - 1) / 2.0 + layer.offset.dy.round();
    const double radius = _analogFaceRadius;

    // Rim — uses ampmColor (repurposed as face-ring colour in analog mode)
    _drawCircleOutline(
        buffer, faceCx, faceCy, radius, layer.ampmColor, layer.opacity);

    // Hour markers — uses dateColor (independently configurable from rim)
    _drawFaceMarkers(buffer, faceCx, faceCy, radius,
        layer.analogFaceStyle, layer.dateColor, layer.opacity);

    // Hand angles (degrees, clockwise from 12 o'clock)
    final double minuteFraction = now.minute / 60.0;
    final double secondFraction = now.second / 60.0;
    final double hourAngle   = ((now.hour % 12) + minuteFraction) * 30.0;
    final double minuteAngle = (now.minute + secondFraction) * 6.0;
    final double secondAngle = now.second * 6.0;

    // Hands — order matters: hour first (shortest, easiest to occlude),
    // minute next, second hand on top.
    _drawHandFromAngle(buffer, faceCx, faceCy, hourAngle,
        radius - 7, layer.hoursColor, layer.opacity);
    _drawHandFromAngle(buffer, faceCx, faceCy, minuteAngle,
        radius - 2, layer.minutesColor, layer.opacity);
    if (layer.showSecondHand) {
      _drawHandFromAngle(buffer, faceCx, faceCy, secondAngle,
          radius - 1, layer.secondsColor, layer.opacity);
    }

    // Center pivot in hour-hand color
    buffer.setPixelColor(
        faceCx.round(), faceCy.round(), layer.hoursColor.withOpacity(layer.opacity));

    // Digital readout on the right half
    if (showDigital) {
      final font = LedFontLibrary.get(layer.fontId);
      final String hoursStr   = _buildHoursStr(now, layer);
      final String minutesStr = _pad(now.minute);

      final bool   colonOn    = !layer.blinkColon || (elapsedMs % 1000) < 500;
      final double colonAlpha = colonOn ? layer.opacity : 0.0;

      final int timeW = font.textWidth(hoursStr)
          + spacingBeforeColon + font.textWidth(':') + spacingAfterColon
          + font.textWidth(minutesStr);

      // Center the readout within the right half (cols 32..63 = 32 wide).
      const int rightHalfStart = 32;
      const int rightHalfWidth = 32;
      final int xStart = rightHalfStart + (rightHalfWidth - timeW) ~/ 2
          + layer.offset.dx.round();
      final int y = (buffer.height - font.charHeight) ~/ 2
          + layer.offset.dy.round();

      int cx = xStart;
      font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
          x: cx, y: y, opacity: layer.opacity);
      cx += font.textWidth(hoursStr) + spacingBeforeColon;
      font.draw(buffer: buffer, text: ':', color: layer.colonColor,
          x: cx + colonVisualOffset, y: y, opacity: colonAlpha);
      cx += font.textWidth(':') + spacingAfterColon;
      font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
          x: cx, y: y, opacity: layer.opacity);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // WEEKDAY PREFIX — "MON 14:30"
  // ═════════════════════════════════════════════════════════════════════════

  void _renderWeekdayPrefix(
      ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);
    final DateTime now = _getTimeForZone(layer.timezone);
    final String weekday = _kWeekdayShort[(now.weekday - 1) % 7];
    final String hoursStr   = _buildHoursStr(now, layer);
    final String minutesStr = _pad(now.minute);

    final bool   colonOn    = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final double colonAlpha = colonOn ? layer.opacity : 0.0;

    const int gap = 2; // gap between weekday and time
    final int weekdayW = font.textWidth(weekday);
    final int timeW = font.textWidth(hoursStr)
        + spacingBeforeColon + font.textWidth(':') + spacingAfterColon
        + font.textWidth(minutesStr);
    final int totalW = weekdayW + gap + timeW;

    final int startX =
        (buffer.width - totalW) ~/ 2 + layer.offset.dx.round();
    final int y = (buffer.height - font.charHeight) ~/ 2
        + layer.offset.dy.round();

    int cx = startX;
    font.draw(buffer: buffer, text: weekday, color: layer.ampmColor,
        x: cx, y: y, opacity: layer.opacity);
    cx += weekdayW + gap;
    font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
        x: cx, y: y, opacity: layer.opacity);
    cx += font.textWidth(hoursStr) + spacingBeforeColon;
    font.draw(buffer: buffer, text: ':', color: layer.colonColor,
        x: cx + colonVisualOffset, y: y, opacity: colonAlpha);
    cx += font.textWidth(':') + spacingAfterColon;
    font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
        x: cx, y: y, opacity: layer.opacity);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STACKED — HH on top row, MM on bottom row, both centered
  // ═════════════════════════════════════════════════════════════════════════

  void _renderStacked(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);
    final DateTime now = _getTimeForZone(layer.timezone);
    final String hoursStr   = _buildHoursStr(now, layer);
    final String minutesStr = _pad(now.minute);

    final int totalH = font.charHeight * 2 + 2;
    final int startY =
        (buffer.height - totalH) ~/ 2 + layer.offset.dy.round();

    final int hourW = font.textWidth(hoursStr);
    final int hourX =
        (buffer.width - hourW) ~/ 2 + layer.offset.dx.round();
    font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
        x: hourX, y: startY, opacity: layer.opacity);

    final int minW = font.textWidth(minutesStr);
    final int minX =
        (buffer.width - minW) ~/ 2 + layer.offset.dx.round();
    font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
        x: minX, y: startY + font.charHeight + 2, opacity: layer.opacity);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SECONDS BAR — HH:MM with a 2-px progress bar below
  // ═════════════════════════════════════════════════════════════════════════

  void _renderSecondsBar(
      ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);
    final DateTime now = _getTimeForZone(layer.timezone);
    final String hoursStr   = _buildHoursStr(now, layer);
    final String minutesStr = _pad(now.minute);

    final bool   colonOn    = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final double colonAlpha = colonOn ? layer.opacity : 0.0;

    const int barH = 2;
    const int gap  = 2;
    final int totalH = font.charHeight + gap + barH;
    final int startY =
        (buffer.height - totalH) ~/ 2 + layer.offset.dy.round();
    final int timeY  = startY;
    final int barY   = startY + font.charHeight + gap;

    // Time row
    final int timeW = font.textWidth(hoursStr)
        + spacingBeforeColon + font.textWidth(':') + spacingAfterColon
        + font.textWidth(minutesStr);
    int cx = (buffer.width - timeW) ~/ 2 + layer.offset.dx.round();
    font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
        x: cx, y: timeY, opacity: layer.opacity);
    cx += font.textWidth(hoursStr) + spacingBeforeColon;
    font.draw(buffer: buffer, text: ':', color: layer.colonColor,
        x: cx + colonVisualOffset, y: timeY, opacity: colonAlpha);
    cx += font.textWidth(':') + spacingAfterColon;
    font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
        x: cx, y: timeY, opacity: layer.opacity);

    // Bar — 50 px wide, centered. Track is dim (12 % of bar color), fill
    // is solid in secondsColor.
    const int barW = 50;
    final int barX = (buffer.width - barW) ~/ 2 + layer.offset.dx.round();
    final Color trackColor =
        const Color(0xFF444444).withOpacity(layer.opacity);
    final Color fillColor =
        layer.secondsColor.withOpacity(layer.opacity);

    _fillRect(buffer, barX, barY, barW, barH, trackColor);
    final int filled = (barW * now.second / 60).round();
    if (filled > 0) {
      _fillRect(buffer, barX, barY, filled, barH, fillColor);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DUAL TIMEZONE — two zones stacked vertically
  // ═════════════════════════════════════════════════════════════════════════

  void _renderDualTz(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);
    final DateTime now1 = _getTimeForZone(layer.timezone);
    final DateTime now2 = _getTimeForZone(layer.secondTimezone);

    final String label1 = layer.firstZoneLabel.isNotEmpty
        ? layer.firstZoneLabel
        : defaultZoneLabel(layer.timezone);
    final String label2 = layer.secondZoneLabel.isNotEmpty
        ? layer.secondZoneLabel
        : defaultZoneLabel(layer.secondTimezone);

    final bool   colonOn    = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final double colonAlpha = colonOn ? layer.opacity : 0.0;

    final int totalH = font.charHeight * 2 + 2;
    final int startY =
        (buffer.height - totalH) ~/ 2 + layer.offset.dy.round();
    final int row1Y = startY;
    final int row2Y = startY + font.charHeight + 2;

    _drawZoneRow(buffer, font, label1, now1, row1Y, colonAlpha, layer);
    _drawZoneRow(buffer, font, label2, now2, row2Y, colonAlpha, layer);
  }

  void _drawZoneRow(PixelBuffer buffer, LedFont font, String label,
      DateTime now, int y, double colonAlpha, ClockLayer layer) {
    final String hoursStr   = _buildHoursStr(now, layer);
    final String minutesStr = _pad(now.minute);

    const int gap = 2;
    final int labelW = font.textWidth(label);
    final int timeW = font.textWidth(hoursStr)
        + spacingBeforeColon + font.textWidth(':') + spacingAfterColon
        + font.textWidth(minutesStr);
    final int totalW = labelW + gap + timeW;

    int cx = (buffer.width - totalW) ~/ 2 + layer.offset.dx.round();
    font.draw(buffer: buffer, text: label, color: layer.ampmColor,
        x: cx, y: y, opacity: layer.opacity);
    cx += labelW + gap;
    font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
        x: cx, y: y, opacity: layer.opacity);
    cx += font.textWidth(hoursStr) + spacingBeforeColon;
    font.draw(buffer: buffer, text: ':', color: layer.colonColor,
        x: cx + colonVisualOffset, y: y, opacity: colonAlpha);
    cx += font.textWidth(':') + spacingAfterColon;
    font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
        x: cx, y: y, opacity: layer.opacity);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Drawing primitives — line, circle outline, face markers, fill rect
  // ═════════════════════════════════════════════════════════════════════════

  /// Bresenham's line algorithm. `setPixel` is bounds-safe so out-of-canvas
  /// segments simply don't paint.
  void _drawLine(PixelBuffer buf, int x0, int y0, int x1, int y1,
      Color color, double opacity) {
    final int argb = color.withOpacity(opacity).value;
    final int dx = (x1 - x0).abs();
    final int dy = -(y1 - y0).abs();
    final int sx = x0 < x1 ? 1 : -1;
    final int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    int x = x0;
    int y = y0;
    while (true) {
      buf.setPixel(x, y, argb);
      if (x == x1 && y == y1) break;
      final int e2 = 2 * err;
      if (e2 >= dy) { err += dy; x += sx; }
      if (e2 <= dx) { err += dx; y += sy; }
    }
  }

  /// Midpoint circle algorithm — single-pixel rim, no fill.
  /// Parametric circle — supports fractional centre and radius so the face
  /// can be centred at (15.5, 15.5) r=13.5 for symmetric 2-px margins.
  void _drawCircleOutline(PixelBuffer buf, double cx, double cy, double r,
      Color color, double opacity) {
    final int argb  = color.withOpacity(opacity).value;
    final int steps = (2 * pi * r * 2).ceil().clamp(64, 512);
    for (int i = 0; i < steps; i++) {
      final double angle = 2 * pi * i / steps;
      final int px = (cx + r * cos(angle)).round();
      final int py = (cy - r * sin(angle)).round();
      if (px >= 0 && px < buf.width && py >= 0 && py < buf.height) {
        buf.setPixel(px, py, argb);
      }
    }
  }

  /// Draws a hand from the face center to a point on a circle of radius
  /// [length] at clockwise angle [angleDeg] (0° = 12 o'clock).
  void _drawHandFromAngle(PixelBuffer buf, double cx, double cy, double angleDeg,
      double length, Color color, double opacity) {
    final double rad = angleDeg * pi / 180.0;
    final int xEnd = (cx + length * sin(rad)).round();
    final int yEnd = (cy - length * cos(rad)).round();
    _drawLine(buf, cx.round(), cy.round(), xEnd, yEnd, color, opacity);
  }

  /// Draws hour markers around the rim according to the configured style.
  void _drawFaceMarkers(PixelBuffer buf, double cx, double cy, double r,
      AnalogFaceStyle style, Color color, double opacity) {
    switch (style) {
      case AnalogFaceStyle.none:
        return;
      case AnalogFaceStyle.cardinalDots:
        for (final h in const [0, 3, 6, 9]) {
          _drawCardinalDot(buf, cx, cy, r, h, color, opacity);
        }
      case AnalogFaceStyle.allDots:
        for (int h = 0; h < 12; h++) {
          // Cardinal hours get shaped markers; the other 8 stay single-pixel.
          if (h == 0 || h == 3 || h == 6 || h == 9) {
            _drawCardinalDot(buf, cx, cy, r, h, color, opacity);
          } else {
            _drawHourDot(buf, cx, cy, r, h, color, opacity);
          }
        }
      case AnalogFaceStyle.ticks:
        for (final h in const [0, 3, 6, 9]) {
          _drawHourTick(buf, cx, cy, r, h, color, opacity);
        }
    }
  }

  /// Single-pixel dot one step inside the rim (used for non-cardinal hours).
  void _drawHourDot(PixelBuffer buf, double cx, double cy, double r, int hour,
      Color color, double opacity) {
    final double rad    = hour * 30.0 * pi / 180.0;
    final double innerR = r - 2;
    final int x = (cx + innerR * sin(rad)).round();
    final int y = (cy - innerR * cos(rad)).round();
    buf.setPixel(x, y, color.withOpacity(opacity).value);
  }

  /// Shaped cardinal dot — oriented perpendicular to the radius so it reads
  /// as a natural tick against the rim:
  ///   12 & 6 → 2×1 horizontal   (two pixels side-by-side, same Y)
  ///    3 & 9 → 1×2 vertical     (two pixels stacked,     same X)
  void _drawCardinalDot(PixelBuffer buf, double cx, double cy, double r,
      int hour, Color color, double opacity) {
    final double rad    = hour * 30.0 * pi / 180.0;
    final double innerR = r - 2;
    final double fx     = cx + innerR * sin(rad);
    final double fy     = cy - innerR * cos(rad);
    final int    argb   = color.withOpacity(opacity).value;

    if (hour == 0 || hour == 6) {
      // 2×1 horizontal — two adjacent X pixels at the same Y
      final int y = fy.round();
      buf.setPixel(fx.floor(), y, argb);
      buf.setPixel(fx.ceil(),  y, argb);
    } else {
      // 1×2 vertical — two adjacent Y pixels at the same X  (hour 3 or 9)
      final int x = fx.round();
      buf.setPixel(x, fy.floor(), argb);
      buf.setPixel(x, fy.ceil(),  argb);
    }
  }

  /// 2x2-pixel tick: 2 px deep from rim, 2 px wide (perpendicular to radius).
  void _drawHourTick(PixelBuffer buf, double cx, double cy, double r, int hour,
      Color color, double opacity) {
    final double rad  = hour * 30.0 * pi / 180.0;
    final int    argb = color.withOpacity(opacity).value;
    final int dx = cos(rad).round();
    final int dy = sin(rad).round();
    for (int depth = 0; depth <= 1; depth++) {
      final int x = (cx + (r - depth) * sin(rad)).round();
      final int y = (cy - (r - depth) * cos(rad)).round();
      buf.setPixel(x,      y,      argb);
      buf.setPixel(x + dx, y + dy, argb);
    }
  }

  /// Solid-fill rectangle. Out-of-bounds pixels are silently skipped.
  void _fillRect(PixelBuffer buf, int x, int y, int w, int h, Color color) {
    final int argb = color.value;
    for (int dy = 0; dy < h; dy++) {
      for (int dx = 0; dx < w; dx++) {
        buf.setPixel(x + dx, y + dy, argb);
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Time helpers (preserved from original)
  // ═════════════════════════════════════════════════════════════════════════

  DateTime _getTimeForZone(String timezone) {
    final DateTime base = _rawNow();
    if (timezone == 'local') return base;
    final DateTime utc = base.toUtc();
    if (timezone == 'UTC') return utc;
    final double? offset = _kTzOffsets[timezone];
    if (offset == null) return base;
    return utc.add(Duration(minutes: (offset * 60).round()));
  }

  DateTime _rawNow() => _container != null
      ? _container!.read(timeServiceProvider)
      : DateTime.now();

  String _buildHoursStr(DateTime now, ClockLayer layer) {
    if (layer.format == ClockFormat.h24) return _pad(now.hour);
    final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    return h.toString();
  }

  int _calcTimeWidth(LedFont font, String hours, String minutes,
      String seconds, bool hasAmPm, String ampm) {
    int w = font.textWidth(hours)
        + spacingBeforeColon
        + font.textWidth(':')
        + spacingAfterColon
        + font.textWidth(minutes);
    if (seconds.isNotEmpty) {
      w += spacingBeforeColon + font.textWidth(':') +
           spacingAfterColon  + font.textWidth(seconds);
    }
    if (hasAmPm) w += spacingGeneral + font.textWidth(ampm);
    return w;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────────────────
// UTC offset table (preserved)
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, double> _kTzOffsets = {
  'UTC':                  0,
  'Europe/London':        0,
  'Europe/Lisbon':        0,
  'Europe/Paris':         1,
  'Europe/Berlin':        1,
  'Europe/Rome':          1,
  'Europe/Amsterdam':     1,
  'Europe/Madrid':        1,
  'Europe/Warsaw':        1,
  'Europe/Athens':        2,
  'Europe/Bucharest':     2,
  'Europe/Helsinki':      2,
  'Europe/Istanbul':      3,
  'Europe/Moscow':        3,
  'Asia/Riyadh':          3,
  'Asia/Dubai':           4,
  'Asia/Baku':            4,
  'Asia/Kabul':           4.5,
  'Asia/Karachi':         5,
  'Asia/Tashkent':        5,
  'Asia/Kolkata':         5.5,
  'Asia/Colombo':         5.5,
  'Asia/Kathmandu':       5.75,
  'Asia/Dhaka':           6,
  'Asia/Almaty':          6,
  'Asia/Rangoon':         6.5,
  'Asia/Bangkok':         7,
  'Asia/Jakarta':         7,
  'Asia/Ho_Chi_Minh':     7,
  'Asia/Singapore':       8,
  'Asia/Shanghai':        8,
  'Asia/Taipei':          8,
  'Asia/Kuala_Lumpur':    8,
  'Asia/Manila':          8,
  'Asia/Seoul':           9,
  'Asia/Tokyo':           9,
  'Australia/Darwin':     9.5,
  'Australia/Brisbane':   10,
  'Australia/Adelaide':   9.5,
  'Australia/Sydney':     10,
  'Pacific/Auckland':     12,
  'Pacific/Fiji':         12,
  'Pacific/Honolulu':    -10,
  'America/Anchorage':   -9,
  'America/Los_Angeles': -8,
  'America/Denver':      -7,
  'America/Phoenix':     -7,
  'America/Chicago':     -6,
  'America/New_York':    -5,
  'America/Toronto':     -5,
  'America/Halifax':     -4,
  'America/Sao_Paulo':   -3,
  'America/Buenos_Aires':-3,
  'Atlantic/Azores':     -1,
};