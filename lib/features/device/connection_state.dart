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

  /// The connection was lost unexpectedly (USB removed, device reset, etc.).
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

  bool get isConnected   => status == DeviceConnectionStatus.connected;
  bool get isSending     => status == DeviceConnectionStatus.sending;
  bool get isDisconnected => status == DeviceConnectionStatus.disconnected;

  /// Creates a copy with the given fields replaced.
  ///
  /// ## Clearing nullable fields
  ///
  /// The original implementation used `??` for every field, which made it
  /// impossible to set [portName] or [errorMessage] back to null once they
  /// were set — passing `null` was indistinguishable from "not provided".
  ///
  /// This version uses a private sentinel [_keep] object. Omitting a nullable
  /// parameter leaves the existing value; passing `null` explicitly clears it.
  ///
  /// ```dart
  /// // Clear the error message after a successful send:
  /// state = state.copyWith(
  ///   status: DeviceConnectionStatus.connected,
  ///   errorMessage: null,   // ← actually clears it now
  /// );
  /// ```
  DeviceConnectionState copyWith({
    DeviceConnectionStatus? status,
    Object?                 portName     = _keep,
    Object?                 errorMessage = _keep,
    double?                 sendProgress,
  }) =>
      DeviceConnectionState(
        status:       status       ?? this.status,
        portName:     portName     == _keep ? this.portName     : portName     as String?,
        errorMessage: errorMessage == _keep ? this.errorMessage : errorMessage as String?,
        sendProgress: sendProgress ?? this.sendProgress,
      );

  @override
  String toString() =>
      'DeviceConnectionState(status: $status, port: $portName, err: $errorMessage)';
}

/// Sentinel used by [DeviceConnectionState.copyWith] to distinguish
/// "field not provided" from "field explicitly set to null".
const Object _keep = Object();