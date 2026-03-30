import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';

class LayerPanel extends ConsumerWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene = ref.watch(sceneProvider);
    final selectedId = ref.watch(selectedLayerIdProvider);

    return Container(
      color: Colors.white.withOpacity(.35),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LAYERS (${scene.layers.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .08,
              color: Colors.black.withOpacity(.45),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: scene.layers.isEmpty
                ? const Center(child: Text('No layers yet'))
                : ListView.separated(
                    itemBuilder: (_, index) {
                      final layer = scene.layers[index];
                      return _LayerTile(
                        layer: layer,
                        selected: selectedId == layer.id,
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemCount: scene.layers.length,
                  ),
          ),
        ],
      ),
    );
  }
}

class _LayerTile extends ConsumerWidget {
  final Layer layer;
  final bool selected;

  const _LayerTile({required this.layer, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sceneProvider.notifier);

    return Material(
      color: selected ? Colors.black.withOpacity(.08) : Colors.white.withOpacity(.7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => notifier.selectLayer(layer.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(_iconFor(layer.type), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  layer.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                onPressed: () => notifier.toggleVisibility(layer.id),
                icon: Icon(layer.visible ? Icons.visibility : Icons.visibility_off),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Delete layer',
                onPressed: () => notifier.removeLayer(layer.id),
                icon: const Icon(Icons.delete_outline),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(LayerType type) {
    switch (type) {
      case LayerType.text:
        return Icons.text_fields;
      case LayerType.clock:
        return Icons.schedule;
      case LayerType.gif:
        return Icons.gif_box;
      case LayerType.spotify:
        return Icons.music_note;
      case LayerType.pomodoro:
        return Icons.timer;
    }
  }
}