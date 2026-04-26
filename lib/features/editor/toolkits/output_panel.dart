import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/connection_state.dart';
import '../../device/device_controller.dart';
import '../../../shared/providers/providers.dart';
import 'ui_primitives.dart';

class OutputPanel extends ConsumerWidget {
  const OutputPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineAsync = ref.watch(timelineProvider);
    final device        = ref.watch(deviceConnectionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Output Rendering'),
        const Hairline(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 5),
                timelineAsync.when(
                  loading: () => const _StatsGrid(frames: '—', bytes: '—'),
                  error: (_, __) => const _StatsGrid(frames: '!', bytes: '!'),
                  data: (t) => _StatsGrid(
                    frames: '${t.frameCount}',
                    bytes:  _fmtBytes(t.totalBytes),
                  ),
                ),                const SizedBox(height: 12),
                const _GroupLabel('Device Status'),
                const SizedBox(height: 5),
                _DeviceStatus(state: device),
                if (device.isSending) ...[
                  const SizedBox(height: 10),
                  _SendProgress(progress: device.sendProgress),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // ── Action button pinned to bottom ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Hairline(margin: EdgeInsets.only(bottom: 10)),
              _SyncToDeviceButton(
                enabled: device.isConnected && !device.isSending,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtBytes(int b) =>
      b < 1024
          ? '${b} B'
          : b < 1048576
              ? '${(b / 1024).toStringAsFixed(1)} KB'
              : '${(b / 1048576).toStringAsFixed(2)} MB';
}

// ─────────────────────────────────────────────────────────────────────────────
// _SyncToDeviceButton
//
// Merges the old "Send to Device" and "Sync" buttons into one.
//
// Every press:
//   1. Invalidates [timelineProvider] — forces a fresh render with the latest
//      scene state (current time for clock, current track for Spotify, etc.).
//      This is a no-cost operation for static layers: the provider simply
//      re-runs and produces the same result from cache.
//   2. Calls sendToDevice() — streams the newly rendered timeline to the
//      hardware over serial.
//
// The label adapts to the selected layer so the button always feels relevant:
//   clock    → "Sync Time to Device"
//   pomodoro → "Sync Timer to Device"
//   spotify  → "Sync Track to Device"
//   gif      → "Sync & Re-encode"
//   other    → "Sync to Device"
// ─────────────────────────────────────────────────────────────────────────────

class _SyncToDeviceButton extends ConsumerWidget {
  final bool enabled;

  const _SyncToDeviceButton({required this.enabled});

  String get _label => 'Sync to Device';

  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.icon(
        onPressed: enabled
            ? () {
                // Force a fresh timeline render with the latest scene state
                // before sending — ensures clock, Spotify, Pomodoro, and GIF
                // layers always reflect the current real-world state.
                ref.invalidate(timelineProvider);
                ref.read(deviceConnectionProvider.notifier).sendToDevice();
              }
            : null,
        icon: const Icon(Icons.sync_rounded, size: 14),
        label: Text(
          _label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.04),
        ),
        style: FilledButton.styleFrom(
          backgroundColor:         kGreen,
          disabledBackgroundColor: context.tBorder,
          foregroundColor:         Colors.white,
          disabledForegroundColor: context.tTextDim,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(kRadiusMd)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatsGrid
// ─────────────────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final String frames, bytes;
  const _StatsGrid({required this.frames, required this.bytes});

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
        childAspectRatio: 2.3,
        children: [
          _StatChip(label: 'Frames', value: frames),
          _StatChip(label: 'Size',   value: bytes),
        ],
      );
}

class _StatChip extends StatelessWidget {
  final String label, value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.tSurfaceLow,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(color: context.tBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: context.tTextDim,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: context.tTextPrimary,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DeviceStatus
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceStatus extends StatelessWidget {
  final DeviceConnectionState state;
  const _DeviceStatus({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state.isConnected || state.isSending
        ? kGreen
        : state.status == DeviceConnectionStatus.error ||
                state.status == DeviceConnectionStatus.lost
            ? Colors.red.shade400
            : const Color(0xFF555555);

    final statusStr = switch (state.status) {
      DeviceConnectionStatus.connected    => 'Connected',
      DeviceConnectionStatus.connecting   => 'Connecting…',
      DeviceConnectionStatus.sending      => 'Sending…',
      DeviceConnectionStatus.scanning     => 'Scanning…',
      DeviceConnectionStatus.error        => 'Error',
      DeviceConnectionStatus.lost         => 'Lost',
      DeviceConnectionStatus.disconnected => 'Not connected',
    };

    return Row(children: [
      Container(
          width: 7,
          height: 7,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(statusStr,
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500)),
              if (state.portName != null)
                Text(state.portName!,
                    style: TextStyle(
                        fontSize: 10, color: context.tTextDim)),
              if (state.errorMessage != null)
                Text(state.errorMessage!,
                    style: TextStyle(
                        fontSize: 10, color: Colors.red.shade400)),
            ]),
      ),
    ]);
  }

  Color _statusColor(DeviceConnectionStatus status) => switch (status) {
        DeviceConnectionStatus.error => Colors.red.shade400,
        DeviceConnectionStatus.lost  => Colors.orange.shade400,
        _                            => const Color(0xFF555555),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// _SendProgress
// ─────────────────────────────────────────────────────────────────────────────

class _SendProgress extends StatelessWidget {
  final double progress;
  const _SendProgress({required this.progress});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Uploading',
                  style: TextStyle(
                      fontSize: 10, color: context.tTextMuted)),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                    fontSize: 10,
                    color: kGreen,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: const BorderRadius.all(kRadiusSm),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: context.tBorder,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(kGreen),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: context.tTextDim),
      );
}