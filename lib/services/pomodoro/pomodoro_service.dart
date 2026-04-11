import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/layer.dart';
import '../../engine/widgets/pomodoro_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PomodoroService — owns the running countdown and phase transitions.
//
// The renderer reads currentPomodoroState via matrixRendererProvider.
// The UI reads pomodoroServiceProvider directly for transport controls.
// ─────────────────────────────────────────────────────────────────────────────

class PomodoroService extends Notifier<PomodoroTimerState> {
  Timer? _ticker;

  @override
  PomodoroTimerState build() => PomodoroTimerState.initial;

  // ── Transport ─────────────────────────────────────────────────────────────

  void start(PomodoroLayer layer) {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick(layer));
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(isRunning: false);
  }

  void togglePlayPause(PomodoroLayer layer) {
    if (state.isRunning) {
      pause();
    } else {
      start(layer);
    }
  }

  /// Reset to the beginning of the current phase.
  void reset(PomodoroLayer layer) {
    _ticker?.cancel();
    _ticker = null;
    state = PomodoroTimerState(
      remaining: _durationFor(state.phase, layer),
      phase: state.phase,
      session: state.session,
      isRunning: false,
    );
  }

  /// Skip to the next phase immediately.
  void skip(PomodoroLayer layer) {
    _ticker?.cancel();
    _ticker = null;
    _advance(layer, fromSkip: true);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _tick(PomodoroLayer layer) {
    final remaining = state.remaining - const Duration(seconds: 1);
    if (remaining <= Duration.zero) {
      _advance(layer);
    } else {
      state = state.copyWith(remaining: remaining);
    }
  }

  void _advance(PomodoroLayer layer, {bool fromSkip = false}) {
    _ticker?.cancel();
    _ticker = null;

    final PomodoroState nextPhase;
    int nextSession = state.session;

    switch (state.phase) {
      case PomodoroState.focus:
        // After focus: short break, unless it's time for a long break.
        if (nextSession % layer.sessionsBeforeLongBreak == 0) {
          nextPhase = PomodoroState.longBreak;
        } else {
          nextPhase = PomodoroState.shortBreak;
        }
      case PomodoroState.shortBreak:
        nextPhase = PomodoroState.focus;
        nextSession++;
      case PomodoroState.longBreak:
        nextPhase = PomodoroState.focus;
        nextSession++;
    }

    state = PomodoroTimerState(
      remaining: _durationFor(nextPhase, layer),
      phase: nextPhase,
      session: nextSession,
      isRunning: false, // always pause between phases — user starts manually
    );
  }

  Duration _durationFor(PomodoroState phase, PomodoroLayer layer) =>
      switch (phase) {
        PomodoroState.focus      => Duration(minutes: layer.focusDurationMinutes),
        PomodoroState.shortBreak => Duration(minutes: layer.shortBreakMinutes),
        PomodoroState.longBreak  => Duration(minutes: layer.longBreakMinutes),
      };

  @override
  void dispose() {
    _ticker?.cancel();
  }
}

final pomodoroServiceProvider =
    NotifierProvider<PomodoroService, PomodoroTimerState>(PomodoroService.new);