import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/device_api_service.dart';
import '../services/web_serial_service.dart';
import '../models/device_state.dart';

// ── Services ──────────────────────────────────────────────────────────────

final deviceApiServiceProvider = ChangeNotifierProvider<DeviceApiService>(
  (ref) => DeviceApiService(),
);

final webSerialServiceProvider = ChangeNotifierProvider<WebSerialService>(
  (ref) => WebSerialService(),
);

// ── Derived state ─────────────────────────────────────────────────────────

final deviceStateProvider = Provider<DeviceState>((ref) {
  return ref.watch(deviceApiServiceProvider).deviceState;
});

final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  return ref.watch(deviceStateProvider).connectionStatus;
});

final activeModeProvider = Provider<AppMode>((ref) {
  return ref.watch(deviceStateProvider).activeMode;
});
