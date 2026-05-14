import 'package:flutter/material.dart';

import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SlotMachineToolboxLeft — frame + win-flash colours, show-frame toggle,
//                         jackpot odds.
// ─────────────────────────────────────────────────────────────────────────────

class SlotMachineToolboxLeft extends StatelessWidget {
  final SlotMachineLayer layer;
  final SceneNotifier n;
  const SlotMachineToolboxLeft(
      {super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Frame colour ──────────────────────────────────────────────
          Row(children: [
            tbColorBtn(context, layer.frameColor,
                (c) => n.updateLayer(layer.copyWith(frameColor: c))),
            const SizedBox(width: 8),
            Text('Frame color',
                style: TextStyle(fontSize: 11, color: context.tTextMuted)),
          ]),
          const SizedBox(height: 8),

          // ── Win-flash colour ──────────────────────────────────────────
          Row(children: [
            tbColorBtn(context, layer.winFlashColor,
                (c) => n.updateLayer(layer.copyWith(winFlashColor: c))),
            const SizedBox(width: 8),
            Text('Win flash color',
                style: TextStyle(fontSize: 11, color: context.tTextMuted)),
          ]),
          const SizedBox(height: 10),

          // ── Show frame toggle ─────────────────────────────────────────
          TbToggleRow(
            label: 'Show frame',
            value: layer.showFrame,
            onChanged: (v) => n.updateLayer(layer.copyWith(showFrame: v)),
          ),
          const SizedBox(height: 6),

          // ── Jackpot odds ──────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// SlotMachineToolboxRight — animation timings + opacity.
// ─────────────────────────────────────────────────────────────────────────────

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
            label: 'Idle pause',
            value: (layer.idleMs / 100).round(),
            unit: '00 ms',
            min: 0,
            max: 50,
            onChanged: (v) => n.updateLayer(layer.copyWith(idleMs: v * 100)),
          ),
          TbStepper(
            label: 'Result hold',
            value: (layer.resultHoldMs / 100).round(),
            unit: '00 ms',
            min: 5,
            max: 50,
            onChanged: (v) =>
                n.updateLayer(layer.copyWith(resultHoldMs: v * 100)),
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