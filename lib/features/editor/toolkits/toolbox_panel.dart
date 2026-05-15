import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import 'toolbox/clock_toolbox.dart';
import 'toolbox/gif_toolbox.dart';
import 'toolbox/pomodoro_toolbox.dart';
import 'toolbox/spotify_toolbox.dart';
import 'toolbox/finance_toolbox.dart';
import 'toolbox/text_toolbox.dart';
import 'toolbox/slot_machine_toolbox.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry-points used by editor_page.dart
// ─────────────────────────────────────────────────────────────────────────────

class ToolboxLeftPanel extends ConsumerWidget {
  const ToolboxLeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();
    return _ToolboxLeft(layer: layer);
  }
}

class ToolboxRightPanel extends ConsumerWidget {
  const ToolboxRightPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();
    return _ToolboxRight(layer: layer);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT sub-panel
// ─────────────────────────────────────────────────────────────────────────────

class _ToolboxLeft extends ConsumerWidget {
  final Layer layer;
  const _ToolboxLeft({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(_leftTitle(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: switch (layer.type) {
              LayerType.text     => TextToolboxLeft(layer: layer as TextLayer, n: n),
              LayerType.clock    => ClockToolboxLeft(layer: layer as ClockLayer, n: n),
              LayerType.gif      => GifToolboxLeft(layer: layer as GifLayer, n: n),
              LayerType.spotify  => SpotifyToolboxLeft(layer: layer as SpotifyLayer),
              LayerType.finance => FinanceToolboxLeft(layer: layer as FinanceLayer, n: n),
              LayerType.pomodoro => const PomodoroToolboxLeft(),
              LayerType.slotMachine => const SlotMachineToolboxLeft(),
            },
          ),
        ),
      ],
    );
  }

  String _leftTitle(LayerType t) => switch (t) {
        LayerType.text     => 'TEXT STYLE',
        LayerType.clock    => 'CLOCK STYLE',
        LayerType.gif      => 'UPLOAD FILES',
        LayerType.spotify  => 'SPOTIFY SETTINGS',
        LayerType.finance => 'FINANCE SETTINGS',
        LayerType.pomodoro => 'POMODORO SETTINGS',
        LayerType.slotMachine => 'SLOT MACHINE SETTINGS',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT sub-panel
// ─────────────────────────────────────────────────────────────────────────────

class _ToolboxRight extends ConsumerWidget {
  final Layer layer;
  const _ToolboxRight({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(_rightTitle(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: switch (layer.type) {
              LayerType.text     => TextToolboxRight(layer: layer as TextLayer, n: n),
              LayerType.clock    => ClockToolboxRight(layer: layer as ClockLayer, n: n),
              LayerType.gif      => GifToolboxRight(layer: layer as GifLayer, n: n),
              LayerType.spotify  => SpotifyToolboxRight(layer: layer as SpotifyLayer, n: n),
              LayerType.finance => FinanceToolboxRight(layer: layer as FinanceLayer, n: n),
              LayerType.pomodoro => const PomodoroToolboxRight(),
              LayerType.slotMachine => SlotMachineToolboxRight(layer: layer as SlotMachineLayer, n: n),         
            },
          ),
        ),
      ],
    );
  }

  String _rightTitle(LayerType t) => switch (t) {
        LayerType.text     => 'ANIMATION EFFECT',
        LayerType.clock    => 'DISPLAY FORMAT',
        LayerType.gif      => 'MEDIA LAYOUT',
        LayerType.spotify  => 'SPOTIFY LAYOUT',
        LayerType.finance => 'FINANCE LAYOUT',
        LayerType.pomodoro => 'POMODORO LAYOUT',
        LayerType.slotMachine => 'ANIMATION TIMING',  
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared chrome
// ─────────────────────────────────────────────────────────────────────────────

class _SubHeader extends StatelessWidget {
  final String title;
  const _SubHeader(this.title);

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
            border: Border(bottom: context.tPanelBorder)),
        child: Text(title,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.12,
                color: context.tTextDim)),
      );
}

class _EmptyToolbox extends StatelessWidget {
  const _EmptyToolbox();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('Select a layer to edit',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.3))),
      );
}