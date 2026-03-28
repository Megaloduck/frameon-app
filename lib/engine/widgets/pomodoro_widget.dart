import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';
import 'text_widget.dart';

/// Runtime state for a running Pomodoro timer.
/// Produced by the PomodoroService and passed into [PomodoroWidget.renderWithState].
class PomodoroTimerState {
  /// Remaining time on the current interval.
  final Duration remaining;
  final PomodoroState phase;
  /// Current session number (1-based).
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

/// Renders a [PomodoroLayer] into a [PixelBuffer].
///
/// Uses [PomodoroTimerState] from the running timer service for live
/// remaining-time display. Falls back to the layer's configured focus
/// duration when no state is provided (e.g. during export).
///
/// Color is determined by [PomodoroLayer.currentState] via [Layer.activeColor]:
/// - [PomodoroState.focus]      → [PomodoroLayer.focusColor] (yellow)
/// - [PomodoroState.shortBreak] → [PomodoroLayer.breakColor] (green)
/// - [PomodoroState.longBreak]  → [PomodoroLayer.breakColor]
///
/// Blink effect: when [PomodoroLayer.blinkColor] is true and the timer
/// is in its last 10 seconds, the color alternates at 1 Hz.
class PomodoroWidget extends MatrixWidget<PomodoroLayer> {
  const PomodoroWidget();

  static const _textWidget = TextWidget();

  /// Render with live timer state from the PomodoroService.
  void renderWithState(
    PomodoroLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    PomodoroTimerState timerState,
  ) {
    final Duration remaining = timerState.remaining;
    final int totalSeconds =
        remaining.inMinutes * 60 + remaining.inSeconds % 60;

    // Determine display color — blink in the final 10 seconds.
    Color color = layer.activeColor;
    if (layer.blinkColor && totalSeconds <= 10) {
      final bool hide = (elapsedMs ~/ 500) % 2 == 1;
      if (hide) return; // entire widget hidden on "off" tick
    }

    final String display = _formatTime(remaining, layer.showSeconds);
    _renderDisplay(buffer, display, color, layer, elapsedMs);

    if (layer.showSession) {
      _renderSession(buffer, timerState.session, color);
    }
  }

  @override
  void render(PomodoroLayer layer, PixelBuffer buffer, int elapsedMs) {
    // Fallback: render with the configured focus duration as a static display.
    final Duration remaining =
        Duration(minutes: layer.focusDurationMinutes);
    final String display = _formatTime(remaining, layer.showSeconds);
    _renderDisplay(buffer, display, layer.activeColor, layer, elapsedMs);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _renderDisplay(
    PixelBuffer buffer,
    String display,
    Color color,
    PomodoroLayer layer,
    int elapsedMs,
  ) {
    _textWidget.render(
      TextLayer(
        id: '',
        name: '',
        text: display,
        color: color,
        alignment: TextAlignment.center,
        offset: layer.offset,
      ),
      buffer,
      0, // no scroll/blink — handled above
    );
  }

  void _renderSession(PixelBuffer buffer, int session, Color color) {
    // Draw [session] small dots in the bottom-right corner.
    // Each dot is 2×2 px, spaced 3 px apart.
    const int dotSize = 2;
    const int dotSpacing = 3;
    final int totalW = session * dotSpacing - 1;
    int x = buffer.width - totalW - 2;
    final int y = buffer.height - dotSize - 2;

    for (int i = 0; i < session; i++) {
      buffer.fillRect(x, y, dotSize, dotSize, color);
      x += dotSpacing;
    }
  }

  String _formatTime(Duration d, bool showSeconds) {
    final int m = d.inMinutes;
    final int s = d.inSeconds % 60;
    return showSeconds
        ? '${_pad(m)}:${_pad(s)}'
        : '${_pad(m)}:00';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}