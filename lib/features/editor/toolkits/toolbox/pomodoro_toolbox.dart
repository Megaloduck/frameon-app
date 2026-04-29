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
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: phaseColor.withOpacity(0.08),
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: phaseColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: timerState.isRunning
                      ? phaseColor
                      : context.tTextDim,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(phaseLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: phaseColor)),
              const Spacer(),
              Text('$mins:$secs',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: phaseColor,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          tbColorBtn(context, layer.focusColor,
              (c) => n.updateLayer(layer.copyWith(focusColor: c))),
          const SizedBox(width: 8),
          Text('Focus Session',
              style:
                  TextStyle(fontSize: 11, color: context.tTextMuted)),
          const Spacer(),
          TbDurationStepper(
            value: layer.focusDurationMinutes,
            unit: 'min',
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(focusDurationMinutes: v)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tbColorBtn(context, layer.breakColor,
              (c) => n.updateLayer(layer.copyWith(breakColor: c))),
          const SizedBox(width: 8),
          Text('Short break',
              style:
                  TextStyle(fontSize: 11, color: context.tTextMuted)),
          const Spacer(),
          TbDurationStepper(
            value: layer.shortBreakMinutes,
            unit: 'min',
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(shortBreakMinutes: v)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tbColorBtn(context, layer.longBreakColor,
              (c) => n.updateLayer(layer.copyWith(longBreakColor: c))),
          const SizedBox(width: 8),
          Text('Long break',
              style:
                  TextStyle(fontSize: 11, color: context.tTextMuted)),
          const Spacer(),
          TbDurationStepper(
            value: layer.longBreakMinutes,
            unit: 'min',
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(longBreakMinutes: v)),
          ),
        ]),
        const SizedBox(height: 8),
        TbStepper(
          label: 'Sessions before long break',
          value: layer.sessionsBeforeLongBreak,
          onChanged: (v) =>
              n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v)),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TbTransportBtn(
              icon: Icons.restart_alt_rounded,
              onTap: () => service.reset(layer)),
          const SizedBox(width: 8),
          TbTransportBtn(
            icon: timerState.isRunning
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            filled: true,
            onTap: () => service.togglePlayPause(layer),
          ),
          const SizedBox(width: 8),
          TbTransportBtn(
              icon: Icons.skip_next_rounded,
              onTap: () => service.skip(layer)),
        ]),
      ],
    );
  }
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
        const SizedBox(height: 8),
        const TbLabel('Custom FPS'),
        TbSpeedSlider(
            value: (1000 / layer.fps).clamp(10, 500),
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(fps: 1000 / v))),
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