import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../engine/scene/layer.dart';
import '../../../../engine/widgets/slot_machine_widget.dart';
import '../../../../services/slot_machine/slot_machine_service.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SlotMachineToolboxLeft — playable controls.
//
// Mirrors the structure of PomodoroToolboxLeft: a ConsumerWidget with no
// constructor params that reads the selected layer + service notifier from
// Riverpod. This is necessary because the SPIN button needs to observe the
// live service state to enable/disable itself and show JACKPOT feedback.
// ═════════════════════════════════════════════════════════════════════════════

class SlotMachineToolboxLeft extends ConsumerWidget {
  const SlotMachineToolboxLeft({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLayerProvider);
    if (selected is! SlotMachineLayer) return const SizedBox.shrink();
    final layer = selected;

    final state   = ref.watch(slotMachineServiceProvider);
    final service = ref.read(slotMachineServiceProvider.notifier);
    final n       = ref.read(sceneProvider.notifier);

    final bool spinning = state.phase == SlotMachinePhase.spinning;
    final bool showWin  = state.phase == SlotMachinePhase.showing && state.isWin;
    final bool canSpin  = state.canSpin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Status / stats card ──────────────────────────────────────────
        _StatusCard(
          headline: showWin
              ? 'JACKPOT!'
              : (spinning ? 'Spinning…' : 'Ready'),
          subline: 'Spins ${state.spinsCount}  ·  Wins ${state.winsCount}',
          accent: showWin ? layer.winFlashColor : null,
        ),
        const SizedBox(height: 10),

        // ── Transport (RESET / SPIN) ─────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TbTransportBtn(
              icon: Icons.restart_alt_rounded,
              onTap: () => service.reset(),
            ),
            const SizedBox(width: 10),
            TbTransportBtn(
              icon: Icons.casino_rounded,
              filled: canSpin,
              onTap: () => service.spin(layer),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Frame colour ─────────────────────────────────────────────────
        Row(children: [
          tbColorBtn(context, layer.frameColor,
              (c) => n.updateLayer(layer.copyWith(frameColor: c))),
          const SizedBox(width: 8),
          Text('Frame color',
              style: TextStyle(fontSize: 11, color: context.tTextMuted)),
        ]),
        const SizedBox(height: 8),

        // ── Win-flash colour ─────────────────────────────────────────────
        Row(children: [
          tbColorBtn(context, layer.winFlashColor,
              (c) => n.updateLayer(layer.copyWith(winFlashColor: c))),
          const SizedBox(width: 8),
          Text('Win flash color',
              style: TextStyle(fontSize: 11, color: context.tTextMuted)),
        ]),
        const SizedBox(height: 10),

        // ── Show-frame toggle ────────────────────────────────────────────
        TbToggleRow(
          label: 'Show frame',
          value: layer.showFrame,
          onChanged: (v) => n.updateLayer(layer.copyWith(showFrame: v)),
        ),
        const SizedBox(height: 6),

        // ── Jackpot odds ─────────────────────────────────────────────────
        const TbLabel('Jackpot odds (1 in N)'),
        const SizedBox(height: 2),
        TbStepper(
          label: 'Win every',
          value: layer.winOddsDenominator,
          unit: ' spins',
          min: 2,
          max: 99,
          onChanged: (v) =>
              n.updateLayer(layer.copyWith(winOddsDenominator: v)),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SlotMachineToolboxRight — animation timings + opacity.
//
// Plain StatelessWidget like the other "right" toolboxes — it doesn't need
// live service state, only the layer config.
// ═════════════════════════════════════════════════════════════════════════════

class SlotMachineToolboxRight extends StatelessWidget {
  final SlotMachineLayer layer;
  final SceneNotifier n;
  const SlotMachineToolboxRight(
      {super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TbLabel('Spin speed (ms / symbol)'),
          TbSpeedSlider(
            value: layer.spinSpeedMs.toDouble(),
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(spinSpeedMs: v.round())),
          ),
          const SizedBox(height: 10),

          TbStepper(
            label: 'Spin duration',
            value: (layer.spinDurationMs / 100).round(),
            unit: '00 ms',
            min: 4,
            max: 40,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(spinDurationMs: v * 100)),
          ),
          TbStepper(
            label: 'Reel stop delay',
            value: (layer.reelStopStaggerMs / 50).round(),
            unit: '0 ms',
            min: 2,
            max: 20,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(reelStopStaggerMs: v * 50)),
          ),
          TbStepper(
            label: 'Win flash',
            value: (layer.winFlashDurationMs / 100).round(),
            unit: '00 ms',
            min: 0,
            max: 60,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(winFlashDurationMs: v * 100)),
          ),
          const SizedBox(height: 12),

          const TbLabel('Opacity'),
          Slider(
            value: layer.opacity,
            min: 0,
            max: 1,
            onChanged: (v) => n.updateLayer(layer.copyWith(opacity: v)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatusCard — compact header in the left toolbox.
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final String headline;
  final String subline;
  final Color? accent;
  const _StatusCard({
    required this.headline,
    required this.subline,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final Color headlineColor = accent ?? context.tTextPrimary;
    final Color borderColor =
        accent?.withOpacity(0.55) ?? context.tPanelBorder.color;
    final Color bgColor =
        accent?.withOpacity(0.10) ?? Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.all(kRadiusSm),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: headlineColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subline,
            style: TextStyle(fontSize: 10, color: context.tTextMuted),
          ),
        ],
      ),
    );
  }
}