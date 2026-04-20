import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart' show themeModeProvider;
import '../../../features/device/connection_state.dart';
import '../../../features/device/device_controller.dart';
import '../../../features/editor/presentation/controller.dart';
import '../../../services/storage/project_service.dart';
import '../../../shared/providers/preset_provider.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/zoom_provider.dart';
import '../toolkits/layer_panel.dart' show LayerPanel;
import '../toolkits/matrix_preview.dart' show MatrixPreview;
import '../toolkits/output_panel.dart' show OutputPanel;
import '../toolkits/toolbox_panel.dart' show ToolboxLeftPanel, ToolboxRightPanel;
import '../toolkits/ui_primitives.dart';
import '../toolkits/widget_palette.dart' show WidgetPalette;

// ─────────────────────────────────────────────────────────────────────────────
// EditorPage
// ─────────────────────────────────────────────────────────────────────────────

class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ): const _RedoIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ): const _RedoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS):
            const _SaveIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) => ref.read(editorControllerProvider.notifier).undo(),
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) => ref.read(editorControllerProvider.notifier).redo(),
          ),
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) => _saveFile(context, ref),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _PresetSlots(),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                                child: const MatrixPreview(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 228, child: _BottomStrip()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _saveFile(BuildContext context, WidgetRef ref) async {
    final json  = ref.exportJson();
    final bytes = Uint8List.fromList(json.codeUnits);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Frameon project',
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

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark  = ref.watch(themeModeProvider) == ThemeMode.dark;
    final zoom    = ref.watch(zoomProvider);
    final device  = ref.watch(deviceConnectionProvider);
    final editor  = ref.watch(editorControllerProvider);
    final scene   = ref.watch(sceneProvider);
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: surface,
        border: const Border(bottom: kPanelBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Logo(),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 12),
          Text(
            scene.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kTextMuted),
          ),
          if (editor.isDirty) ...[
            const SizedBox(width: 5),
            Container(width: 5, height: 5, decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)),
          ],
          const SizedBox(width: 8),
          _FileMenuBtn(),
          const Spacer(),
          _TopIconBtn(
            icon: Icons.undo_rounded,
            tooltip: 'Undo  ⌘Z',
            enabled: editor.canUndo,
            onTap: () => ref.read(editorControllerProvider.notifier).undo(),
          ),
          _TopIconBtn(
            icon: Icons.redo_rounded,
            tooltip: 'Redo  ⌘⇧Z',
            enabled: editor.canRedo,
            onTap: () => ref.read(editorControllerProvider.notifier).redo(),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 8),
          _ConnectionChip(state: device),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 8),
          const Text(
            'ZOOM',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.08, color: kTextMuted),
          ),
          const SizedBox(width: 6),
          ...kZoomLevels.map((z) => _ZoomBtn(level: z, active: z == zoom)),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 8),
          _ThemeBtn(isDark: isDark),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(color: kGreen, borderRadius: const BorderRadius.all(kRadiusSm)),
            child: const Icon(Icons.grid_on_rounded, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 7),
          const Text(
            'Frameon',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextPrimary, letterSpacing: -0.3),
          ),
        ],
      );
}

class _FileMenuBtn extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<String>(
        tooltip: 'File',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: kBorder),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_rounded, size: 13, color: kTextMuted),
              SizedBox(width: 4),
              Text('File', style: TextStyle(fontSize: 11, color: kTextMuted, fontWeight: FontWeight.w500)),
              Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: kTextMuted),
            ],
          ),
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(kRadiusMd)),
        itemBuilder: (_) => [
          _mi('open', 'Open project…', Icons.file_open_outlined),
          _mi('save', 'Save project…', Icons.save_outlined),
          const PopupMenuDivider(height: 1),
          _mi('new',  'New project',   Icons.add_rounded),
        ],
        onSelected: (v) {
          switch (v) {
            case 'open': _open(context, ref);
            case 'save': _save(context, ref);
            case 'new':  ref.read(sceneProvider.notifier).newScene();
          }
        },
      );

  PopupMenuItem<String> _mi(String val, String label, IconData icon) =>
      PopupMenuItem(
        value: val, height: 36,
        child: Row(children: [
          Icon(icon, size: 14, color: kTextMuted),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      );

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['frameon'], withData: true,
    );
    if (r == null || r.files.single.bytes == null) return;
    try {
      ref.importJson(String.fromCharCodes(r.files.single.bytes!));
      final path = r.files.single.path ?? r.files.single.name;
      ref.read(editorControllerProvider.notifier).markOpened(path);
      ref.read(recentProjectsProvider.notifier).add(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to open: $e')));
      }
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final json  = ref.exportJson();
    final bytes = Uint8List.fromList(json.codeUnits);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Frameon project',
      fileName: '${ref.read(sceneProvider).name}.frameon',
      type: FileType.custom, allowedExtensions: ['frameon'], bytes: bytes,
    );
    if (result != null) {
      ref.read(editorControllerProvider.notifier).markSaved(result);
      ref.read(recentProjectsProvider.notifier).add(result);
    }
  }
}

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;
  const _TopIconBtn({required this.icon, required this.tooltip, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: const BorderRadius.all(kRadiusSm),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 16, color: enabled ? kTextMuted : kTextDim),
          ),
        ),
      );
}

