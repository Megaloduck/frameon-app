import 'package:flutter/material.dart';

import '../../../../engine/renderer/font_organizer.dart';
import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

class TextToolboxLeft extends StatelessWidget {
  final TextLayer layer;
  final SceneNotifier n;
  const TextToolboxLeft({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            tbColorBtn(context, layer.color,
                (c) => n.updateLayer(layer.copyWith(color: c))),
            const SizedBox(width: 8),
            const Text('Text Color',
                style: TextStyle(fontSize: 11, color: kTextMuted)),
          ]),
          const SizedBox(height: 10),
          const TbLabel('Font Style'),
          const SizedBox(height: 4),
          TbDropdown<LedFontId>(
            values: LedFontId.values,
            current: layer.fontId,
            onChange: (v) => n.updateLayer(layer.copyWith(fontId: v)),
            labelFor: (v) => LedFontLibrary.get(v).name,
          ),
          const SizedBox(height: 8),
          const TbLabel('Display Text'),
          const SizedBox(height: 4),
          TbTextField(
              value: layer.text,
              onSubmitted: (v) => n.updateLayer(layer.copyWith(text: v))),
        ],
      );
}

class TextToolboxRight extends StatelessWidget {
  final TextLayer layer;
  final SceneNotifier n;
  const TextToolboxRight({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tbGreenDropdown<AnimationEffect>(AnimationEffect.values, layer.effect,
              (v) => n.updateLayer(layer.copyWith(effect: v))),
          const SizedBox(height: 12),
          if (layer.effect != AnimationEffect.none) ...[
            const TbLabel('Speed'),
            TbSpeedSlider(
                value: layer.effectSpeedMs.toDouble(),
                onChanged: (v) =>
                    n.updateLayer(layer.copyWith(effectSpeedMs: v.round()))),
            const SizedBox(height: 8),
          ],
          const TbLabel('Alignment'),
          const SizedBox(height: 4),
          TbSegAlign(
              current: layer.alignment,
              onChange: (v) => n.updateLayer(layer.copyWith(alignment: v))),
          const SizedBox(height: 12),
          const TbLabel('Opacity'),
          Slider(
              value: layer.opacity,
              min: 0,
              max: 1,
              onChanged: (v) => n.updateLayer(layer.copyWith(opacity: v))),
        ],
      );
}