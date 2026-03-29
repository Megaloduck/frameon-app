import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../renderer/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Runtime state for a running Pomodoro timer.
class PomodoroTimerState {
  final Duration remaining;
  final PomodoroState phase;
  final int session;
  final bool isRunning;

  const PomodoroTimerState({
    required this.remaining,
    required this.phase,
    required this.session,
    this.isRunning = false,
  });

  static const PomodoroTimerState initial = PomodoroTimerState(
    remaining: Duration(minutes: 25),
    phase: PomodoroState.focus,
    session: 1,
  );
}

/// Renders a [PomodoroLayer] into a [PixelBuffer] using the real 5×7 font.
class PomodoroWidget extends MatrixWidget<PomodoroLayer> {
  const PomodoroWidget();

  void renderWithState(
    PomodoroLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    PomodoroTimerState state,
  ) {
    final int secs = state.remaining.inSeconds;

    // Blink the entire display in the last 10 seconds.
    if (layer.blinkColor && secs <= 10) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    _renderTime(buffer, state.remaining, layer, elapsedMs);

    if (layer.showSession) {
      _renderSessionDots(buffer, state.session, layer.activeColor);
    }
  }

  @override
  void render(PomodoroLayer layer, PixelBuffer buffer, int elapsedMs) {
    _renderTime(
      buffer,
      Duration(minutes: layer.focusDurationMinutes),
      layer,
      elapsedMs,
    );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _renderTime(
    PixelBuffer buffer,
    Duration remaining,
    PomodoroLayer layer,
    int elapsedMs,
  ) {
    final String display = _format(remaining, layer.showSeconds, elapsedMs);
    final int y = (buffer.height - PixelFont.glyphHeight) ~/ 2 + layer.offset.dy.round();

    PixelFont.drawCentered(
      buffer: buffer,
      text: display,
      color: layer.activeColor,
      bufferWidth: buffer.width,
      y: y,
      opacity: layer.opacity,
    );
  }

  /// Format remaining time. The colon blinks at 1 Hz driven by [elapsedMs].
  String _format(Duration d, bool showSeconds, int elapsedMs) {
    final bool colonOn = (elapsedMs % 1000) < 500;
    final String sep = colonOn ? ':' : ' ';
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return showSeconds
        ? '${_pad(m)}$sep${_pad(s)}'
        : '${_pad(m)}$sep${_pad(00)}';
  }

  /// Draw small session-indicator dots in the bottom-right corner.
  void _renderSessionDots(PixelBuffer buffer, int session, Color color) {
    const int dotSize = 2;
    const int dotGap  = 1;
    final int totalW  = session * dotSize + (session - 1) * dotGap;
    int x = buffer.width - totalW - 2;
    final int y = buffer.height - dotSize - 1;

    for (int i = 0; i < session; i++) {
      buffer.fillRect(x, y, dotSize, dotSize, color);
      x += dotSize + dotGap;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}