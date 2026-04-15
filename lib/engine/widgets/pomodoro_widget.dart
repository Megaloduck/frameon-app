import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
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

  PomodoroTimerState copyWith({
    Duration? remaining,
    PomodoroState? phase,
    int? session,
    bool? isRunning,
  }) =>
      PomodoroTimerState(
        remaining: remaining ?? this.remaining,
        phase: phase ?? this.phase,
        session: session ?? this.session,
        isRunning: isRunning ?? this.isRunning,
      );
}

/// Renders a [PomodoroLayer] into a [PixelBuffer].
///
/// Pomodoro always uses the polymorph font — digits are clean and legible
/// at the tight time-display sizes used here.
class PomodoroWidget extends MatrixWidget<PomodoroLayer> {
  const PomodoroWidget();

  // Pomodoro uses a fixed font regardless of layer settings.
  static LedFont get _font => LedFontLibrary.get(LedFontId.polymorph);

  void renderWithState(
    PomodoroLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    PomodoroTimerState state,
  ) {
    if (layer.blinkColor && state.remaining.inSeconds <= 10) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    final activeLayer = layer.copyWith(currentState: state.phase);
    _renderTime(buffer, state.remaining, activeLayer, elapsedMs);
    if (layer.showSession) {
      _renderSessionDots(buffer, state.session, activeLayer.activeColor);
    }
  }

  @override
  void render(PomodoroLayer layer, PixelBuffer buffer, int elapsedMs) {
    _renderTime(
        buffer, Duration(minutes: layer.focusDurationMinutes), layer, elapsedMs);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _renderTime(PixelBuffer buf, Duration d, PomodoroLayer layer, int t) {
    final font = _font;
    final String text = _format(d, layer.showSeconds, t);
    final int y = (buf.height - font.charHeight) ~/ 2 + layer.offset.dy.round();
    font.drawCentered(
      buffer:      buf,
      text:        text,
      color:       layer.activeColor,
      bufferWidth: buf.width,
      y:           y,
      opacity:     layer.opacity,
    );
  }

  String _format(Duration d, bool showSeconds, int elapsedMs) {
    final bool colonOn = (elapsedMs % 1000) < 500;
    final String sep   = colonOn ? ':' : ' ';
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return showSeconds ? '${_pad(m)}$sep${_pad(s)}' : '${_pad(m)}$sep${_pad(00)}';
  }

  void _renderSessionDots(PixelBuffer buf, int session, Color color) {
    const int ds = 2, dg = 1;
    int x = buf.width - (session * ds + (session - 1) * dg) - 2;
    final int y = buf.height - ds - 1;
    for (int i = 0; i < session; i++) {
      buf.fillRect(x, y, ds, ds, color);
      x += ds + dg;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}