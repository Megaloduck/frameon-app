import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/device/connection_state.dart';
import '../../../features/device/device_controller.dart';
import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import '../widgets/layer_panel.dart';
import '../widgets/matrix_preview.dart';
import '../widgets/toolbox_panel.dart';
import '../widgets/widget_pallete.dart';

class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
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
                  child: Column(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _Panel(
                          child: Column(
                            children: [
                              Padding(
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
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: MatrixPreview(),
                                ),
                              ),
                              const _MatrixInfo(),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 180, child: _Panel(child: const LayerPanel())),
                    ],
                  ),
                ),
                SizedBox(width: 220, child: _Panel(child: const ToolboxPanel())),
                SizedBox(width: 180, child: _Panel(child: const _OutputPanel())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceConnectionProvider);
    return Container(
      height: 48,
      color: Colors.white.withOpacity(.6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _SlotButton(label: 'F', color: Colors.blue.shade400),
          const SizedBox(width: 4),
          ...[1, 2, 3, 4].map((n) =>
              Padding(padding: const EdgeInsets.only(left: 4),
                  child: _SlotButton(label: '$n', color: Colors.green.shade500))),
          const Spacer(),
          // Connection status chip
          _ConnectionChip(state: device),
          const SizedBox(width: 12),
          Text('ZOOM',
              style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.4))),
          const SizedBox(width: 6),
          ...[4, 8, 10, 12, 14, 16].map((z) => _ZoomButton(zoom: z)),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.wb_sunny, size: 14),
            label: const Text('LIGHT', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends ConsumerWidget {
  final DeviceConnectionState state;
  const _ConnectionChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool connected = state.isConnected;
    final Color color = connected ? const Color(0xFF21C32C) : Colors.grey.shade400;
    final String label = connected
        ? state.portName ?? 'Connected'
        : state.status == DeviceConnectionStatus.connecting
            ? 'Connecting…'
            : 'Not connected';

    return GestureDetector(
      onTap: () => _showPortSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(.6)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  void _showPortSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _PortSelector(
        onConnect: (port) async {
          Navigator.pop(context);
          await ref.read(deviceConnectionProvider.notifier).connect(port);
        },
        onDisconnect: () async {
          Navigator.pop(context);
          await ref.read(deviceConnectionProvider.notifier).disconnect();
        },
        isConnected: state.isConnected,
        connectedPort: state.portName,
      ),
    );
  }
}

class _PortSelector extends ConsumerWidget {
  final Future<void> Function(String) onConnect;
  final Future<void> Function() onDisconnect;
  final bool isConnected;
  final String? connectedPort;

  const _PortSelector({
    required this.onConnect,
    required this.onDisconnect,
    required this.isConnected,
    required this.connectedPort,
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
            const Text('Select port',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            portsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (ports) => ports.isEmpty
                  ? const Text('No ports found')
                  : Column(
                      children: ports
                          .map((p) => ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.usb,
                                  color: p == connectedPort
                                      ? const Color(0xFF21C32C)
                                      : null,
                                ),
                                title: Text(p),
                                trailing: p == connectedPort
                                    ? const Icon(Icons.check,
                                        color: Color(0xFF21C32C))
                                    : null,
                                onTap: () => onConnect(p),
                              ))
                          .toList(),
                    ),
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

class _SlotButton extends StatelessWidget {
  final String label;
  final Color color;
  const _SlotButton({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text(label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
      );
}

class _ZoomButton extends StatelessWidget {
  final int zoom;
  const _ZoomButton({required this.zoom});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
            minimumSize: const Size(36, 28),
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: Text('${zoom}x', style: const TextStyle(fontSize: 11)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _MatrixInfo extends ConsumerWidget {
  const _MatrixInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene = ref.watch(sceneProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                  color: Color(0xFF21C32C), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('${scene.matrixWidth} × ${scene.matrixHeight} — RGB565',
              style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.4))),
        ],
      ),
    );
  }
}

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
            loading: () => const _StatRow(label: 'Frames', value: '—'),
            error: (_, __) => const _StatRow(label: 'Frames', value: 'err'),
            data: (t) => Column(children: [
              _StatRow(label: 'Frames',    value: '${t.frameCount}'),
              _StatRow(label: 'Bytes',     value: '${t.totalBytes}'),
              _StatRow(label: 'Duration',  value: '${t.totalDurationMs}ms'),
              _StatRow(label: 'Per frame',
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
              child: Text(_syncLabel(scene.layers.isNotEmpty
                  ? scene.layers.last.type : null),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

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