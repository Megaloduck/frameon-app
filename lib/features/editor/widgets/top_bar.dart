import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart' show themeModeProvider;
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/zoom_provider.dart';
import '../../../features/device/connection_state.dart';
import '../../../features/device/device_controller.dart';
import '../../../features/editor/presentation/controller.dart';
import '../../../services/storage/project_service.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top bar  (h = 44 px)
// ─────────────────────────────────────────────────────────────────────────────

class EditorTopBar extends ConsumerWidget {
  const EditorTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(editorControllerProvider);
    final scene  = ref.watch(sceneProvider);
    final device = ref.watch(deviceConnectionProvider);
    final zoom   = ref.watch(zoomProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(bottom: kPanelBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // ── Scene slots ────────────────────────────────────────────────
          _SceneSlots(),
          _VDivider(),

          // ── Project name + dirty flag ──────────────────────────────────
          _ProjectName(name: scene.name, isDirty: editor.isDirty),
          const Spacer(),

          // ── Undo / Redo ────────────────────────────────────────────────
          _TopBarIconBtn(
            icon: Icons.undo_rounded,
            tooltip: 'Undo  ⌘Z',
            enabled: editor.canUndo,
            onTap: () => ref.read(editorControllerProvider.notifier).undo(),
          ),
          _TopBarIconBtn(
            icon: Icons.redo_rounded,
            tooltip: 'Redo  ⌘⇧Z',
            enabled: editor.canRedo,
            onTap: () => ref.read(editorControllerProvider.notifier).redo(),
          ),
          _VDivider(),

          // ── File menu ─────────────────────────────────────────────────
          _FileMenuBtn(ref: ref),
          _VDivider(),

          // ── Connection ────────────────────────────────────────────────
          _ConnectionChip(state: device),
          _VDivider(),

          // ── Zoom ──────────────────────────────────────────────────────
          ...kZoomLevels.map(
            (z) => _ZoomBtn(level: z, active: z == zoom),
          ),
          _VDivider(),

          // ── Theme toggle ──────────────────────────────────────────────
          _TopBarIconBtn(
            icon: isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
            tooltip: 'Toggle theme',
            onTap: () {
              final cur = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  cur == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        ],
      ),
    );
  }
}

// ── Scene slots ───────────────────────────────────────────────────────────────

class _SceneSlots extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Slot(label: 'F', active: true),
          const SizedBox(width: 3),
          ...List.generate(4, (i) => Padding(
                padding: const EdgeInsets.only(left: 3),
                child: _Slot(label: '${i + 1}'),
              )),
        ],
      );
}

class _Slot extends StatelessWidget {
  final String label;
  final bool active;
  const _Slot({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? kGreen.withOpacity(0.15) : Colors.transparent,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(
            color: active ? kGreen.withOpacity(0.4) : kBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? kGreen : kTextMuted,
          ),
        ),
      );
}

// ── Project name ──────────────────────────────────────────────────────────────

class _ProjectName extends StatelessWidget {
  final String name;
  final bool isDirty;
  const _ProjectName({required this.name, required this.isDirty});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kTextMuted),
          ),
          if (isDirty) ...[
            const SizedBox(width: 4),
            Container(
              width: 5, height: 5,
              decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
            ),
          ],
        ],
      );
}

// ── Icon button ───────────────────────────────────────────────────────────────

class _TopBarIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;

  const _TopBarIconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: const BorderRadius.all(kRadiusSm),
          child: Container(
            width: 30, height: 30,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 17,
              color: enabled ? kTextMuted : kTextDim,
            ),
          ),
        ),
      );
}

// ── File menu ─────────────────────────────────────────────────────────────────

class _FileMenuBtn extends StatelessWidget {
  final WidgetRef ref;
  const _FileMenuBtn({required this.ref});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'File',
        icon: const Icon(Icons.folder_open_rounded, size: 17, color: kTextMuted),
        iconSize: 17,
        splashRadius: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(kRadiusMd)),
        itemBuilder: (_) => [
          _menuItem('open',  'Open project…',  Icons.file_open_outlined),
          _menuItem('save',  'Save project…',  Icons.save_outlined),
          const PopupMenuDivider(height: 1),
          _menuItem('new',   'New project',    Icons.add_rounded),
        ],
        onSelected: (v) {
          switch (v) {
            case 'open': _openFile(context, ref);
            case 'save': _saveFile(context, ref);
            case 'new':  ref.read(sceneProvider.notifier).newScene();
          }
        },
      );

  PopupMenuItem<String> _menuItem(String value, String label, IconData icon) =>
      PopupMenuItem(
        value: value,
        height: 36,
        child: Row(children: [
          Icon(icon, size: 15, color: kTextMuted),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      );

  Future<void> _openFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['frameon'], withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    try {
      final json = String.fromCharCodes(result.files.single.bytes!);
      ref.importJson(json);
      final path = result.files.single.path ?? result.files.single.name;
      ref.read(editorControllerProvider.notifier).markOpened(path);
      ref.read(recentProjectsProvider.notifier).add(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open: $e')),
        );
      }
    }
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

// ── Connection chip ───────────────────────────────────────────────────────────

class _ConnectionChip extends ConsumerWidget {
  final DeviceConnectionState state;
  const _ConnectionChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = state.isConnected;
    final color     = connected ? kGreen : kTextDim;
    final label     = connected
        ? (state.portName ?? 'Connected')
        : state.status == DeviceConnectionStatus.connecting
            ? 'Connecting…'
            : 'No device';

    return GestureDetector(
      onTap: () => _showPortSheet(context, ref),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: connected ? kGreen.withOpacity(0.08) : Colors.transparent,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(color: connected ? kGreen.withOpacity(0.3) : kBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  void _showPortSheet(BuildContext context, WidgetRef ref) {
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

  const _PortSheet({
    required this.isConnected,
    required this.connectedPort,
    required this.onConnect,
    required this.onDisconnect,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portsAsync = ref.watch(availablePortsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Select port', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Scan', style: TextStyle(fontSize: 13)),
              onPressed: () async {
                await onScan();
                ref.invalidate(availablePortsProvider);
              },
            ),
          ]),
          const SizedBox(height: 8),
          portsAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error:   (e, _) => Text('Error: $e'),
            data: (ports) => ports.isEmpty
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No serial ports found.'))
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
              icon: const Icon(Icons.link_off_rounded, size: 15),
              label: const Text('Disconnect', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Zoom buttons ──────────────────────────────────────────────────────────────

class _ZoomBtn extends ConsumerWidget {
  final int level;
  final bool active;
  const _ZoomBtn({required this.level, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: () => ref.read(zoomProvider.notifier).state = level,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: active ? kGreen.withOpacity(0.1) : Colors.transparent,
            borderRadius: const BorderRadius.all(kRadiusSm),
          ),
          alignment: Alignment.center,
          child: Text(
            '${level}×',
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? kGreen : kTextMuted,
            ),
          ),
        ),
      );
}

// ── Vertical divider ──────────────────────────────────────────────────────────

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1, height: 18, color: kBorder,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}