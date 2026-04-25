import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
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
    final selectedLayer = ref.watch(selectedLayerProvider);

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
                  loading: () => const _StatsGrid(
                      frames: '—', bytes: '—', duration: '—', perFrame: '—'),
                  error: (_, __) => const _StatsGrid(
                      frames: '!', bytes: '!', duration: '!', perFrame: '!'),
                  data: (t) => _StatsGrid(
                    frames:   '${t.frameCount}',
                    bytes:    _fmtBytes(t.totalBytes),
                    duration: '${t.totalDurationMs} ms',
                    perFrame: t.frameCount > 0
                        ? '${(t.totalDurationMs / t.frameCount).round()} ms'
                        : '—',
                  ),
                ),
                const SizedBox(height: 12),
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

        // ── Action buttons pinned to bottom ────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Hairline(margin: EdgeInsets.only(bottom: 10)),
              _SendButton(
                enabled: device.isConnected && !device.isSending,
                onTap:   () =>
                    ref.read(deviceConnectionProvider.notifier).sendToDevice(),
              ),
              const SizedBox(height: 6),
              _SyncButton(
                layerType: selectedLayer?.type,
                // Only enable Sync when connected and not currently sending.
                enabled: device.isConnected && !device.isSending,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtBytes(int b) =>
      b < 1024 ? '$b B' : '${(b / 1024).toStringAsFixed(1)} KB';
}

// ── Stats grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final String frames, bytes, duration, perFrame;
  const _StatsGrid({
    required this.frames,
    required this.bytes,
    required this.duration,
    required this.perFrame,
  });

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
        childAspectRatio: 2.3,
        children: [
          _StatChip(label: 'Frames',    value: frames),
          _StatChip(label: 'Size',      value: bytes),
          _StatChip(label: 'Duration',  value: duration),
          _StatChip(label: 'Per frame', value: perFrame),
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

// ── Device status ─────────────────────────────────────────────────────────────

class _DeviceStatus extends StatelessWidget {
  final DeviceConnectionState state;
  const _DeviceStatus({required this.state});

  @override
  Widget build(BuildContext context) {
    // FIX: the original used `state.isConnected` (only true for `connected`
    // status) to pick the dot colour. This made the dot go grey while sending,
    // which looks identical to "disconnected" and confuses users into thinking
    // the connection dropped when they hit Send.
    //
    // Now the dot stays green for both `connected` and `sending`.
    final bool alive = state.isConnected || state.isSending;
    final color = alive ? kGreen : _statusColor(state.status);

    final statusStr = switch (state.status) {
      DeviceConnectionStatus.connected    => 'Connected',
      DeviceConnectionStatus.connecting   => 'Connecting…',
      DeviceConnectionStatus.sending      => 'Sending…',
      DeviceConnectionStatus.scanning     => 'Scanning…',
      DeviceConnectionStatus.error        => 'Error',
      DeviceConnectionStatus.lost         => 'Connection lost',
      DeviceConnectionStatus.disconnected => 'No device',
    };

    return Row(children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusStr,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (state.portName != null)
              Text(
                state.portName!,
                style: TextStyle(fontSize: 10, color: context.tTextDim),
              ),
            if (state.errorMessage != null)
              Text(
                state.errorMessage!,
                style: TextStyle(fontSize: 10, color: Colors.red.shade400),
              ),
          ],
        ),
      ),
    ]);
  }

  /// Returns the appropriate colour for non-alive statuses.
  Color _statusColor(DeviceConnectionStatus status) => switch (status) {
        DeviceConnectionStatus.error => Colors.red.shade400,
        DeviceConnectionStatus.lost  => Colors.orange.shade400,
        _                            => const Color(0xFF555555),
      };
}

// ── Send progress ─────────────────────────────────────────────────────────────

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
              valueColor: const AlwaysStoppedAnimation<Color>(kGreen),
            ),
          ),
        ],
      );
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.upload_rounded, size: 14),
        label: const Text(
          'Send to Device',
          style: TextStyle(
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

/// Sync / re-encode button — label changes based on the selected layer type.
///
/// ## What it does
///
/// The timeline provider intentionally does NOT auto-update for clock ticks,
/// Spotify track changes, or Pomodoro state (those would cause a full ~1.2 MB
/// re-render every second). Instead the user explicitly triggers a re-export
/// via this button.
///
/// Pressing it:
///   1. Invalidates [timelineProvider], forcing a fresh render of the current
///      scene with up-to-date time / track / timer state.
///   2. If the device is connected, immediately sends the new timeline.
///
/// This is the correct way to "sync time", "refresh track", or "re-encode" a
/// GIF — the button was previously wired to `onPressed: () {}` (a no-op).
class _SyncButton extends ConsumerWidget {
  final LayerType? layerType;
  final bool enabled;
  const _SyncButton({required this.layerType, required this.enabled});

  String get _label => switch (layerType) {
        LayerType.clock    => 'Sync Time',
        LayerType.text     => 'Sync Text',
        LayerType.pomodoro => 'Sync Timer',
        LayerType.spotify  => 'Refresh Track',
        LayerType.gif      => 'Re-encode',
        _                  => 'Sync',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
        // FIX: was `onPressed: () {}` — completely non-functional.
        // Now invalidates the timeline (forcing a re-render with current state)
        // and sends to device if connected.
        onPressed: enabled
            ? () {
                // Force a fresh timeline render with the latest scene state
                // (current time for clock, current track for Spotify, etc.).
                ref.invalidate(timelineProvider);

                // Send the newly rendered timeline to the device.
                ref.read(deviceConnectionProvider.notifier).sendToDevice();
              }
            : null,
        icon: const Icon(Icons.sync_rounded, size: 13),
        label: Text(
          _label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor:         kGreen,
          disabledForegroundColor: const Color(0xFF555555),
          side: BorderSide(color: kGreen.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(vertical: 9),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(kRadiusMd)),
        ),
      );
}

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