import 'dart:math' as math;
import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PomodoroTimerState
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// PomodoroWidget
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a [PomodoroLayer] into a [PixelBuffer].
///
/// Two layouts are supported via [PomodoroLayout]:
///
///   splitLayout  — progress arc on left half, MM:SS + phase label on right.
///   minimalist   — small MM label top-left, large SS scale-2 below it,
///                  2-px vertical bar on far right, session dots top-right.
///
/// Export behaviour (isExport = true):
///   Both render paths return immediately without drawing anything.
///   The firmware renders the pomodoro live via overdrawPomodoro() on every
///   frame using millis() + the descriptor embedded in the packet header
///   (v1.8/v1.9). Baking pixels would cause double-rendering on the device.
class PomodoroWidget extends MatrixWidget<PomodoroLayer> {
  const PomodoroWidget();

  static LedFont get _font => LedFontLibrary.get(LedFontId.polymorph);

  // ── Public entry points ───────────────────────────────────────────────────

  /// Render with live timer state (live preview path).
  ///
  /// [isExport] must be true during device export so no pixels are baked —
  /// the firmware owns rendering via overdrawPomodoro().
  void renderWithState(
    PomodoroLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    PomodoroTimerState state, {
    bool isExport = false,
  }) {
    // Export path: leave buffer blank — firmware renders live.
    if (isExport) return;

    buffer.clear();

    if (layer.blinkColor && state.remaining.inSeconds <= 10) {
      if ((elapsedMs ~/ 500) % 2 == 1) return;
    }

    final activeLayer = layer.copyWith(currentState: state.phase);
    final totalSecs   = _totalSecsFor(state.phase, layer);
    final progress    = (totalSecs > 0)
        ? 1.0 - (state.remaining.inSeconds / totalSecs)
        : 1.0;

    switch (layer.layout) {
      case PomodoroLayout.splitLayout:
        _renderSplit(buffer, state.remaining, activeLayer, elapsedMs, progress);
      case PomodoroLayout.minimalist:
        _renderMinimalist(buffer, state.remaining, activeLayer, elapsedMs,
            progress, state.session);
    }
  }

  /// Render a static preview (no live state, 0 % progress).
  ///
  /// [isExport] must be true during device export so no pixels are baked.
  @override
  void render(PomodoroLayer layer, PixelBuffer buffer, int elapsedMs,
      {bool isExport = false}) {
    // Export path: leave buffer blank — firmware renders live.
    if (isExport) return;

    buffer.clear();

    switch (layer.layout) {
      case PomodoroLayout.splitLayout:
        _renderSplit(buffer,
            Duration(minutes: layer.focusDurationMinutes), layer, elapsedMs, 0.0);
      case PomodoroLayout.minimalist:
        _renderMinimalist(buffer,
            Duration(minutes: layer.focusDurationMinutes), layer, elapsedMs, 0.0, 1);
    }
  }

  // ── Layout: splitLayout ───────────────────────────────────────────────────
  //
  // Left 28 px  — hollow arc ring (outerR=11, innerR=7) showing elapsed %.
  // Right 36 px — MM:SS centred at x=46, dim phase label one line below.

  void _renderSplit(
    PixelBuffer buf,
    Duration d,
    PomodoroLayer layer,
    int elapsedMs,
    double progress,
  ) {
    final font  = _font;
    final color = layer.activeColor;

    // ── Arc (left half) ──────────────────────────────────────────────────
    const int cx = 14;
    const int cy = 16;
    const int outerR = 11;
    const int innerR = 7;   // hollow ring width = outerR - innerR = 4 px

    final double sweepEnd = -math.pi / 2 + progress * math.pi * 2;

    // Rasterise ring pixels — draw filled circle of outerR, punch out innerR.
    for (int py = cy - outerR; py <= cy + outerR; py++) {
      for (int px2 = cx - outerR; px2 <= cx + outerR; px2++) {
        final double dist = math.sqrt(
            ((px2 - cx) * (px2 - cx) + (py - cy) * (py - cy)).toDouble());
        if (dist < innerR || dist > outerR) continue;

        // Determine angle of this pixel (0 = top, clockwise).
        final double angle = math.atan2(py - cy, px2 - cx);

        // Is this pixel in the "filled" arc?
        final bool filled = _inArc(angle, -math.pi / 2, sweepEnd);

        final int br = filled ? color.red   : (color.red   * 0.2).round();
        final int bg = filled ? color.green : (color.green * 0.2).round();
        final int bb = filled ? color.blue  : (color.blue  * 0.2).round();
        buf.setPixel(px2, py,
            0xFF000000 | (br << 16) | (bg << 8) | bb);
      }
    }

    // ── Time (right half) ────────────────────────────────────────────────
    final bool colonOn = (elapsedMs % 1000) < 500;
    final String timeStr = _fmt(d, layer.showSeconds, colonOn);
    final int tw = font.textWidth(timeStr);
    // Right-area centre x = 28 + (64-28)/2 = 46; pin text there.
    final int tx = 46 - tw ~/ 2;
    final int ty = buf.height ~/ 2 - font.charHeight - 1; // upper half of right area

    font.draw(buffer: buf, text: timeStr, color: color, x: tx, y: ty);

    // ── Phase label (dim, below time) ────────────────────────────────────
    final String label = _phaseLabel(layer.currentState);
    final int lw = font.textWidth(label);
    final int lx = 46 - lw ~/ 2;
    final int ly = ty + font.lineHeight + 1;

    final Color dimColor = Color.fromARGB(
      color.alpha,
      (color.red   * 1.0).round(),
      (color.green * 1.0).round(),
      (color.blue  * 1.0).round(),
    );
    font.draw(buffer: buf, text: label, color: dimColor, x: lx, y: ly);
  }

