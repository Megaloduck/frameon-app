import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/timeline.dart';
import '../../features/export/frame_exporter.dart';
import '../../services/serial/serial_service.dart';
import '../../shared/providers/providers.dart';
import 'connection_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Serial service provider
// ─────────────────────────────────────────────────────────────────────────────

/// Swap [StubSerialService] for a real implementation when hardware is ready.
final serialServiceProvider = Provider<SerialService>(
  (_) => StubSerialService(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Available ports provider
// ─────────────────────────────────────────────────────────────────────────────

final availablePortsProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(serialServiceProvider);
  return service.availablePorts();
});

// ─────────────────────────────────────────────────────────────────────────────
// Device controller
// ─────────────────────────────────────────────────────────────────────────────

/// Manages the full device lifecycle: scan → connect → send → disconnect.
///
/// The UI reads [deviceConnectionProvider] for reactive state and calls
/// methods on the notifier to drive transitions.
class DeviceController extends Notifier<DeviceConnectionState> {
  @override
  DeviceConnectionState build() => const DeviceConnectionState();

  SerialService get _serial => ref.read(serialServiceProvider);
  FrameExporter get _exporter => const FrameExporter();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Refresh the list of available ports.
  Future<List<String>> scanPorts() async {
    state = state.copyWith(status: DeviceConnectionStatus.scanning);
    try {
      final ports = await _serial.availablePorts();
      state = state.copyWith(status: DeviceConnectionStatus.disconnected);
      ref.invalidate(availablePortsProvider);
      return ports;
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: e.toString(),
      );
      return [];
    }
  }

  /// Connect to [portName].
  Future<void> connect(String portName) async {
    state = state.copyWith(
      status: DeviceConnectionStatus.connecting,
      portName: portName,
    );
    try {
      await _serial.connect(portName);
      state = state.copyWith(status: DeviceConnectionStatus.connected);
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: 'Connect failed: $e',
      );
    }
  }

  /// Disconnect from the current port.
  Future<void> disconnect() async {
    await _serial.disconnect();
    state = const DeviceConnectionState();
  }

  /// Send the current [Timeline] to the connected device.
  ///
  /// Reads the latest rendered timeline from [timelineProvider].
  /// Shows progress via [DeviceConnectionState.sendProgress].
  Future<void> sendToDevice() async {
    if (!state.isConnected) return;

    final timelineAsync = ref.read(timelineProvider);
    final Timeline? timeline = timelineAsync.valueOrNull;
    if (timeline == null || timeline.frameCount == 0) return;

    state = state.copyWith(
      status: DeviceConnectionStatus.sending,
      sendProgress: 0,
    );

    try {
      final packet = _exporter.export(timeline);
      await _serial.send(
        packet,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
      );
      state = state.copyWith(
        status: DeviceConnectionStatus.connected,
        sendProgress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(
        status: DeviceConnectionStatus.error,
        errorMessage: 'Send failed: $e',
      );
    }
  }
}

final deviceConnectionProvider =
    NotifierProvider<DeviceController, DeviceConnectionState>(
  DeviceController.new,
);