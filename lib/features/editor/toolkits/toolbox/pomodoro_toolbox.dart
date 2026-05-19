import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

class PomodoroToolboxLeft extends ConsumerWidget {
  const PomodoroToolboxLeft({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer      = ref.watch(selectedLayerProvider) as PomodoroLayer;
    final n          = ref.read(sceneProvider.notifier);
    final timerState = ref.watch(pomodoroServiceProvider);
    final service    = ref.read(pomodoroServiceProvider.notifier);

    final phaseLabel = switch (timerState.phase) {
      PomodoroState.focus      => 'Focus Session',
      PomodoroState.shortBreak => 'Short Break',
      PomodoroState.longBreak  => 'Long Break',
    };

    final phaseColor = switch (timerState.phase) {
      PomodoroState.focus      => layer.focusColor,
      PomodoroState.shortBreak => layer.breakColor,
      PomodoroState.longBreak  => layer.longBreakColor,
    };

    final mins = timerState.remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final secs = timerState.remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        // ── Status + transport ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: phaseColor.withOpacity(0.08),
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: phaseColor.withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              // Left — phase label + timer stacked
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: timerState.isRunning
                                ? phaseColor
                                : phaseColor.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          phaseLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: phaseColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$mins:$secs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: phaseColor,
                        fontFamily: 'monospace',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Right — transport buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TbTransportBtn(
                    icon: Icons.restart_alt_rounded,
                    onTap: () => service.reset(layer),
                  ),
                  const SizedBox(width: 6),
                  TbTransportBtn(
                    icon: timerState.isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    filled: true,
                    onTap: () => service.togglePlayPause(layer),
                  ),
                  const SizedBox(width: 6),
                  TbTransportBtn(
                    icon: Icons.skip_next_rounded,
                    onTap: () => service.skip(layer),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Timer durations ───────────────────────────────────────────────
        const TbLabel('Timer durations'),
        const SizedBox(height: 6),
        _DurationRow(
          color: layer.focusColor,
          label: 'Focus',
          value: layer.focusDurationMinutes,
          onColorChanged: (c) => n.updateLayer(layer.copyWith(focusColor: c)),
          onValueChanged: (v) => n.updateLayer(layer.copyWith(focusDurationMinutes: v)),
          context: context,
        ),
        const SizedBox(height: 6),
        _DurationRow(
          color: layer.breakColor,
          label: 'Short break',
          value: layer.shortBreakMinutes,
          onColorChanged: (c) => n.updateLayer(layer.copyWith(breakColor: c)),
          onValueChanged: (v) => n.updateLayer(layer.copyWith(shortBreakMinutes: v)),
          context: context,
        ),
        const SizedBox(height: 6),
        _DurationRow(
          color: layer.longBreakColor,
          label: 'Long break',
          value: layer.longBreakMinutes,
          onColorChanged: (c) => n.updateLayer(layer.copyWith(longBreakColor: c)),
          onValueChanged: (v) => n.updateLayer(layer.copyWith(longBreakMinutes: v)),
          context: context,
        ),

        const SizedBox(height: 10),

        // ── Sessions ──────────────────────────────────────────────────────
        TbStepper(
          label: 'Sessions before long break',
          value: layer.sessionsBeforeLongBreak,
          onChanged: (v) =>
              n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v)),
        ),
      ],
    );
  }
}

// ── Private helper — one duration row ────────────────────────────────────────

class _DurationRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<int> onValueChanged;
  final BuildContext context;

  const _DurationRow({
    required this.color,
    required this.label,
    required this.value,
    required this.onColorChanged,
    required this.onValueChanged,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) => Row(
        children: [
          tbColorBtn(context, color, onColorChanged),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: context.tTextMuted),
            ),
          ),
          TbDurationStepper(
            value: value,
            unit: 'min',
            onChanged: onValueChanged,
          ),
        ],
      );
}

class PomodoroToolboxRight extends ConsumerWidget {
  const PomodoroToolboxRight({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider) as PomodoroLayer;
    final n     = ref.read(sceneProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Layout dropdown with human-readable labels ──────────────────
        _PomodoroLayoutDropdown(
          current: layer.layout,
          onChanged: (v) => n.updateLayer(layer.copyWith(layout: v)),
        ),
        const SizedBox(height: 8),
        TbToggleRow(
            label: 'Show seconds',
            value: layer.showSeconds,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(showSeconds: v))),
        TbToggleRow(
            label: 'Show session',
            value: layer.showSession,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(showSession: v))),
        TbToggleRow(
            label: 'Blink colon',
            value: layer.blinkColor,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(blinkColor: v))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom layout dropdown  — maps enum values to readable names
// ─────────────────────────────────────────────────────────────────────────────

class _PomodoroLayoutDropdown extends StatelessWidget {
  final PomodoroLayout current;
  final ValueChanged<PomodoroLayout> onChanged;

  const _PomodoroLayoutDropdown({
    required this.current,
    required this.onChanged,
  });

  static String _label(PomodoroLayout v) => switch (v) {
        PomodoroLayout.splitLayout  => 'Split Layout',
        PomodoroLayout.minimalist   => 'Minimalist',
      };

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kGreen.withOpacity(0.1),
          border: Border.all(color: kGreen.withOpacity(0.5)),
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<PomodoroLayout>(
            value: current,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: kGreen),
            dropdownColor: context.tSurface,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: kGreen),
            items: PomodoroLayout.values
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(_label(v)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}