class _ConnectionChip extends ConsumerWidget {
  final DeviceConnectionState state;
  const _ConnectionChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = state.isConnected;
    final color = connected ? kGreen : kTextDim;
    final label = connected
        ? (state.portName ?? 'Connected')
        : state.status == DeviceConnectionStatus.connecting
            ? 'Connecting…'
            : 'No device';

    return GestureDetector(
      onTap: () => _showSheet(context, ref),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: connected ? kGreen.withOpacity(0.08) : Colors.transparent,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(color: connected ? kGreen.withOpacity(0.35) : kBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.usb_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _PortSheet(
        isConnected: state.isConnected,
        connectedPort: state.portName,
        onConnect: (p) async {
          Navigator.pop(context);
          await ref.read(deviceConnectionProvider.notifier).connect(p);
        },
        onDisconnect: () async {
          Navigator.pop(context);
          await ref.read(deviceConnectionProvider.notifier).disconnect();
        },
        onScan: () => ref.read(deviceConnectionProvider.notifier).scanPorts(),
      ),
    );
  }
}

class _PortSheet extends ConsumerWidget {
  final bool isConnected;
  final String? connectedPort;
  final Future<void> Function(String) onConnect;
  final Future<void> Function() onDisconnect;
  final Future<List<String>> Function() onScan;
  const _PortSheet({required this.isConnected, required this.connectedPort,
      required this.onConnect, required this.onDisconnect, required this.onScan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portsAsync = ref.watch(availablePortsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Serial port', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Scan'),
              onPressed: () async { await onScan(); ref.invalidate(availablePortsProvider); },
            ),
          ]),
          const SizedBox(height: 8),
          portsAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
            data: (ports) => ports.isEmpty
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No ports found.'))
                : Column(children: ports.map((p) => ListTile(
                      dense: true,
                      leading: Icon(Icons.usb_rounded, color: p == connectedPort ? kGreen : null),
                      title: Text(p),
                      trailing: p == connectedPort ? const Icon(Icons.check_rounded, color: kGreen) : null,
                      onTap: () => onConnect(p),
                    )).toList()),
          ),
          if (isConnected) ...[
            const Divider(),
            TextButton.icon(
              onPressed: onDisconnect,
              icon: const Icon(Icons.link_off_rounded, size: 14),
              label: const Text('Disconnect'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ZoomBtn extends ConsumerWidget {
  final int level;
  final bool active;
  const _ZoomBtn({required this.level, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: () => ref.read(zoomProvider.notifier).state = level,
        child: Container(
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? kGreen : Colors.transparent,
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: active ? kGreen : kBorder),
          ),
          child: Text(
            '${level}x',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? Colors.white : kTextMuted),
          ),
        ),
      );
}

class _ThemeBtn extends ConsumerWidget {
  final bool isDark;
  const _ThemeBtn({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: () => ref.read(themeModeProvider.notifier).state =
            isDark ? ThemeMode.light : ThemeMode.dark,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: kBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
              size: 13,
              color: isDark ? const Color(0xFF7B8CDE) : const Color(0xFFE6A817),
            ),
            const SizedBox(width: 5),
            Text(
              isDark ? 'DARK' : 'LIGHT',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.05, color: kTextMuted),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Preset slots — left vertical strip
//
// How it works:
//   • Tapping a slot saves the current scene into the slot we're LEAVING,
//     then loads the target slot's scene (or a blank if never saved).
//   • Long-pressing a slot shows a delete confirmation.
//   • The "+" button adds a new slot with a copy of the current scene as its
//     initial content so the user always starts from something useful.
//   • A dot indicator appears on any slot that has a saved (non-null) scene.
// ─────────────────────────────────────────────────────────────────────────────

class _PresetSlots extends ConsumerWidget {
  const _PresetSlots();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset  = ref.watch(presetProvider);
    final presetN = ref.read(presetProvider.notifier);
    final sceneN  = ref.read(sceneProvider.notifier);

    void switchTo(int label) {
      // 1. Save the current scene back into the slot we're leaving.
      final current = ref.read(sceneProvider);
      presetN.saveScene(current, slot: preset.activeSlot);

      // 2. Load the target slot's scene (blank if never saved).
      final target = presetN.switchTo(label);
      if (target != null) {
        sceneN.loadScene(target);
      } else {
        // First visit — start with a fresh blank scene.
        sceneN.newScene();
        // Immediately snapshot it into the slot so it persists.
        presetN.saveScene(ref.read(sceneProvider), slot: label);
      }

      // 3. Reset undo history — undo across preset boundaries is confusing.
      ref.read(editorControllerProvider.notifier).newProject();
    }

    void addSlot() {
      // Save current scene first.
      final current = ref.read(sceneProvider);
      presetN.saveScene(current, slot: preset.activeSlot);

      // Add slot with a blank scene.
      presetN.addSlot();
      sceneN.newScene();
      presetN.saveScene(ref.read(sceneProvider), slot: preset.activeSlot);
      ref.read(editorControllerProvider.notifier).newProject();
    }

    void confirmDelete(int label) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete preset?'),
          content: Text('Preset $label will be removed. This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed != true) return;
        final wasActive = preset.activeSlot == label;
        presetN.removeSlot(label);
        // If we deleted the active slot, load whichever slot is now active.
        if (wasActive) {
          final newActive = ref.read(presetProvider).activeSlot;
          final saved = ref.read(presetProvider).scenes[newActive];
          if (saved != null) {
            sceneN.loadScene(saved);
          } else {
            sceneN.newScene();
          }
          ref.read(editorControllerProvider.notifier).newProject();
        }
      });
    }

    return Container(
      width: 56,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...preset.slots.map((label) {
                    final isActive = preset.activeSlot == label;
                    final hasSaved = preset.scenes[label] != null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _PresetSlot(
                        label: '$label',
                        active: isActive,
                        hasSavedContent: hasSaved,
                        onTap: isActive ? null : () => switchTo(label),
                        onLongPress: preset.slots.length > 1
                            ? () => confirmDelete(label)
                            : null,
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _SlotIconBtn(
                      icon: Icons.add_rounded,
                      tooltip: 'Add preset',
                      onTap: addSlot,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, width: 32, color: kBorder, margin: const EdgeInsets.only(bottom: 6)),
          _SlotIconBtn(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slot widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PresetSlot extends StatelessWidget {
  final String label;
  final bool active;
  final bool hasSavedContent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _PresetSlot({
    required this.label,
    required this.active,
    required this.hasSavedContent,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: onLongPress != null ? 'Hold to delete' : '',
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: active ? kGreen : Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.all(kRadiusSm),
                  border: Border.all(color: active ? kGreen : kBorder, width: active ? 0 : 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : kTextMuted,
                  ),
                ),
              ),
              // Small dot in top-right corner when slot has saved content.
              if (hasSavedContent && !active)
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: kGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _SlotIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _SlotIconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.all(kRadiusSm),
              border: Border.all(color: kBorder),
            ),
            child: Icon(icon, size: 18, color: kTextMuted),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom strip
// ─────────────────────────────────────────────────────────────────────────────

class _BottomStrip extends StatelessWidget {
  _BottomStrip();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, left: 8, bottom: 8),
        child: Row(
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
              width: 188,
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
              width: 200,
              child: PanelShell(
                margin: const EdgeInsets.only(right: 8),
                child: const ToolboxRightPanel(),
              ),
            ),
            SizedBox(
              width: 188,
              child: PanelShell(
                margin: EdgeInsets.zero,
                child: const OutputPanel(),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyboard intents
// ─────────────────────────────────────────────────────────────────────────────

class _UndoIntent extends Intent { const _UndoIntent(); }
class _RedoIntent extends Intent { const _RedoIntent(); }
class _SaveIntent extends Intent { const _SaveIntent(); }