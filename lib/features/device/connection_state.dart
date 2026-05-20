// lib/features/device/connection_state.dart

enum DeviceConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  sending,
  lost,
  error,
}

class DeviceConnectionState {
  final DeviceConnectionStatus status;
  final String? portName;
  final String? errorMessage;
  final double  sendProgress;

  // ── Hardware-mirrored state (updated live by EVT listener) ────────────────

  /// Current brightness as applied by the device (0–255).
  /// Mirrors the last "EVT BRIGHT <n>" message.
  final int  deviceBrightness;

  /// True when the user long-held the encoder to lock the display.
  /// When locked, [DeviceController.sendToDevice] is a no-op.
  final bool deviceLocked;

  const DeviceConnectionState({
    this.status           = DeviceConnectionStatus.disconnected,
    this.portName,
    this.errorMessage,
    this.sendProgress     = 0,
    this.deviceBrightness = 128,   // matches firmware DEFAULT_BRIGHTNESS
    this.deviceLocked     = false,
  });

  bool get isConnected    => status == DeviceConnectionStatus.connected;
  bool get isSending      => status == DeviceConnectionStatus.sending;
  bool get isDisconnected => status == DeviceConnectionStatus.disconnected;

  /// Brightness as 0.0–1.0 for Slider / indicator widgets.
  double get brightnessNorm => deviceBrightness / 255.0;

  DeviceConnectionState copyWith({
    DeviceConnectionStatus? status,
    Object?  portName          = _keep,
    Object?  errorMessage      = _keep,
    double?  sendProgress,
    int?     deviceBrightness,
    bool?    deviceLocked,
  }) =>
      DeviceConnectionState(
        status:           status            ?? this.status,
        portName:         portName          == _keep ? this.portName     : portName     as String?,
        errorMessage:     errorMessage      == _keep ? this.errorMessage : errorMessage as String?,
        sendProgress:     sendProgress      ?? this.sendProgress,
        deviceBrightness: deviceBrightness  ?? this.deviceBrightness,
        deviceLocked:     deviceLocked      ?? this.deviceLocked,
      );

  @override
  String toString() =>
      'DeviceConnectionState(status: $status, port: $portName, '
      'bright: $deviceBrightness, locked: $deviceLocked)';
}

const Object _keep = Object();