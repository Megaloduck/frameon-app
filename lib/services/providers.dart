import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'device_api_service.dart';
import 'web_serial_service.dart';
import 'usb_api_service.dart';
import 'transport_service.dart';
import 'spotify_service.dart';
import '../models/device_state.dart';

// ── Core services ─────────────────────────────────────────────────────────
// All are app-lifetime singletons using plain ChangeNotifierProvider
// (NOT autoDispose). They are never rebuilt unless the ProviderScope is
// rebuilt (i.e. the whole app restarts).

final deviceApiServiceProvider = ChangeNotifierProvider<DeviceApiService>(
  (ref) => DeviceApiService(),
);

final webSerialServiceProvider = ChangeNotifierProvider<WebSerialService>(
  (ref) => WebSerialService(),
);

/// USB command API.
///
/// CRITICAL: Use ref.read (NOT ref.watch) to inject WebSerialService.
/// ref.watch would cause this provider to rebuild every time WebSerialService
/// calls notifyListeners() — which happens on every incoming serial line.
/// That would dispose and recreate UsbApiService mid-conversation, causing
/// "used after disposed" errors and lost response completers.
///
/// The UsbApiService adds its own ChangeNotifier listener to WebSerialService
/// internally, so it reacts to status changes without Riverpod recreating it.
final usbApiServiceProvider = ChangeNotifierProvider<UsbApiService>((ref) {
  final serial = ref.read(webSerialServiceProvider);
  final svc    = UsbApiService(serial);
  ref.onDispose(svc.dispose);
  return svc;
});

/// Unified transport — USB preferred, WiFi fallback.
///
/// Same pattern: ref.read to inject dependencies so this provider is never
/// accidentally recreated by dependency notifications.
final transportProvider = ChangeNotifierProvider<TransportService>((ref) {
  final usb  = ref.read(usbApiServiceProvider);
  final wifi = ref.read(deviceApiServiceProvider);
  final svc  = TransportService(usb, wifi);
  ref.onDispose(svc.dispose);
  return svc;
});

// ── Derived state ─────────────────────────────────────────────────────────
// These use ref.watch correctly — they are lightweight computed values,
// not service instances, so rebuilding them on change is fine and expected.

final deviceStateProvider = Provider<DeviceState>((ref) {
  return ref.watch(deviceApiServiceProvider).deviceState;
});

final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  return ref.watch(deviceStateProvider).connectionStatus;
});

final activeModeProvider = Provider<AppMode>((ref) {
  return ref.watch(deviceStateProvider).activeMode;
});

/// Which transport is currently active (usb / wifi / none).
/// Rebuilds widgets only when the transport enum value changes,
/// not on every serial line received.
final activeTransportProvider = Provider<ActiveTransport>((ref) {
  return ref.watch(transportProvider).transport;
});

// Feature providers are co-located with their screens:
// spotifyServiceProvider  → lib/services/spotify_service.dart
// clockConfigProvider     → lib/screens/clock/clock_screen.dart
// pomodoroConfigProvider  → lib/screens/pomodoro/pomodoro_screen.dart
// pomodoroTimerProvider   → lib/screens/pomodoro/pomodoro_screen.dart
// gifListProvider         → lib/screens/gif/gif_screen.dart
