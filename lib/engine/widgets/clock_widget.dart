import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../renderer/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Renders a [ClockLayer] into a [PixelBuffer] using the real 5×7 [PixelFont].
///
/// Colon blink strategy:
/// - In live preview [elapsedMs] advances with wall-clock time so the colon
///   blinks naturally.
/// - In frame export [elapsedMs] is synthetic (frameIdx × frameDurationMs);
///   the colon blinks on a per-frame basis consistent with the exported timing.
///   This fixes the previous bug where [elapsedMs] was hard-coded to 0.
class ClockWidget extends MatrixWidget<ClockLayer> {
  const ClockWidget();

  @override
  void render(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final now = DateTime.now();

    // Colon: visible for the first half of every second.
    // For live preview we use wall-clock milliseconds; during export we use
    // elapsedMs so exported frames are deterministic and consistent.
    final bool colonOn =
        !layer.blinkColon || (elapsedMs % 1000) < 500;
    final String sep = colonOn ? ':' : ' ';

    final String timeStr = _buildTimeStr(now, layer, sep);

    // Vertical layout: if showing date, shift time down slightly.
    final int totalH = layer.showDate
        ? PixelFont.glyphHeight * 2 + 2
        : PixelFont.glyphHeight;
    final int startY = (buffer.height - totalH) ~/ 2;

    if (layer.showDate) {
      final String dateStr =
          '${_pad(now.day)}.${_pad(now.month)}.${now.year % 100}';
      _draw(buffer, dateStr, layer, startY);
      _draw(buffer, timeStr, layer, startY + PixelFont.glyphHeight + 2);
    } else {
      _draw(buffer, timeStr, layer, startY);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildTimeStr(DateTime now, ClockLayer layer, String sep) {
    if (layer.format == ClockFormat.h24) {
      final String base = '${_pad(now.hour)}$sep${_pad(now.minute)}';
      return layer.showSeconds ? '$base$sep${_pad(now.second)}' : base;
    } else {
      final int h = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final String ampm = now.hour < 12 ? 'AM' : 'PM';
      final String base = '$h$sep${_pad(now.minute)}';
      return layer.showSeconds
          ? '$base$sep${_pad(now.second)} $ampm'
          : '$base $ampm';
    }
  }

  void _draw(PixelBuffer buffer, String text, ClockLayer layer, int y) {
    switch (layer.alignment) {
      case ClockAlignment.left:
        PixelFont.draw(
          buffer: buffer, text: text, color: layer.color,
          x: layer.offset.dx.round(), y: y, opacity: layer.opacity,
        );
      case ClockAlignment.center:
        PixelFont.drawCentered(
          buffer: buffer, text: text, color: layer.color,
          bufferWidth: buffer.width, y: y, opacity: layer.opacity,
        );
      case ClockAlignment.right:
        PixelFont.drawRight(
          buffer: buffer, text: text, color: layer.color,
          rightEdge: buffer.width + layer.offset.dx.round(),
          y: y, opacity: layer.opacity,
        );
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}