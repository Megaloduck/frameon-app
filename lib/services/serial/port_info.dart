class PortInfo {
  final String name;           // "COM3" / "/dev/ttyUSB0"
  final String? description;   // "Silicon Labs CP210x USB to UART Bridge"
  final String? manufacturer;  // "Silicon Laboratories"

  const PortInfo({
    required this.name,
    this.description,
    this.manufacturer,
  });

  /// Best label to show in the UI — description if available, else name.
  String get displayLabel => description?.isNotEmpty == true ? description! : name;
}