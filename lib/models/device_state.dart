import 'package:flutter/foundation.dart';

enum ConnectionStatus { disconnected, connecting, connected }

enum AppMode { spotify, clock, gif, pomodoro }

@immutable
class DeviceState {
  final ConnectionStatus connectionStatus;
  final String? deviceIp;
  final String? deviceName;
  final AppMode activeMode;
  final String? errorMessage;

  const DeviceState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.deviceIp,
    this.deviceName,
    this.activeMode = AppMode.clock,
    this.errorMessage,
  });

  DeviceState copyWith({
    ConnectionStatus? connectionStatus,
    String? deviceIp,
    String? deviceName,
    AppMode? activeMode,
    String? errorMessage,
  }) {
    return DeviceState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      deviceIp: deviceIp ?? this.deviceIp,
      deviceName: deviceName ?? this.deviceName,
      activeMode: activeMode ?? this.activeMode,
      errorMessage: errorMessage,
    );
  }

  bool get isConnected => connectionStatus == ConnectionStatus.connected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState &&
          connectionStatus == other.connectionStatus &&
          deviceIp == other.deviceIp &&
          deviceName == other.deviceName &&
          activeMode == other.activeMode &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        connectionStatus,
        deviceIp,
        deviceName,
        activeMode,
        errorMessage,
      );
}
