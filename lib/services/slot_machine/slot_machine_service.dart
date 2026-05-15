import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/layer.dart';
import '../../engine/widgets/slot_machine_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SlotMachineService
// ─────────────────────────────────────────────────────────────────────────────
//
// Owns the runtime state of the *playable* slot machine — what symbols are
// currently locked in, whether a spin is in progress, and lifetime counters
// (spins, wins).
//
// The widget renders entirely from the state this service produces, so any
// UI surface (toolbox button, future hotkey, etc.) just needs to call
// [spin] or [reset] on this notifier.
//
// Mirrors the structure of [PomodoroService]: a single global notifier that
// the renderer also reads from in real time via [matrixRendererProvider]'s
// listener wiring.
// ─────────────────────────────────────────────────────────────────────────────

class SlotMachineService extends Notifier<SlotMachineRuntimeState> {
  Timer? _spinTimer;
  final Random _rng = Random();

  @override
  SlotMachineRuntimeState build() {
    ref.onDispose(() => _spinTimer?.cancel());
    return SlotMachineRuntimeState.initial;
  }

  /// Trigger a new spin. No-op if a spin is already in flight.
  ///
  /// The result is rolled *now* and stored in state immediately — the visual
  /// reel animation that follows is purely cosmetic. This matches how real
  /// slot machines work (the outcome is decided at the press, not at the
  /// stop).
  void spin(SlotMachineLayer layer) {
    if (!state.canSpin) return;

    final List<int> result = _roll(layer.winOddsDenominator);
    final bool isWin = result[0] == result[1] && result[1] == result[2];
    final int  nowMs = DateTime.now().millisecondsSinceEpoch;
    final int  cycleMs =
        layer.spinDurationMs + 2 * layer.reelStopStaggerMs;

    state = state.copyWith(
      phase:                  SlotMachinePhase.spinning,
      symbols:                result,
      spinStartedAtEpochMs:   nowMs,
      resultRevealedAtEpochMs: -1,
      spinsCount:             state.spinsCount + 1,
      isWin:                  isWin,
    );

    _spinTimer?.cancel();
    _spinTimer = Timer(Duration(milliseconds: cycleMs), () {
      state = state.copyWith(
        phase:                   SlotMachinePhase.showing,
        resultRevealedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        winsCount:               state.winsCount + (state.isWin ? 1 : 0),
      );
    });
  }

  /// Cancel any in-flight spin and clear all counters back to a fresh machine.
  void reset() {
    _spinTimer?.cancel();
    state = SlotMachineRuntimeState.initial;
  }

  // ── Rolling ──────────────────────────────────────────────────────────────

  /// Roll a result with the configured jackpot odds.
  ///
  /// Strategy:
  ///   • With probability 1/[winOdds], force a 3-of-a-kind on a randomly
  ///     chosen symbol.
  ///   • Otherwise roll each reel independently — and if that *happens* to
  ///     produce a 3-of-a-kind by chance, nudge reel 2 so the configured
  ///     win rate stays accurate.
  List<int> _roll(int winOdds) {
    final bool jackpot = winOdds > 1 && _rng.nextInt(winOdds) == 0;
    if (jackpot) {
      final int s = _rng.nextInt(kSlotMachineSymbolCount);
      return <int>[s, s, s];
    }
    final int r0 = _rng.nextInt(kSlotMachineSymbolCount);
    final int r1 = _rng.nextInt(kSlotMachineSymbolCount);
    int       r2 = _rng.nextInt(kSlotMachineSymbolCount);
    if (r0 == r1 && r1 == r2) {
      r2 = (r2 + 1) % kSlotMachineSymbolCount;
    }
    return <int>[r0, r1, r2];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final slotMachineServiceProvider =
    NotifierProvider<SlotMachineService, SlotMachineRuntimeState>(
        SlotMachineService.new);