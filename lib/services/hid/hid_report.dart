// lib/services/hid/hid_report.dart
//
// Dart mirror of the 7-byte FrameonHidReport C struct.
// Matches the on-wire layout exactly (little-endian, packed).

import 'dart:typed_data';

// ── Button bit masks (field: buttons) ────────────────────────────────────────
const int kHidBtnEncPress = 1 << 0;
const int kHidBtnJoyPress = 1 << 1;
const int kHidBtn1        = 1 << 2;
const int kHidBtn2        = 1 << 3;
const int kHidBtn3        = 1 << 4;
const int kHidBtn4        = 1 << 5;
const int kHidBtn5        = 1 << 6;

// ── Event bit masks (field: events, one-shot) ─────────────────────────────────
const int kHidEvtEncLong  = 1 << 0;
const int kHidEvtJoyLong  = 1 << 1;
const int kHidEvtBtn1Long = 1 << 2;
const int kHidEvtBtn2Long = 1 << 3;
const int kHidEvtBtn3Long = 1 << 4;
const int kHidEvtBtn4Long = 1 << 5;
const int kHidEvtBtn5Long = 1 << 6;

// ── Joystick dead-zone ────────────────────────────────────────────────────────
/// ADC counts from calibrated centre required to register an axis move.
const int kJoyThreshold = 500;

/// FrameonHidReport — parsed from an 8-byte USB HID input report.
///
/// Byte layout (after report ID byte 0):
///   [0]      encDelta  int8   encoder steps since last report
///   [1-2]    joyX      uint16 raw ADC 0-4095
///   [3-4]    joyY      uint16 raw ADC 0-4095
///   [5]      buttons   uint8  held-button bitmask
///   [6]      events    uint8  one-shot event bitmask
class FrameonHidReport {
  /// Encoder steps since the last report (positive = CW, negative = CCW).
  final int encDelta;

  /// Raw joystick X ADC value (0–4095). Apply calibration on this side.
  final int joyX;

  /// Raw joystick Y ADC value (0–4095).
  final int joyY;

  /// Bitmask of buttons currently held — see kHidBtn* constants.
  final int buttons;

  /// Bitmask of one-shot events fired this cycle — see kHidEvt* constants.
  final int events;

  const FrameonHidReport({
    required this.encDelta,
    required this.joyX,
    required this.joyY,
    required this.buttons,
    required this.events,
  });

  /// Parse from a raw HID report byte list.
  ///
  /// [bytes] must contain the full report including the Report ID at index 0.
  /// Returns null if the data is malformed or the report ID is unexpected.
  static FrameonHidReport? tryParse(List<int> bytes) {
    if (bytes.length < 8) return null;
    if (bytes[0] != 0x01) return null; // wrong report ID

    final data = Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);

    final encDelta = view.getInt8(1);               // signed
    final joyX     = view.getUint16(2, Endian.little);
    final joyY     = view.getUint16(4, Endian.little);
    final buttons  = view.getUint8(6);
    final events   = view.getUint8(7);

    return FrameonHidReport(
      encDelta: encDelta,
      joyX:     joyX,
      joyY:     joyY,
      buttons:  buttons,
      events:   events,
    );
  }

  // ── Convenience accessors ─────────────────────────────────────────────────

  bool get encoderMoved    => encDelta != 0;
  bool get encoderCW       => encDelta > 0;
  bool get encoderCCW      => encDelta < 0;

  bool get encPressed      => (buttons & kHidBtnEncPress) != 0;
  bool get joyPressed      => (buttons & kHidBtnJoyPress) != 0;
  bool get btn1Pressed     => (buttons & kHidBtn1) != 0;
  bool get btn2Pressed     => (buttons & kHidBtn2) != 0;
  bool get btn3Pressed     => (buttons & kHidBtn3) != 0;
  bool get btn4Pressed     => (buttons & kHidBtn4) != 0;
  bool get btn5Pressed     => (buttons & kHidBtn5) != 0;

  bool get encLong         => (events  & kHidEvtEncLong)  != 0;
  bool get joyLong         => (events  & kHidEvtJoyLong)  != 0;
  bool get btn1Long        => (events  & kHidEvtBtn1Long) != 0;
  bool get btn2Long        => (events  & kHidEvtBtn2Long) != 0;
  bool get btn3Long        => (events  & kHidEvtBtn3Long) != 0;
  bool get btn4Long        => (events  & kHidEvtBtn4Long) != 0;
  bool get btn5Long        => (events  & kHidEvtBtn5Long) != 0;

  /// Normalised joystick X: −1.0 (left) … 0.0 (centre) … +1.0 (right).
  /// [centreX] = calibrated resting ADC value from [kJoyCentreDefault] or
  /// whatever the firmware reported in its first few packets.
  double normJoyX(int centreX) {
    final delta = joyX - centreX;
    if (delta.abs() < kJoyThreshold) return 0.0;
    return (delta / (delta > 0 ? (4095 - centreX) : centreX.toDouble()))
        .clamp(-1.0, 1.0);
  }

  /// Normalised joystick Y: −1.0 (up) … 0.0 (centre) … +1.0 (down).
  double normJoyY(int centreY) {
    final delta = joyY - centreY;
    if (delta.abs() < kJoyThreshold) return 0.0;
    return (delta / (delta > 0 ? (4095 - centreY) : centreY.toDouble()))
        .clamp(-1.0, 1.0);
  }

  @override
  String toString() =>
      'HID(enc=$encDelta joyX=$joyX joyY=$joyY btn=0x${buttons.toRadixString(16)} evt=0x${events.toRadixString(16)})';
}