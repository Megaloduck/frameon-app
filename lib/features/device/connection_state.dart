/// All possible states of the connection to the LED matrix device.
enum DeviceConnectionStatus {
  /// No device has been selected or connected yet.
  disconnected,

  /// Actively searching for available serial ports.
  scanning,

  /// A port has been selected and a connection is being established.
  connecting,

  /// Connected and ready to send frames.
  connected,

  /// A transmission is in progress.
  sending,

  /// The connection was lost unexpectedly.
  lost,

  /// An error occurred during connect or send.
  error,
}

/// Snapshot of the current device connection.
class DeviceConnectionState {
  final DeviceConnectionStatus status;

  /// The serial port name currently in use (e.g. "COM3", "/dev/ttyUSB0").
  final String? portName;

  /// Human-readable error message when [status] is [DeviceConnectionStatus.error].
  final String? errorMessage;

  /// Upload progress 0.0–1.0 when [status] is [DeviceConnectionStatus.sending].
  final double sendProgress;

  const DeviceConnectionState({
    this.status = DeviceConnectionStatus.disconnected,
    this.portName,
    this.errorMessage,
    this.sendProgress = 0,
  });

  bool get isConnected  => status == DeviceConnectionStatus.connected;
  bool get isSending    => status == DeviceConnectionStatus.sending;
  bool get isDisconnected => status == DeviceConnectionStatus.disconnected;

  DeviceConnectionState copyWith({
    DeviceConnectionStatus? status,
    String? portName,
    String? errorMessage,
    double? sendProgress,
  }) =>
      DeviceConnectionState(
        status: status ?? this.status,
        portName: portName ?? this.portName,
        errorMessage: errorMessage ?? this.errorMessage,
        sendProgress: sendProgress ?? this.sendProgress,
      );

  @override
  String toString() =>
      'DeviceConnectionState(status: $status, port: $portName)';
}