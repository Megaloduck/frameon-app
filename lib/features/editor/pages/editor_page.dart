import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart' show themeModeProvider;
import '../../../engine/scene/layer.dart';
import '../../../features/device/connection_state.dart';
import '../../../features/device/device_controller.dart';
import '../../../features/editor/presentation/controller.dart';
import '../../../services/storage/project_service.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/zoom_provider.dart';
import '../widgets/layer_panel.dart';
import '../widgets/matrix_preview.dart';
import '../widgets/toolbox_panel.dart';
import '../widgets/widget_pallete.dart';

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
            onInvoke: (_) => _saveDialog(context, ref),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFFE8E6E0),
            body: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 160, child: _Panel(child: const WidgetPalette())),
                      Expanded(
                        child: Column(children: [
                          Expanded(
                            flex: 3,
                            child: _Panel(
                              child: Column(children: [
                                const _PreviewHeader(),
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: MatrixPreview(),
                                  ),
                                ),
                                const _MatrixInfo(),
                              ]),
                            ),
                          ),
                          SizedBox(height: 180, child: _Panel(child: const LayerPanel())),
                        ]),
                      ),
                      SizedBox(width: 220, child: _Panel(child: const ToolboxPanel())),
                      SizedBox(width: 180, child: _Panel(child: const _OutputPanel())),
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

  // Keyboard shortcut Ctrl+S delegates to the same _saveFile used in the menu.
  Future<void> _saveDialog(BuildContext context, WidgetRef ref) =>
      _TopBar._saveFileStatic(context, ref);
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyboard intents
// ─────────────────────────────────────────────────────────────────────────────

