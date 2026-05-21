// lib/services/hid/hid_report.dart
//
// Dart mirror of the 7-byte FrameonHidReport C struct.
//
// Wire layout (8 bytes total including Report ID at byte 0):
//   [0]   report_id  always 0x01
//   [1]   enc_delta  int8   encoder steps (+ = CW)
//   [2-3] joy_x      uint16 raw ADC 0-4095 (app applies opacity + dead zone)
//   [4]   brightness uint8  current brightness (firmware-applied from joy Y)
//   [5]   buttons    uint8  held-button bitmask
//   [6]   events     uint8  long-press one-shot bitmask
//   [7]   taps       uint8  short-press one-shot bitmask

import 'dart:typed_data';

// ── Button masks (buttons field) ──────────────────────────────────────────────
const int kHidBtnEncPress = 1 << 0;
const int kHidBtnJoyPress = 1 << 1;
const int kHidBtn1        = 1 << 2;
const int kHidBtn2        = 1 << 3;
const int kHidBtn3        = 1 << 4;
const int kHidBtn4        = 1 << 5;
const int kHidBtn5        = 1 << 6;

// ── Event masks — long-press one-shot (events field) ─────────────────────────
const int kHidEvtEncLong  = 1 << 0;
const int kHidEvtJoyLong  = 1 << 1;
const int kHidEvtBtn1Long = 1 << 2;
const int kHidEvtBtn2Long = 1 << 3;
const int kHidEvtBtn3Long = 1 << 4;
const int kHidEvtBtn4Long = 1 << 5;
const int kHidEvtBtn5Long = 1 << 6;

// ── Tap masks — short-press one-shot (taps field) ─────────────────────────────
const int kHidTapEnc  = 1 << 0;
const int kHidTapJoy  = 1 << 1;
const int kHidTapBtn1 = 1 << 2;
const int kHidTapBtn2 = 1 << 3;
const int kHidTapBtn3 = 1 << 4;
const int kHidTapBtn4 = 1 << 5;
const int kHidTapBtn5 = 1 << 6;

// ── Joystick dead zone ────────────────────────────────────────────────────────
const int kJoyThreshold = 500;

/// Parsed USB HID input report from the Frameon controller.
class FrameonHidReport {
  final int encDelta;   // encoder steps since last report (+CW, -CCW)
  final int joyX;       // raw ADC 0-4095 (for opacity dead-zone in app)
  final int brightness; // current display brightness 0-255 (firmware-applied)
  final int buttons;    // held-button bitmask
  final int events;     // long-press one-shot bitmask
  final int taps;       // short-press one-shot bitmask

  const FrameonHidReport({
    required this.encDelta,
    required this.joyX,
    required this.brightness,
    required this.buttons,
    required this.events,
    required this.taps,
  });

  // ── Parser ────────────────────────────────────────────────────────────────

  static FrameonHidReport? tryParse(List<int> bytes) {
    if (bytes.length < 8) return null;
    if (bytes[0] != 0x01) return null; // wrong report ID

    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    return FrameonHidReport(
      encDelta:   view.getInt8(1),
      joyX:       view.getUint16(2, Endian.little),
      brightness: view.getUint8(4),
      buttons:    view.getUint8(5),
      events:     view.getUint8(6),
      taps:       view.getUint8(7),
    );
  }

  // ── Held-button accessors ─────────────────────────────────────────────────
  bool get encPressed  => (buttons & kHidBtnEncPress) != 0;
  bool get joyPressed  => (buttons & kHidBtnJoyPress) != 0;
  bool get btn1Pressed => (buttons & kHidBtn1) != 0;
  bool get btn2Pressed => (buttons & kHidBtn2) != 0;
  bool get btn3Pressed => (buttons & kHidBtn3) != 0;
  bool get btn4Pressed => (buttons & kHidBtn4) != 0;
  bool get btn5Pressed => (buttons & kHidBtn5) != 0;

  // ── Long-press one-shot accessors (events) ────────────────────────────────
  bool get encLong  => (events & kHidEvtEncLong)  != 0;
  bool get joyLong  => (events & kHidEvtJoyLong)  != 0;
  bool get btn1Long => (events & kHidEvtBtn1Long) != 0;
  bool get btn2Long => (events & kHidEvtBtn2Long) != 0;
  bool get btn3Long => (events & kHidEvtBtn3Long) != 0;
  bool get btn4Long => (events & kHidEvtBtn4Long) != 0;
  bool get btn5Long => (events & kHidEvtBtn5Long) != 0;

  // ── Short-press one-shot accessors (taps) ─────────────────────────────────
  bool get encTap  => (taps & kHidTapEnc)  != 0;
  bool get joyTap  => (taps & kHidTapJoy)  != 0;
  bool get btn1Tap => (taps & kHidTapBtn1) != 0;
  bool get btn2Tap => (taps & kHidTapBtn2) != 0;
  bool get btn3Tap => (taps & kHidTapBtn3) != 0;
  bool get btn4Tap => (taps & kHidTapBtn4) != 0;
  bool get btn5Tap => (taps & kHidTapBtn5) != 0;

  bool get encoderMoved => encDelta != 0;
  bool get encoderCW    => encDelta > 0;
  bool get encoderCCW   => encDelta < 0;

  /// Normalised joystick X: −1.0 (left/opacity−) … 0.0 … +1.0 (right/opacity+).
  double normJoyX(int centreX) {
    final delta = joyX - centreX;
    if (delta.abs() < kJoyThreshold) return 0.0;
    return (delta / (delta > 0 ? (4095 - centreX) : centreX.toDouble()))
        .clamp(-1.0, 1.0);
  }

  @override
  String toString() =>
      'HID(enc=$encDelta joyX=$joyX bright=$brightness '
      'btn=0x${buttons.toRadixString(16)} '
      'evt=0x${events.toRadixString(16)} '
      'tap=0x${taps.toRadixString(16)})';
}