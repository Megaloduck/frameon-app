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
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/zoom_provider.dart';
import '../widgets/layer_panel.dart' show LayerPanel;
import '../widgets/matrix_preview.dart' show MatrixPreview;
import '../widgets/output_panel.dart' show OutputPanel;
import '../widgets/toolbox_panel.dart' show ToolboxLeftPanel, ToolboxRightPanel;
import '../widgets/ui_primitives.dart';
import '../widgets/widget_palette.dart' show WidgetPalette;

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
                // ── Top bar ────────────────────────────────────────────────
                const _TopBar(),

                // ── Body ───────────────────────────────────────────────────
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left: preset slots column
                      const _PresetSlots(),

                      // Centre: preview + bottom strip
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Expanded(child: MatrixPreview()),
                              const SizedBox(height: 8),
                              SizedBox(height: 228, child: _BottomStrip()),
                            ],
                          ),
                        ),
                      ),
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
          // ── Logo ─────────────────────────────────────────────────────
          _Logo(),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 12),

          // ── Project name + dirty dot ──────────────────────────────────
          Text(
            scene.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kTextMuted),
          ),
          if (editor.isDirty) ...[
            const SizedBox(width: 5),
            Container(width: 5, height: 5, decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)),
          ],

          // ── File menu ─────────────────────────────────────────────────
          const SizedBox(width: 8),
          _FileMenuBtn(),

          const Spacer(),

          // ── Undo / Redo ───────────────────────────────────────────────
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

          // ── USB connection chip ───────────────────────────────────────
          _ConnectionChip(state: device),

          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 8),

          // ── Zoom label + buttons ──────────────────────────────────────
          const Text(
            'ZOOM',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.08, color: kTextMuted),
          ),
          const SizedBox(width: 6),
          ...kZoomLevels.map((z) => _ZoomBtn(level: z, active: z == zoom)),

          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: kBorder),
          const SizedBox(width: 8),

          // ── Theme toggle ──────────────────────────────────────────────
          _ThemeBtn(isDark: isDark),
        ],
      ),
    );
  }
}

// ── Logo ──────────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Green LED-matrix icon
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: kGreen,
              borderRadius: const BorderRadius.all(kRadiusSm),
            ),
            child: const Icon(Icons.grid_on_rounded, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 7),
          const Text(
            'FrameOn',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kTextPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ],
      );
}

// ── File menu ─────────────────────────────────────────────────────────────────

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to open: $e')));
      }
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final json  = ref.exportJson();
    final bytes = Uint8List.fromList(json.codeUnits);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save FrameOn project',
      fileName: '${ref.read(sceneProvider).name}.frameon',
      type: FileType.custom, allowedExtensions: ['frameon'], bytes: bytes,
    );
    if (result != null) {
      ref.read(editorControllerProvider.notifier).markSaved(result);
      ref.read(recentProjectsProvider.notifier).add(result);
    }
  }
}

// ── Top icon button ───────────────────────────────────────────────────────────

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

// ── Connection chip ───────────────────────────────────────────────────────────

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

// ── Zoom button ───────────────────────────────────────────────────────────────

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
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: active ? Colors.white : kTextMuted,
            ),
          ),
        ),
      );
}

// ── Theme button ──────────────────────────────────────────────────────────────

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
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 0.05, color: kTextMuted),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Preset slots — left vertical strip
// Slots 1-4 are matrix presets.  Settings icon at bottom.
// ─────────────────────────────────────────────────────────────────────────────

class _PresetSlots extends StatefulWidget {
  const _PresetSlots();
  @override
  State<_PresetSlots> createState() => _PresetSlotsState();
}

class _PresetSlotsState extends State<_PresetSlots> {
  int _active = 1;

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Column(
          children: [
            ...List.generate(4, (i) {
              final n = i + 1;
              final isActive = _active == n;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _PresetSlot(
                  label: '$n',
                  active: isActive,
                  onTap: () => setState(() => _active = n),
                ),
              );
            }),
            const Spacer(),
            // Settings cog
            GestureDetector(
              onTap: () {},
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.all(kRadiusSm),
                  border: Border.all(color: kBorder),
                ),
                child: const Icon(Icons.settings_rounded, size: 18, color: kTextMuted),
              ),
            ),
          ],
        ),
      );
}

class _PresetSlot extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PresetSlot({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
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
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom strip
// ─────────────────────────────────────────────────────────────────────────────

class _BottomStrip extends StatelessWidget {
  // Not const — Consumer children resolved at runtime.
  _BottomStrip();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 248,
            child: PanelShell(
              margin: const EdgeInsets.only(right: 8),
              child: const WidgetPalette(),
            ),
          ),
          SizedBox(
            width: 172,
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
            width: 192,
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
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyboard intents
// ─────────────────────────────────────────────────────────────────────────────

class _UndoIntent extends Intent { const _UndoIntent(); }
class _RedoIntent extends Intent { const _RedoIntent(); }
class _SaveIntent extends Intent { const _SaveIntent(); }