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

  // ── Spacing (pixels) ──────────────────────────────────────────────────────
  static const int spacingBeforeColon = 2;
  static const int spacingAfterColon  = 0;
  static const int spacingGeneral     = 1;
  static const int colonVisualOffset  = -1;

  static ProviderContainer? _container;
  static void init(ProviderContainer container) => _container = container;

  @override
  void render(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(layer.fontId);
    final DateTime now = _getTimeForZone(layer.timezone);

    final bool colonOn    = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final double colonAlpha = colonOn ? layer.opacity : 0.0;

    final hoursStr   = _buildHoursStr(now, layer);
    final minutesStr = _pad(now.minute);
    final secondsStr = layer.showSeconds ? _pad(now.second) : '';
    final dateStr    = layer.showDate
        ? '${_pad(now.day)}.${_pad(now.month)}.${now.year % 100}'
        : '';
    final ampmStr = layer.format != ClockFormat.h24
        ? (now.hour < 12 ? 'AM' : 'PM')
        : '';

    final bool hasDate    = dateStr.isNotEmpty;
    final bool hasSeconds = secondsStr.isNotEmpty;
    final bool hasAmPm    = ampmStr.isNotEmpty;

    // ── Vertical layout ───────────────────────────────────────────────────
    int totalHeight = font.charHeight;
    if (hasDate) totalHeight += font.charHeight + 2;

    final int startY = (buffer.height - totalHeight) ~/ 2;
    int currentY     = startY;

    // ── Date row ──────────────────────────────────────────────────────────
    if (hasDate) {
      _drawAligned(font,
        buffer:      buffer,
        text:        dateStr,
        color:       layer.dateColor,
        alignment:   layer.alignment,
        offsetX:     layer.offset.dx.round(),
        y:           currentY,
        opacity:     layer.opacity,
        bufferWidth: buffer.width,
      );
      currentY += font.charHeight + 2;
    }

    // ── Time row width for alignment ──────────────────────────────────────
    final int totalWidth = _calcTimeWidth(font, hoursStr, minutesStr, secondsStr, hasAmPm, ampmStr);
    int cx = _startX(buffer, totalWidth, layer.alignment, layer.offset.dx.round());

    // ── Hours ─────────────────────────────────────────────────────────────
    font.draw(buffer: buffer, text: hoursStr, color: layer.hoursColor,
        x: cx, y: currentY, opacity: layer.opacity);
    cx += font.textWidth(hoursStr);

    // ── Colon 1 ───────────────────────────────────────────────────────────
    cx += spacingBeforeColon;
    font.draw(buffer: buffer, text: ':', color: layer.colonColor,
        x: cx + colonVisualOffset, y: currentY, opacity: colonAlpha);
    cx += font.textWidth(':') + spacingAfterColon;

    // ── Minutes ───────────────────────────────────────────────────────────
    font.draw(buffer: buffer, text: minutesStr, color: layer.minutesColor,
        x: cx, y: currentY, opacity: layer.opacity);
    cx += font.textWidth(minutesStr);

    // ── Seconds (optional) ────────────────────────────────────────────────
    if (hasSeconds) {
      cx += spacingBeforeColon;
      font.draw(buffer: buffer, text: ':', color: layer.colonColor,
          x: cx + colonVisualOffset, y: currentY, opacity: colonAlpha);
      cx += font.textWidth(':') + spacingAfterColon;
      font.draw(buffer: buffer, text: secondsStr, color: layer.secondsColor,
          x: cx, y: currentY, opacity: layer.opacity);
      cx += font.textWidth(secondsStr);
    }

    // ── AM/PM (optional) ──────────────────────────────────────────────────
    if (hasAmPm) {
      cx += spacingGeneral;
      font.draw(buffer: buffer, text: ampmStr, color: layer.minutesColor,
          x: cx, y: currentY, opacity: layer.opacity);
    }
  }

  // ── Time resolution ───────────────────────────────────────────────────────

  /// Return the current wall-clock time adjusted to [timezone].
  ///
  /// Strategy:
  ///   - 'local'  → device local time (no conversion needed)
  ///   - 'UTC'    → UTC
  ///   - anything else → look up in the offset table and apply offset to UTC
  ///
  /// Note: DST is not modelled — offsets use the standard (winter) offset for
  /// the zone. For a real app you would pull in the `timezone` package; for an
  /// LED panel this is accurate enough and keeps dependencies minimal.
  DateTime _getTimeForZone(String timezone) {
    final DateTime base = _rawNow();

    if (timezone == 'local') return base;

    final DateTime utc = base.toUtc();
    if (timezone == 'UTC') return utc;

    final double? offset = _kTzOffsets[timezone];
    if (offset == null) return base; // unknown id → fall back to local

    final int offsetMinutes = (offset * 60).round();
    return utc.add(Duration(minutes: offsetMinutes));
  }

  DateTime _rawNow() =>
      _container != null ? _container!.read(timeServiceProvider) : DateTime.now();

  // ── Helpers ───────────────────────────────────────────────────────────────

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
      w += spacingBeforeColon
          + font.textWidth(':')
          + spacingAfterColon
          + font.textWidth(seconds);
    }
    if (hasAmPm) w += spacingGeneral + font.textWidth(ampm);
    return w;
  }

  int _startX(PixelBuffer buffer, int totalWidth, ClockAlignment alignment, int offsetX) =>
      switch (alignment) {
        ClockAlignment.left   => offsetX,
        ClockAlignment.center => ((buffer.width - totalWidth) ~/ 2) + offsetX,
        ClockAlignment.right  => buffer.width - totalWidth + offsetX,
      };

  void _drawAligned(LedFont font, {
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
        font.draw(buffer: buffer, text: text, color: color,
            x: offsetX, y: y, opacity: opacity);
      case ClockAlignment.center:
        font.drawCentered(buffer: buffer, text: text, color: color,
            bufferWidth: bufferWidth, y: y, opacity: opacity);
      case ClockAlignment.right:
        font.drawRight(buffer: buffer, text: text, color: color,
            rightEdge: bufferWidth + offsetX, y: y, opacity: opacity);
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────────────────
// UTC offset table — standard (non-DST) offsets in fractional hours.
//
// These match the _kTimezones list in clock_toolbox.dart.
// DST transitions are NOT modelled; offset is the standard offset.
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