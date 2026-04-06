import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import '../../../features/editor/presentation/controller.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayerPanel  (bottom-center strip, h = 190 px)
//
// Layout changes from original:
//   - Reorderable list with a drag handle (≡) on each row.
//   - Selected layer gets a 2 px green left border accent instead of a
//     translucent overlay — much more legible at small sizes.
//   - Row height reduced from ~40 px to 32 px — fits more layers.
//   - Visibility icon replaced with an eye that dims the entire row when
//     the layer is hidden.
//   - Delete button only appears on hover (via _LayerRowState).
//   - Layer count badge in the header.
// ─────────────────────────────────────────────────────────────────────────────

class LayerPanel extends ConsumerWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene      = ref.watch(sceneProvider);
    final selectedId = ref.watch(selectedLayerIdProvider);
    final notifier   = ref.read(sceneProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: kPanelBorder),
          ),
          child: Row(
            children: [
              const Text(
                'LAYERS',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.12, color: kTextDim,
                ),
              ),
              const SizedBox(width: 6),
              _CountBadge(count: scene.layers.length),
              const Spacer(),
              // Move selected up / down
              _HeaderBtn(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Move layer up',
                enabled: selectedId != null &&
                    scene.layers.indexWhere((l) => l.id == selectedId) > 0,
                onTap: () {
                  final i = scene.layers.indexWhere((l) => l.id == selectedId);
                  notifier.reorderLayer(i, i - 1);
                },
              ),
              _HeaderBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Move layer down',
                enabled: selectedId != null &&
                    scene.layers.indexWhere((l) => l.id == selectedId) <
                        scene.layers.length - 1,
                onTap: () {
                  final i = scene.layers.indexWhere((l) => l.id == selectedId);
                  notifier.reorderLayer(i, i + 1);
                },
              ),
            ],
          ),
        ),

        // ── List ───────────────────────────────────────────────────────
        Expanded(
          child: scene.layers.isEmpty
              ? const _EmptyState()
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  onReorder: notifier.reorderLayer,
                  itemCount: scene.layers.length,
                  itemBuilder: (_, index) {
                    final layer = scene.layers[index];
                    return _LayerRow(
                      key:      ValueKey(layer.id),
                      layer:    layer,
                      index:    index,
                      selected: layer.id == selectedId,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Layer row ─────────────────────────────────────────────────────────────────

class _LayerRow extends ConsumerStatefulWidget {
  final Layer layer;
  final int   index;
  final bool  selected;

  const _LayerRow({
    required super.key,
    required this.layer,
    required this.index,
    required this.selected,
  });

  @override
  ConsumerState<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends ConsumerState<_LayerRow> {
  bool _hovered = false;

  Color get _typeColor => kLayerTypeColors[widget.layer.type.name] ?? kTextMuted;
  IconData get _typeIcon => kLayerTypeIcons[widget.layer.type.name] ?? Icons.layers_rounded;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(sceneProvider.notifier);
    final hidden   = !widget.layer.visible;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => notifier.selectLayer(widget.layer.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 32,
          decoration: BoxDecoration(
            color: widget.selected
                ? _typeColor.withOpacity(0.06)
                : _hovered
                    ? Colors.black.withOpacity(0.025)
                    : Colors.transparent,
            border: Border(
              left: widget.selected
                  ? BorderSide(color: _typeColor, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Opacity(
            opacity: hidden ? 0.4 : 1.0,
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: widget.index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.drag_indicator_rounded, size: 14, color: kTextDim),
                  ),
                ),

                // Type badge
                LayerTypeBadge(icon: _typeIcon, color: _typeColor, size: 22),
                const SizedBox(width: 7),

                // Name
                Expanded(
                  child: Text(
                    widget.layer.name,
                    style: const TextStyle(fontSize: 12, color: kTextPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Visibility toggle — always visible
                _RowIconBtn(
                  icon: hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  tooltip: hidden ? 'Show layer' : 'Hide layer',
                  color: hidden ? kTextDim : kTextMuted,
                  onTap: () => notifier.toggleVisibility(widget.layer.id),
                ),

                // Delete — only on hover
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 100),
                  child: _RowIconBtn(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete layer',
                    color: Colors.red.shade300,
                    onTap: () {
                      ref.read(editorControllerProvider.notifier).snapshot();
                      notifier.removeLayer(widget.layer.id);
                    },
                  ),
                ),

                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: kBorder,
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        child: Text(
          '$count',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: kTextMuted),
        ),
      );
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;
  const _HeaderBtn({required this.icon, required this.tooltip, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: const BorderRadius.all(kRadiusSm),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 15, color: enabled ? kTextMuted : kTextDim),
          ),
        ),
      );
}

class _RowIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  const _RowIconBtn({required this.icon, required this.tooltip, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(kRadiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text(
          'No layers yet — add one from the widget palette',
          style: TextStyle(fontSize: 11, color: kTextDim),
          textAlign: TextAlign.center,
        ),
      );
}