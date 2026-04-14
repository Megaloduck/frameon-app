import 'package:flutter/material.dart';

import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart'; 

class ClockToolboxLeft extends StatelessWidget {
  final ClockLayer layer;
  final SceneNotifier n;
  const ClockToolboxLeft({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TbLabel('Element Colors'),
          const SizedBox(height: 8),
          _ColorRow(
              label: 'Hours',
              color: layer.hoursColor,
              onChanged: (c) =>
                  n.updateLayer(layer.copyWith(hoursColor: c))),
          const SizedBox(height: 6),
          _ColorRow(
              label: 'Minutes',
              color: layer.minutesColor,
              onChanged: (c) =>
                  n.updateLayer(layer.copyWith(minutesColor: c))),
          const SizedBox(height: 6),
          if (layer.showSeconds) ...[
            _ColorRow(
                label: 'Seconds',
                color: layer.secondsColor,
                onChanged: (c) =>
                    n.updateLayer(layer.copyWith(secondsColor: c))),
            const SizedBox(height: 6),
          ],
          if (layer.showDate) ...[
            _ColorRow(
                label: 'Date',
                color: layer.dateColor,
                onChanged: (c) =>
                    n.updateLayer(layer.copyWith(dateColor: c))),
            const SizedBox(height: 6),
          ],
          _ColorRow(
              label: 'Colon',
              color: layer.colonColor,
              onChanged: (c) =>
                  n.updateLayer(layer.copyWith(colonColor: c))),
        ],
      );
}

class ClockToolboxRight extends StatelessWidget {
  final ClockLayer layer;
  final SceneNotifier n;
  const ClockToolboxRight({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tbGreenDropdown<_TzOpt>(
              _TzOpt.values,
              _TzOpt.values.firstWhere((t) => t.name == layer.timezone,
                  orElse: () => _TzOpt.local),
              (v) => n.updateLayer(layer.copyWith(timezone: v.name))),
          const SizedBox(height: 10),
          const TbLabel('Alignment'),
          const SizedBox(height: 4),
          Row(
              children: ClockAlignment.values.map((v) {
            final active = v == layer.alignment;
            return Expanded(
              child: GestureDetector(
                onTap: () => n.updateLayer(layer.copyWith(alignment: v)),
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: active ? kGreen : kSurface,
                    border: Border.all(color: active ? kGreen : kBorder),
                    borderRadius: BorderRadius.horizontal(
                        left: v == ClockAlignment.left
                            ? const Radius.circular(6)
                            : Radius.zero,
                        right: v == ClockAlignment.right
                            ? const Radius.circular(6)
                            : Radius.zero),
                  ),
                  alignment: Alignment.center,
                  child: Text(v.name.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : kTextMuted)),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 10),
          TbToggleRow(
              label: '24-hour format',
              value: layer.format == ClockFormat.h24,
              onChanged: (v) => n.updateLayer(layer.copyWith(
                  format: v ? ClockFormat.h24 : ClockFormat.h12))),
          TbToggleRow(
              label: 'Show date',
              value: layer.showDate,
              onChanged: (v) => n.updateLayer(layer.copyWith(showDate: v))),
          TbToggleRow(
              label: 'Show seconds',
              value: layer.showSeconds,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(showSeconds: v))),
          TbToggleRow(
              label: 'Blink colon',
              value: layer.blinkColon,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(blinkColon: v))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

enum _TzOpt { local, utc, bangkok, tokyo, london, newYork }

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorRow(
      {required this.label, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: kTextMuted))),
          tbColorBtn(context, color, onChanged),
        ],
      );
}