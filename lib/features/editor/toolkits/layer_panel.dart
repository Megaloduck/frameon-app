import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import '../presentation/controller.dart';
import 'ui_primitives.dart';

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
          decoration: BoxDecoration(
            border: Border(bottom: context.tPanelBorder),
          ),
          child: Row(
            children: [
              Text(
                'LAYERS',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.12, color: context.tTextDim,
                ),
              ),
              const SizedBox(width: 6),
              _CountBadge(count: scene.layers.length),
              const Spacer(),
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

  // Resolved in build() so we have access to context for the fallback colour.
  Color _resolveTypeColor(BuildContext context) =>
      kLayerTypeColors[widget.layer.type.name] ?? context.tTextMuted;

  IconData get _typeIcon =>
      kLayerTypeIcons[widget.layer.type.name] ?? Icons.layers_rounded;

  @override
  Widget build(BuildContext context) {
    final notifier   = ref.read(sceneProvider.notifier);
    final hidden     = !widget.layer.visible;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor  = _resolveTypeColor(context);

    final hoverBg = isDark
        ? Colors.white.withOpacity(0.04)
        : Colors.black.withOpacity(0.025);

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
                ? typeColor.withOpacity(0.10)
                : _hovered ? hoverBg : Colors.transparent,
            border: Border(
              left: widget.selected
                  ? BorderSide(color: typeColor, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Opacity(
            opacity: hidden ? 0.4 : 1.0,
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.drag_indicator_rounded, size: 14,
                        color: context.tTextDim),
                  ),
                ),
                LayerTypeBadge(icon: _typeIcon, color: typeColor, size: 22),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.layer.name,
                    style: TextStyle(fontSize: 12, color: context.tTextPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _RowIconBtn(
                  icon: hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  tooltip: hidden ? 'Show layer' : 'Hide layer',
                  color: hidden ? context.tTextDim : context.tTextMuted,
                  onTap: () => notifier.toggleVisibility(widget.layer.id),
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 100),
                  child: _RowIconBtn(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete layer',
                    color: Colors.red.shade400,
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

// ── Helpers ───────────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: context.tBorder,
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: context.tTextMuted),
        ),
      );
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;
  const _HeaderBtn({required this.icon, required this.tooltip,
      this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: const BorderRadius.all(kRadiusSm),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 15,
                color: enabled ? context.tTextMuted : context.tTextDim),
          ),
        ),
      );
}

class _RowIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  const _RowIconBtn({required this.icon, required this.tooltip,
      required this.onTap, required this.color});

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
  Widget build(BuildContext context) => Center(
        child: Text(
          'No layers yet — add one from the widget palette',
          style: TextStyle(fontSize: 11, color: context.tTextDim),
          textAlign: TextAlign.center,
        ),
      );
}