class _UndoIntent extends Intent { const _UndoIntent(); }
class _RedoIntent extends Intent { const _RedoIntent(); }
class _SaveIntent extends Intent { const _SaveIntent(); }

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device  = ref.watch(deviceConnectionProvider);
    final editor  = ref.watch(editorControllerProvider);
    final zoom    = ref.watch(zoomProvider);
    final scene   = ref.watch(sceneProvider);

    return Container(
      height: 48,
      color: Colors.white.withOpacity(.6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Scene slots
          _SlotBtn(label: 'F', color: Colors.blue.shade400),
          ...[1, 2, 3, 4].map((n) => Padding(
              padding: const EdgeInsets.only(left: 3),
              child: _SlotBtn(label: '$n', color: Colors.green.shade500))),

          const SizedBox(width: 12),

          // Title + dirty marker
          Text(
            '${scene.name}${editor.isDirty ? ' •' : ''}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black.withOpacity(.5)),
          ),

          const Spacer(),

          // Undo / Redo
          IconButton(
            icon: const Icon(Icons.undo, size: 18),
            tooltip: 'Undo (⌘Z)',
            onPressed: editor.canUndo
                ? () => ref.read(editorControllerProvider.notifier).undo()
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 18),
            tooltip: 'Redo (⌘⇧Z)',
            onPressed: editor.canRedo
                ? () => ref.read(editorControllerProvider.notifier).redo()
                : null,
          ),

          const SizedBox(width: 4),

          // Save / Load
          _MenuButton(
            icon: Icons.folder_open,
            tooltip: 'Open / Save',
            items: [
              PopupMenuItem(
                onTap: () => _openFile(context, ref),
                child: const Text('Open project…', style: TextStyle(fontSize: 13)),
              ),
              PopupMenuItem(
                onTap: () => _saveFile(context, ref),
                child: const Text('Save project…', style: TextStyle(fontSize: 13)),
              ),
              PopupMenuItem(
                onTap: () => ref.read(sceneProvider.notifier).newScene(),
                child: const Text('New project', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // Connection chip
          _ConnectionChip(state: device),

          const SizedBox(width: 10),

          // Zoom
          Text('ZOOM',
              style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.4))),
          const SizedBox(width: 4),
          ...kZoomLevels.map((z) => _ZoomBtn(zoom: z, active: z == zoom)),

          const SizedBox(width: 10),

          // Light / dark toggle
          IconButton(
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark
                  ? Icons.wb_sunny_outlined
                  : Icons.dark_mode_outlined,
              size: 18,
            ),
            tooltip: 'Toggle theme',
            onPressed: () {
              final current = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  current == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['frameon'],
      withData: true,
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

  Future<void> _saveFile(BuildContext context, WidgetRef ref) =>
      _saveFileStatic(context, ref);

  static Future<void> _saveFileStatic(BuildContext context, WidgetRef ref) async {
    final json = ref.exportJson();
    final bytes = json.codeUnits;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save FrameOn project',
      fileName: '${ref.read(sceneProvider).name}.frameon',
      type: FileType.custom,
      allowedExtensions: ['frameon'],
      bytes: Uint8List.fromList(bytes),
    );
    if (result != null) {
      ref.read(editorControllerProvider.notifier).markSaved(result);
      ref.read(recentProjectsProvider.notifier).add(result);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview header
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('MATRIX PREVIEW',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .08,
                  color: Colors.black.withOpacity(.45))),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Matrix info bar
// ─────────────────────────────────────────────────────────────────────────────

class _MatrixInfo extends ConsumerWidget {
  const _MatrixInfo();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene = ref.watch(sceneProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
                color: Color(0xFF21C32C), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('${scene.matrixWidth} × ${scene.matrixHeight} — RGB565',
            style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.4))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Output panel
// ─────────────────────────────────────────────────────────────────────────────

class _OutputPanel extends ConsumerWidget {
  const _OutputPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineAsync = ref.watch(timelineProvider);
    final scene         = ref.watch(sceneProvider);
    final device        = ref.watch(deviceConnectionProvider);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OUTPUT',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  letterSpacing: .08, color: Colors.black.withOpacity(.4))),
          const SizedBox(height: 12),
          timelineAsync.when(
            loading: () => const _Stat(label: 'Frames', value: '—'),
            error: (_, __) => const _Stat(label: 'Error', value: '!'),
            data: (t) => Column(children: [
              _Stat(label: 'Frames',   value: '${t.frameCount}'),
              _Stat(label: 'Bytes',    value: '${t.totalBytes}'),
              _Stat(label: 'Duration', value: '${t.totalDurationMs}ms'),
              _Stat(label: 'Per frame',
                  value: t.frameCount > 0
                      ? '${(t.totalDurationMs / t.frameCount).round()}ms'
                      : '—'),
            ]),
          ),
          if (device.isSending) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: device.sendProgress,
              color: const Color(0xFF21C32C),
              backgroundColor: Colors.grey.shade200,
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF21C32C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: device.isConnected && !device.isSending
                  ? () => ref.read(deviceConnectionProvider.notifier).sendToDevice()
                  : null,
              child: const Text('SEND TO DEVICE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF21C32C),
                side: const BorderSide(color: Color(0xFF21C32C)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {},
              child: Text(
                _syncLabel(scene.layers.isNotEmpty ? scene.layers.last.type : null),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _syncLabel(LayerType? t) => switch (t) {
        LayerType.clock    => 'SYNC TIME',
        LayerType.text     => 'SYNC TEXT',
        LayerType.pomodoro => 'SYNC TIME',
        _                  => 'SYNC',
      };
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(.5))),
            Text(value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection chip + port selector
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionChip extends ConsumerWidget {
  final DeviceConnectionState state;
  const _ConnectionChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool connected = state.isConnected;
    final Color color =
        connected ? const Color(0xFF21C32C) : Colors.grey.shade400;
    final String label = connected
        ? (state.portName ?? 'Connected')
        : state.status == DeviceConnectionStatus.connecting
            ? 'Connecting…'
            : 'No device';

    return GestureDetector(
      onTap: () => _showPortSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(.6)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Select port',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Scan'),
                  onPressed: () async {
                    await onScan();
                    ref.invalidate(availablePortsProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            portsAsync.when(
              loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )),
              error: (e, _) => Text('Error: $e'),
              data: (ports) => ports.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No serial ports found.'))
                  : Column(
                      children: ports
                          .map((p) => ListTile(
                                dense: true,
                                leading: Icon(Icons.usb,
                                    color: p == connectedPort
                                        ? const Color(0xFF21C32C)
                                        : null),
                                title: Text(p),
                                trailing: p == connectedPort
                                    ? const Icon(Icons.check,
                                        color: Color(0xFF21C32C))
                                    : null,
                                onTap: () => onConnect(p),
                              ))
                          .toList()),
            ),
            if (isConnected) ...[
              const Divider(),
              TextButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Disconnect'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small UI components
// ─────────────────────────────────────────────────────────────────────────────

class _SlotBtn extends StatelessWidget {
  final String label;
  final Color color;
  const _SlotBtn({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 30, height: 30,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      );
}

class _ZoomBtn extends ConsumerWidget {
  final int zoom;
  final bool active;
  const _ZoomBtn({required this.zoom, required this.active});
  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
        onPressed: () => ref.read(zoomProvider.notifier).state = zoom,
        style: TextButton.styleFrom(
          minimumSize: const Size(34, 28),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          foregroundColor: active
              ? const Color(0xFF21C32C)
              : Colors.black.withOpacity(.5),
          backgroundColor:
              active ? const Color(0xFF21C32C).withOpacity(.1) : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text('${zoom}x',
            style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      );
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<PopupMenuEntry> items;
  const _MenuButton(
      {required this.icon, required this.tooltip, required this.items});
  @override
  Widget build(BuildContext context) => PopupMenuButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 18, color: Colors.black.withOpacity(.55)),
        itemBuilder: (_) => items,
      );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}