  // ── Layout: minimalist ────────────────────────────────────────────────────
  //
  // Small MM label   — normal-scale, top-left at (2, 1).
  // Large SS         — scale-2 (14 px tall), at (2, 9) below the MM label.
  // Vertical bar     — 2 px wide at x=62..63, y=1..30, drains bottom-up.
  //                    Filled = activeColor; unfilled = 15 % dim.
  // Session dots     — 2×2 px, y=1..2, right→left from x=58, if showSession.
  //                    Active/done = activeColor; future = 18 % dim.

  void _renderMinimalist(
  PixelBuffer buf,
  Duration d,
  PomodoroLayer layer,
  int elapsedMs,
  double progress,
  int session,
) {
  final font  = _font;
  final color = layer.activeColor;

  // ── Small minutes (above big seconds) ────────────────────────────────
  final String mStr = _pad(d.inMinutes.remainder(60));
  font.draw(buffer: buf, text: mStr, color: color, x: 1, y: 9);

  // ── Large seconds (bottom left, 1px margin) ──────────────────────────
  final String sStr = _pad(d.inSeconds.remainder(60));
  // Position at bottom of screen: y = height - charHeight*2 (since scale-2) - 1px margin
  // Scale-2 makes each char 14px tall (7px * 2). For "00", that's 2 chars * 14px = 28px.
  final int secondsY = buf.height - 14 - 1; // 14 = 7px * 2, 1px margin at bottom
  _drawScale2(buf, sStr, 1, secondsY, color, font);

  // ── Vertical bar (far right, 2 px wide) ──────────────────────────────
  const int barX   = 61; // 1px right margin
  const int barTop = 1;  // 1px top margin
  const int barBot = 31; // 1px bottom margin
  final int barH   = barBot - barTop;
  final int filled = (progress * barH).round();

  for (int y = barTop; y < barBot; y++) {
    final bool on = y >= (barTop + barH - filled);
    final int br = on ? color.red   : (color.red   * 0.15).round();
    final int bg = on ? color.green : (color.green * 0.15).round();
    final int bb = on ? color.blue  : (color.blue  * 0.15).round();
    final int argb = 0xFF000000 | (br << 16) | (bg << 8) | bb;
    buf.setPixel(barX,     y, argb);
    buf.setPixel(barX + 1, y, argb);
  }

  // ── Session dots (top-right, above bar) ──────────────────────────────
  if (layer.showSession) {
    const int dotsY = 1;
    // up to 8 sessions; draw right-aligned just left of bar
    final int total = layer.sessionsBeforeLongBreak.clamp(1, 8);
    for (int i = 0; i < total; i++) {
      final int dotX = 58 - i * 4; // right→left
      final bool done = i < (session - 1);
      final bool active = i == (session - 1);
      final int br = (done || active) ? color.red   : (color.red   * 0.18).round();
      final int bg = (done || active) ? color.green : (color.green * 0.18).round();
      final int bb = (done || active) ? color.blue  : (color.blue  * 0.18).round();
      final int argb = 0xFF000000 | (br << 16) | (bg << 8) | bb;
      // 2×2 dot
      buf.setPixel(dotX,     dotsY,     argb);
      buf.setPixel(dotX + 1, dotsY,     argb);
      buf.setPixel(dotX,     dotsY + 1, argb);
      buf.setPixel(dotX + 1, dotsY + 1, argb);
    }
  }
}

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmt(Duration d, bool showSeconds, bool colonOn) {
    final String sep = colonOn ? ':' : ' ';
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    return showSeconds
        ? '${_pad(m)}$sep${_pad(s)}'
        : '${_pad(m)}$sep${_pad(0)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _phaseLabel(PomodoroState phase) => switch (phase) {
        PomodoroState.focus      => 'FOCUS',
        PomodoroState.shortBreak => 'BREAK',
        PomodoroState.longBreak  => 'REST',
      };

  int _totalSecsFor(PomodoroState phase, PomodoroLayer layer) => switch (phase) {
        PomodoroState.focus      => layer.focusDurationMinutes * 60,
        PomodoroState.shortBreak => layer.shortBreakMinutes    * 60,
        PomodoroState.longBreak  => layer.longBreakMinutes     * 60,
      };

  /// Returns true if [angle] lies in the arc drawn clockwise from [start]
  /// to [end], where all angles are in radians in [-π, π].
  bool _inArc(double angle, double start, double end) {
    double norm(double a) => (a - start) % (2 * math.pi);
    if (norm(end) < 0.001) return false; // 0 % — nothing filled
    return norm(angle) <= norm(end);
  }

  /// Draws [text] at (x, y) with each source pixel doubled to a 2×2 block.
  void _drawScale2(
    PixelBuffer buf,
    String text,
    int x,
    int y,
    Color color,
    LedFont font,
  ) {
    final int tw  = font.textWidth(text);
    final tmp     = PixelBuffer(width: tw, height: font.charHeight);
    font.draw(buffer: tmp, text: text, color: color, x: 0, y: 0);

    for (int row = 0; row < font.charHeight; row++) {
      for (int col = 0; col < tw; col++) {
        final int argb = tmp.getPixel(col, row);
        if ((argb >> 24) & 0xFF == 0) continue;
        buf.setPixel(x + col * 2,     y + row * 2,     argb);
        buf.setPixel(x + col * 2 + 1, y + row * 2,     argb);
        buf.setPixel(x + col * 2,     y + row * 2 + 1, argb);
        buf.setPixel(x + col * 2 + 1, y + row * 2 + 1, argb);
      }
    }
  }
}