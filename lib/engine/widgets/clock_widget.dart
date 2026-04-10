import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../renderer/pixel_buffer.dart';
import '../renderer/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';
import '../../../shared/providers/time_service.dart';

class ClockWidget extends MatrixWidget<ClockLayer> {
  const ClockWidget();

  // ── Spacing Configuration ─────────────────────────────
  static const int spacingBeforeColon = 2;
  static const int spacingAfterColon  = 0;
  static const int spacingGeneral     = 1;
  static const int colonVisualOffset  = -1;

  /// Set once in main.dart so the stateless renderer can read the live time.
  static ProviderContainer? _container;

  static void init(ProviderContainer container) {
    _container = container;
  }

  @override
  void render(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final DateTime now = _getCurrentTime();

    // Blink colon without shifting layout
    final bool colonOn      = !layer.blinkColon || (elapsedMs % 1000) < 500;
    final String colonStr   = ':';
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

    // ── Vertical layout ──────────────────────────────────
    int totalHeight = PixelFont.glyphHeight;
    if (hasDate) totalHeight += PixelFont.glyphHeight + 2;

    final int startY   = (buffer.height - totalHeight) ~/ 2;
    int currentY       = startY;

    // ── Date row ─────────────────────────────────────────
    if (hasDate) {
      _drawAligned(
        buffer:      buffer,
        text:        dateStr,
        color:       layer.dateColor,
        alignment:   layer.alignment,
        offsetX:     layer.offset.dx.round(),
        y:           currentY,
        opacity:     layer.opacity,
        bufferWidth: buffer.width,
      );
      currentY += PixelFont.glyphHeight + 2;
    }

    // ── Compute total time-row width for alignment ────────
    final int totalWidth = _calcTimeWidth(hoursStr, minutesStr, secondsStr, hasAmPm, ampmStr);
    int cx = _startX(buffer, totalWidth, layer.alignment, layer.offset.dx.round());

    // ── Hours ─────────────────────────────────────────────
    _drawText(buffer, hoursStr, layer.hoursColor, cx, currentY, layer.opacity);
    cx += PixelFont.measureWidth(hoursStr);

    // ── Colon 1 ───────────────────────────────────────────
    cx += spacingBeforeColon;
    _drawText(buffer, colonStr, layer.colonColor, cx + colonVisualOffset, currentY, colonAlpha);
    cx += PixelFont.measureWidth(colonStr) + spacingAfterColon;

    // ── Minutes ───────────────────────────────────────────
    _drawText(buffer, minutesStr, layer.minutesColor, cx, currentY, layer.opacity);
    cx += PixelFont.measureWidth(minutesStr);

    // ── Seconds (optional) ────────────────────────────────
    if (hasSeconds) {
      cx += spacingBeforeColon;
      _drawText(buffer, colonStr, layer.colonColor, cx + colonVisualOffset, currentY, colonAlpha);
      cx += PixelFont.measureWidth(colonStr) + spacingAfterColon;
      _drawText(buffer, secondsStr, layer.secondsColor, cx, currentY, layer.opacity);
      cx += PixelFont.measureWidth(secondsStr);
    }

    // ── AM/PM (optional) ──────────────────────────────────
    if (hasAmPm) {
      cx += spacingGeneral;
      _drawText(buffer, ampmStr, layer.minutesColor, cx, currentY, layer.opacity);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  DateTime _getCurrentTime() {
    if (_container != null) {
      return _container!.read(timeServiceProvider);
    }
    return DateTime.now();
  }

  String _buildHoursStr(DateTime now, ClockLayer layer) {
    if (layer.format == ClockFormat.h24) return _pad(now.hour);
    final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    return h.toString();
  }

  int _calcTimeWidth(String hours, String minutes, String seconds,
      bool hasAmPm, String ampm) {
    int w = PixelFont.measureWidth(hours)
        + spacingBeforeColon
        + PixelFont.measureWidth(':')
        + spacingAfterColon
        + PixelFont.measureWidth(minutes);
    if (seconds.isNotEmpty) {
      w += spacingBeforeColon
          + PixelFont.measureWidth(':')
          + spacingAfterColon
          + PixelFont.measureWidth(seconds);
    }
    if (hasAmPm) w += spacingGeneral + PixelFont.measureWidth(ampm);
    return w;
  }

  int _startX(PixelBuffer buffer, int totalWidth, ClockAlignment alignment, int offsetX) {
    return switch (alignment) {
      ClockAlignment.left   => offsetX,
      ClockAlignment.center => ((buffer.width - totalWidth) ~/ 2) + offsetX,
      ClockAlignment.right  => buffer.width - totalWidth + offsetX,
    };
  }

  void _drawAligned({
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
        PixelFont.draw(buffer: buffer, text: text, color: color, x: offsetX, y: y, opacity: opacity);
      case ClockAlignment.center:
        PixelFont.drawCentered(buffer: buffer, text: text, color: color, bufferWidth: bufferWidth, y: y, opacity: opacity);
      case ClockAlignment.right:
        PixelFont.drawRight(buffer: buffer, text: text, color: color, rightEdge: bufferWidth + offsetX, y: y, opacity: opacity);
    }
  }

  void _drawText(PixelBuffer buffer, String text, Color color, int x, int y, double opacity) {
    if (text.isEmpty) return;
    PixelFont.draw(buffer: buffer, text: text, color: color, x: x, y: y, opacity: opacity);
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}