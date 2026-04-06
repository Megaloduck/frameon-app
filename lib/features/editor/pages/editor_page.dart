import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart' show themeModeProvider;
import '../../../features/editor/presentation/controller.dart';
import '../../../services/storage/project_service.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/zoom_provider.dart';
// Use explicit `show` on every widget import so the analyser never has to
// guess which file a name comes from — this is what killed the build.
import '../widgets/layer_panel.dart' show LayerPanel;
import '../widgets/matrix_preview.dart' show MatrixPreview;
import '../widgets/output_panel.dart' show OutputPanel;
import '../widgets/toolbox_panel.dart' show ToolboxLeftPanel, ToolboxRightPanel;
import '../widgets/ui_primitives.dart';
import '../widgets/widget_palette.dart' show WidgetPalette;

class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ): const _RedoIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ): const _RedoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS):
            const _SaveIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) =>
                ref.read(editorControllerProvider.notifier).undo(),
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) =>
                ref.read(editorControllerProvider.notifier).redo(),
          ),
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) => _saveFile(context, ref),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SceneSlots(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // MatrixPreview is a ConsumerStatefulWidget —
                            // const Expanded(child: ...) is fine because
                            // Expanded itself is const; MatrixPreview() is not.
                            const Expanded(child: MatrixPreview()),
                            const SizedBox(height: 8),
                            // _BottomStrip has no const constructor on purpose.
                            SizedBox(height: 230, child: _BottomStrip()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Floating zoom + theme pill — top-right corner.
                const Positioned(top: 10, right: 10, child: _TopRightControls()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _saveFile(BuildContext context, WidgetRef ref) async {
    final json = ref.exportJson();
    final bytes = Uint8List.fromList(json.codeUnits);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save FrameOn project',
      fileName: '${ref.read(sceneProvider).name}.frameon',
      type: FileType.custom,
      allowedExtensions: ['frameon'],
      bytes: bytes,
    );
    if (result != null) {
      ref.read(editorControllerProvider.notifier).markSaved(result);
      ref.read(recentProjectsProvider.notifier).add(result);
    }
  }
}

// ── Scene slots ───────────────────────────────────────────────────────────────

class _SceneSlots extends StatelessWidget {
  const _SceneSlots();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        child: Column(
          children: [
            const _SlotButton(label: 'F', active: true),
            Container(
              height: 1,
              width: 30,
              color: kBorder,
              margin: const EdgeInsets.symmetric(vertical: 5),
            ),
            ...List.generate(
              4,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: _SlotButton(label: '${i + 1}'),
              ),
            ),
            const Spacer(),
            const _SlotIconButton(icon: Icons.settings_rounded),
          ],
        ),
      );
}

class _SlotButton extends StatelessWidget {
  final String label;
  final bool active;
  const _SlotButton({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? kGreen : Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(
            color: active ? kGreen : kBorder,
            width: active ? 0 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : kTextMuted,
          ),
        ),
      );
}

class _SlotIconButton extends StatelessWidget {
  final IconData icon;
  const _SlotIconButton({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(color: kBorder),
        ),
        child: Icon(icon, size: 18, color: kTextMuted),
      );
}

// ── Top-right controls ────────────────────────────────────────────────────────

class _TopRightControls extends ConsumerWidget {
  const _TopRightControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(zoomProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.all(kRadiusSm),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ZOOM',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
              color: kTextMuted,
            ),
          ),
          const SizedBox(width: 8),
          ...kZoomLevels.map((z) => _ZoomButton(level: z, active: z == zoom)),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: kBorder),
          const SizedBox(width: 8),
          _ThemeButton(isDark: isDark),
        ],
      ),
    );
  }
}

class _ZoomButton extends ConsumerWidget {
  final int level;
  final bool active;
  const _ZoomButton({required this.level, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: () => ref.read(zoomProvider.notifier).state = level,
        child: Container(
          margin: const EdgeInsets.only(right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? kGreen : Colors.transparent,
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: active ? kGreen : kBorder),
          ),
          child: Text(
            '${level}x',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : kTextMuted,
            ),
          ),
        ),
      );
}

/// Displays the CURRENT theme name with a sun/moon icon.
/// Tapping it flips to the opposite theme.
class _ThemeButton extends ConsumerWidget {
  final bool isDark;
  const _ThemeButton({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: () {
          ref.read(themeModeProvider.notifier).state =
              isDark ? ThemeMode.light : ThemeMode.dark;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                size: 13,
                color: isDark
                    ? const Color(0xFF7B8CDE) // periwinkle moon
                    : const Color(0xFFE6A817), // amber sun
              ),
              const SizedBox(width: 5),
              Text(
                isDark ? 'DARK' : 'LIGHT',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05,
                  color: kTextMuted,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Bottom strip ──────────────────────────────────────────────────────────────

class _BottomStrip extends StatelessWidget {
  // No const constructor — children include non-const Consumer widgets.
  // ignore: prefer_const_constructors_in_immutables
  _BottomStrip();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 250,
            child: PanelShell(
              margin: const EdgeInsets.only(right: 8),
              child: const WidgetPalette(),
            ),
          ),
          SizedBox(
            width: 175,
            child: PanelShell(
              margin: const EdgeInsets.only(right: 8),
              child: const LayerPanel(),
            ),
          ),
          Expanded(
            child: PanelShell(
              margin: const EdgeInsets.only(right: 8),
              child: const ToolboxLeftPanel(),
            ),
          ),
          SizedBox(
            width: 195,
            child: PanelShell(
              margin: const EdgeInsets.only(right: 8),
              child: const ToolboxRightPanel(),
            ),
          ),
          SizedBox(
            width: 190,
            child: PanelShell(
              margin: EdgeInsets.zero,
              child: const OutputPanel(),
            ),
          ),
        ],
      );
}

// ── Keyboard intents ──────────────────────────────────────────────────────────

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}