import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';
import 'text_widget.dart';

/// Renders a [ClockLayer] into a [PixelBuffer].
///
/// Reads the current system time on every frame so the preview stays live.
/// The colon blinks at 1 Hz when [ClockLayer.blinkColon] is true.
///
/// Layout (single-line):
///   HH:MM          (24-h, seconds off)
///   HH:MM:SS       (24-h, seconds on)
///   H:MM AM/PM     (12-h, seconds off)
///
/// Date line (when [ClockLayer.showDate] is true) renders on the row above
/// the time using the same glyph approach.
class ClockWidget extends MatrixWidget<ClockLayer> {
  const ClockWidget();

  // Reuse the text drawing logic from TextWidget.
  static const _textWidget = TextWidget();

  @override
  void render(ClockLayer layer, PixelBuffer buffer, int elapsedMs) {
    final now = DateTime.now();

    // Colon visibility: hidden during the second half of every second.
    final bool colonOn = !layer.blinkColon || (now.millisecond < 500);
    final String sep = colonOn ? ':' : ' ';

    final String timeStr = _buildTimeString(now, layer, sep);

    // Render time — vertically centred; horizontally per alignment.
    final int yOffset = layer.showDate ? -4 : 0;
    _drawString(buffer, timeStr, layer.color, layer.alignment, 0, yOffset);

    // Render date above the time when requested.
    if (layer.showDate) {
      final String dateStr =
          '${_pad(now.day)}/${_pad(now.month)}/${now.year % 100}';
      _drawString(buffer, dateStr, layer.color, layer.alignment, 0, -12);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _buildTimeString(DateTime now, ClockLayer layer, String sep) {
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

  void _drawString(
    PixelBuffer buffer,
    String text,
    Color color,
    ClockAlignment alignment,
    int xOff,
    int yOff,
  ) {
    // Map ClockAlignment → TextAlignment for the shared drawing helper.
    final TextAlignment textAlign = switch (alignment) {
      ClockAlignment.left   => TextAlignment.left,
      ClockAlignment.center => TextAlignment.center,
      ClockAlignment.right  => TextAlignment.right,
    };

    _textWidget.render(
      TextLayer(
        id: '',
        name: '',
        text: text,
        color: color,
        alignment: textAlign,
        offset: Offset(xOff.toDouble(), yOff.toDouble()),
      ),
      buffer,
      0, // elapsedMs — clocks don't use animation effects internally
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}