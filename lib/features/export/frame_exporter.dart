import 'dart:ui';
import 'dart:typed_data';
import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';
import '../../engine/widgets/pomodoro_widget.dart';

/// Packet header magic bytes.
const List<int> _kMagic = [0x46, 0x52, 0x4D]; // "FRM"

/// Protocol flags.
const int _kVersionNormal = 0x03; // v2.0 — 80-byte header with clock v1.6
const int _kVersionNext   = 0x4E; // 'N' — next-song preload (unchanged)

// ── Clock flag bits (must match frameon.h CLK_FLAG_*) ────────────────────────
const int _kClkPresent = 0x01;
const int _kClkH12     = 0x02;
const int _kClkSeconds = 0x04;
const int _kClkDate    = 0x08;
const int _kClkBlink   = 0x10;
const int _kClkAmPm    = 0x20;

// ── Pomodoro flag bits (must match frameon.h POMO_FLAG_*) ────────────────────
const int _kPomoPresent = 0x01;
const int _kPomoRunning = 0x02;
const int _kPomoSeconds = 0x04;
const int _kPomoSession = 0x08;
const int _kPomoBlink   = 0x10;

// ── Pomodoro phase values (must match POMO_PHASE_* in pomodorohelper.h) ──────
const int _kPomoPhasesFocus      = 0;
const int _kPomoPhasesShortBreak = 1;
const int _kPomoPhasesLongBreak  = 2;

/// RGB colour → RGB565 packed uint16.
int _colorToRgb565(Color color) {
  final int r = (color.red   >> 3) & 0x1F;
  final int g = (color.green >> 2) & 0x3F;
  final int b = (color.blue  >> 3) & 0x1F;
  return (r << 11) | (g << 5) | b;
}

/// Progress bar geometry per [SpotifyLayout].
({int barX, int barY, int barW}) _barGeometry(
    SpotifyLayout layout, bool showProgress) {
  if (!showProgress) return (barX: 0, barY: 0, barW: 0);
  return switch (layout) {
    SpotifyLayout.artAndText => (barX: 33, barY: 29, barW: 30),
    SpotifyLayout.textOnly   => (barX: 0,  barY: 30, barW: 64),
    SpotifyLayout.artOnly    => (barX: 0,  barY: 30, barW: 64),
  };
}

/// Maps [LedFontId] to the uint8 font index the firmware uses.
int _fontIdToByte(LedFontId id) => LedFontId.values.indexOf(id);

/// Converts a signed integer timezone offset in minutes to a signed int16.
/// Clamped to ±1440 (±24 h).
int _tzMinToInt16(int minutes) => minutes.clamp(-1440, 1440);

/// Returns the total phase duration in seconds for the firmware progress arc.
int _pomodoroTotalSecs(PomodoroState phase, PomodoroLayer layer) =>
    switch (phase) {
      PomodoroState.focus      => layer.focusDurationMinutes * 60,
      PomodoroState.shortBreak => layer.shortBreakMinutes    * 60,
      PomodoroState.longBreak  => layer.longBreakMinutes     * 60,
    };

/// The [FrameExporter] converts a [Timeline] into the binary packet format
/// transmitted to the LED matrix device over Serial.
///
/// ## Packet Layout v2.0 (header = 80 bytes)
///
/// ```
/// [0-2]   "FRM" magic
/// [3]     flags         0x03 normal | 0x4E next-song
/// [4-5]   frameCount    uint16 BE
/// [6-7]   width         uint16 BE
/// [8-9]   height        uint16 BE
/// [10-11] durMs         uint16 BE
/// [12-15] payloadBytes  uint32 BE
/// [16-19] startPosMs    uint32 BE  (Spotify)
/// [20-23] trackDurMs    uint32 BE  (Spotify)
/// [24]    barX          uint8
/// [25]    barY          uint8
/// [26]    barW          uint8
/// [27-28] barColor      uint16 BE RGB565
/// ── Clock descriptor v1.5 ────────────────────────────────────────────────
/// [29]    clockFlags    uint8   bit0=present bit1=h12 bit2=seconds
///                                bit3=date bit4=blink bit5=ampm
/// [30-33] clockEpochSec uint32 BE  Unix time at commit
/// [34-35] clockTzMin    int16 BE   signed tz offset in minutes
/// [36]    clockFontId   uint8
/// [37]    clockOffsetX  int8
/// [38]    clockOffsetY  int8
/// [39]    reserved      uint8  0x00
/// [40-41] hoursColor    uint16 BE RGB565
/// [42-43] minutesColor  uint16 BE RGB565
/// [44-45] secondsColor  uint16 BE RGB565
/// [46-47] colonColor    uint16 BE RGB565
/// [48-49] dateColor     uint16 BE RGB565
/// [50-51] ampmColor     uint16 BE RGB565
/// ── Pomodoro descriptor v1.9 ─────────────────────────────────────────────
/// [52]    pomodoroFlags   uint8
/// [53-56] pomodoroRemSec  uint32 BE
/// [57]    pomodoroPhase   uint8
/// [58]    pomodoroSession uint8
/// [59]    pomodoroOffsetX int8
/// [60]    pomodoroOffsetY int8
/// [61-62] pomodoroColor   uint16 BE RGB565
/// [63]    pomodoroLayout  uint8
/// [64]    pomodoroSessTotal uint8
/// [65-66] pomodoroTotalSec  uint16 BE
/// [67]    reserved        0x00
/// ── Clock extension v1.6 ─────────────────────────────────────────────────
/// [68]    layoutStyle   uint8   ClockLayoutStyle.index (0=classic..5=dual)
/// [69]    analogFlags   uint8   bits0-1=faceStyle, bit2=secHand, bit3=digital
/// [70-71] tz2OffsetMin  int16 BE  second timezone offset in minutes
/// [72-75] label1        4×ASCII null-padded (first zone short label)
/// [76-79] label2        4×ASCII null-padded (second zone short label)
/// ── Payload ──────────────────────────────────────────────────────────────
/// [80..N] RGB565 pixel data  (frameCount × width × height × 2)
/// [N+1-2] CRC-16/CCITT
/// ```
class FrameExporter {
  final int matrixWidth;
  final int matrixHeight;

  const FrameExporter({this.matrixWidth = 64, this.matrixHeight = 32});

  static const int _headerSize = 80; // v2.0 (was 68 in v1.9)

  // ── Public API ────────────────────────────────────────────────────────────

  /// Build a normal-commit packet.
  Uint8List export(
    Timeline timeline, {
    int startPositionMs = 0,
    int trackDurationMs = 0,
    SpotifyLayout? layout,
    bool showProgress = false,
    Color progressColor = const Color(0xFF21C32C),
    ClockLayer? clockLayer,
    DateTime? clockCommitTime,
    PomodoroLayer? pomodoroLayer,
    PomodoroTimerState? pomodoroState,
  }) =>
      _build(
        timeline,
        flags: _kVersionNormal,
        startPositionMs: startPositionMs,
        trackDurationMs: trackDurationMs,
        layout: layout,
        showProgress: showProgress,
        progressColor: progressColor,
        clockLayer: clockLayer,
        clockCommitTime: clockCommitTime,
        pomodoroLayer: pomodoroLayer,
        pomodoroState: pomodoroState,
      );

  /// Build a next-song preload packet.
  Uint8List exportNext(
    Timeline timeline, {
    int startPositionMs = 0,
    int trackDurationMs = 0,
    SpotifyLayout? layout,
    bool showProgress = false,
    Color progressColor = const Color(0xFF21C32C),
  }) =>
      _build(
        timeline,
        flags: _kVersionNext,
        startPositionMs: startPositionMs,
        trackDurationMs: trackDurationMs,
        layout: layout,
        showProgress: showProgress,
        progressColor: progressColor,
        // next-song preload packets never carry clock or pomodoro descriptors.
      );

  // ── Internal build ────────────────────────────────────────────────────────

  Uint8List _build(
    Timeline timeline, {
    required int flags,
    required int startPositionMs,
    required int trackDurationMs,
    SpotifyLayout? layout,
    bool showProgress = false,
    Color progressColor = const Color(0xFF21C32C),
    ClockLayer? clockLayer,
    DateTime? clockCommitTime,
    PomodoroLayer? pomodoroLayer,
    PomodoroTimerState? pomodoroState,
  }) {
    if (timeline.frameCount == 0) {
      throw StateError('Cannot export an empty timeline.');
    }

    final int frameCount    = timeline.frameCount;
    final int durationMs    = timeline.frames.first.durationMs;
    final int bytesPerFrame = matrixWidth * matrixHeight * 2;
    final int payloadBytes  = frameCount * bytesPerFrame;

    final Uint8List packet = Uint8List(_headerSize + payloadBytes + 2);
    final ByteData  bd     = ByteData.sublistView(packet);

    final bar = layout != null
        ? _barGeometry(layout, showProgress)
        : (barX: 0, barY: 0, barW: 0);

    int off = 0;

    // ── Magic [0..2] ──────────────────────────────────────────────────────
    packet[off++] = _kMagic[0];
    packet[off++] = _kMagic[1];
    packet[off++] = _kMagic[2];

    // ── Flags [3] ─────────────────────────────────────────────────────────
    packet[off++] = flags;

    // ── Frame metadata [4..15] ────────────────────────────────────────────
    bd.setUint16(off, frameCount,   Endian.big); off += 2;
    bd.setUint16(off, matrixWidth,  Endian.big); off += 2;
    bd.setUint16(off, matrixHeight, Endian.big); off += 2;
    bd.setUint16(off, durationMs,   Endian.big); off += 2;
    bd.setUint32(off, payloadBytes, Endian.big); off += 4;

    // ── Spotify progress bar [16..28] ─────────────────────────────────────
    bd.setUint32(off, startPositionMs,               Endian.big); off += 4;
    bd.setUint32(off, trackDurationMs,               Endian.big); off += 4;
    packet[off++] = bar.barX;
    packet[off++] = bar.barY;
    packet[off++] = bar.barW;
    bd.setUint16(off, _colorToRgb565(progressColor), Endian.big); off += 2;

    // ── Clock descriptor v1.5 [29..51] ───────────────────────────────────
    if (clockLayer != null && clockCommitTime != null) {
      int clockFlags = _kClkPresent;
      if (clockLayer.format == ClockFormat.h12) clockFlags |= _kClkH12;
      if (clockLayer.showSeconds)               clockFlags |= _kClkSeconds;
      if (clockLayer.showDate)                  clockFlags |= _kClkDate;
      if (clockLayer.blinkColon)                clockFlags |= _kClkBlink;
      if (clockLayer.format == ClockFormat.h12) clockFlags |= _kClkAmPm;

      final int epochSec = clockCommitTime.toUtc().millisecondsSinceEpoch ~/ 1000;
      final int tzMin    = _tzOffsetForId(clockLayer.timezone);

      packet[off++] = clockFlags;                                              // [29]
      bd.setUint32(off, epochSec,                             Endian.big); off += 4; // [30-33]
      bd.setInt16 (off, _tzMinToInt16(tzMin),                 Endian.big); off += 2; // [34-35]
      packet[off++] = _fontIdToByte(clockLayer.fontId);                       // [36]
      packet[off++] = clockLayer.offset.dx.round().clamp(-128, 127) & 0xFF;   // [37]
      packet[off++] = clockLayer.offset.dy.round().clamp(-128, 127) & 0xFF;   // [38]
      packet[off++] = 0x00;                                                    // [39] reserved
      bd.setUint16(off, _colorToRgb565(clockLayer.hoursColor),   Endian.big); off += 2; // [40-41]
      bd.setUint16(off, _colorToRgb565(clockLayer.minutesColor), Endian.big); off += 2; // [42-43]
      bd.setUint16(off, _colorToRgb565(clockLayer.secondsColor), Endian.big); off += 2; // [44-45]
      bd.setUint16(off, _colorToRgb565(clockLayer.colonColor),   Endian.big); off += 2; // [46-47]
      bd.setUint16(off, _colorToRgb565(clockLayer.dateColor),    Endian.big); off += 2; // [48-49]
      bd.setUint16(off, _colorToRgb565(clockLayer.ampmColor),    Endian.big); off += 2; // [50-51]
    } else {
      off += 23; // No clock — zero-fill [29..51]
    }

    // ── Pomodoro descriptor v1.9 [52..67] ────────────────────────────────
    if (pomodoroLayer != null && pomodoroState != null) {
      int pomoFlags = _kPomoPresent;
      if (pomodoroState.isRunning)   pomoFlags |= _kPomoRunning;
      if (pomodoroLayer.showSeconds) pomoFlags |= _kPomoSeconds;
      if (pomodoroLayer.showSession) pomoFlags |= _kPomoSession;
      if (pomodoroLayer.blinkColor)  pomoFlags |= _kPomoBlink;

      final int remainingSec = pomodoroState.remaining.inSeconds;
      final int phase = switch (pomodoroState.phase) {
        PomodoroState.focus      => _kPomoPhasesFocus,
        PomodoroState.shortBreak => _kPomoPhasesShortBreak,
        PomodoroState.longBreak  => _kPomoPhasesLongBreak,
      };
      final Color activeColor = switch (pomodoroState.phase) {
        PomodoroState.focus      => pomodoroLayer.focusColor,
        PomodoroState.shortBreak => pomodoroLayer.breakColor,
        PomodoroState.longBreak  => pomodoroLayer.longBreakColor,
      };
      final int layoutByte = pomodoroLayer.layout.index;
      final int totalSecs  = _pomodoroTotalSecs(pomodoroState.phase, pomodoroLayer)
          .clamp(1, 65535);

      packet[off++] = pomoFlags;                                               // [52]
      bd.setUint32(off, remainingSec,                         Endian.big); off += 4; // [53-56]
      packet[off++] = phase;                                                   // [57]
      packet[off++] = pomodoroState.session.clamp(0, 255);                    // [58]
      packet[off++] = pomodoroLayer.offset.dx.round().clamp(-128, 127) & 0xFF; // [59]
      packet[off++] = pomodoroLayer.offset.dy.round().clamp(-128, 127) & 0xFF; // [60]
      bd.setUint16(off, _colorToRgb565(activeColor),          Endian.big); off += 2; // [61-62]
      packet[off++] = layoutByte;                                              // [63]
      packet[off++] = pomodoroLayer.sessionsBeforeLongBreak.clamp(1, 255);    // [64]
      bd.setUint16(off, totalSecs,                            Endian.big); off += 2; // [65-66]
      packet[off++] = 0x00;                                                    // [67] reserved
    } else {
      off += 16; // No pomodoro — zero-fill [52..67]
    }

    // ── Clock extension v1.6 [68..79] ────────────────────────────────────
    if (clockLayer != null && clockCommitTime != null) {
      // [68] Layout style — ClockLayoutStyle.index (classic=0..dualTimezone=5)
      packet[off++] = clockLayer.layoutStyle.index;

      // [69] Analog flags — packed byte
      int analogFlags = clockLayer.analogFaceStyle.index & 0x03; // bits 0-1: face style
      if (clockLayer.showSecondHand)    analogFlags |= 0x04;     // bit 2
      if (clockLayer.analogShowDigital) analogFlags |= 0x08;     // bit 3
      packet[off++] = analogFlags;

      // [70-71] Second timezone offset (int16 BE, minutes)
      final int tz2Min = _tzOffsetForId(clockLayer.secondTimezone);
      bd.setInt16(off, _tzMinToInt16(tz2Min), Endian.big); off += 2;

      // [72-75] First zone label — 4 ASCII bytes, null-padded
      // Empty string → renderer auto-derives from timezone id
      final String lbl1 = clockLayer.firstZoneLabel.isNotEmpty
          ? clockLayer.firstZoneLabel
          : defaultZoneLabel(clockLayer.timezone);
      _writeFixedAscii(packet, off, lbl1, 4); off += 4;

      // [76-79] Second zone label — 4 ASCII bytes, null-padded
      final String lbl2 = clockLayer.secondZoneLabel.isNotEmpty
          ? clockLayer.secondZoneLabel
          : defaultZoneLabel(clockLayer.secondTimezone);
      _writeFixedAscii(packet, off, lbl2, 4); off += 4;
    } else {
      off += 12; // No clock — zero-fill [68..79]
    }

    // ── Pixel payload ─────────────────────────────────────────────────────
    assert(off == _headerSize,
        'Header offset mismatch: expected $_headerSize, got $off');

    int px = _headerSize;
    for (final frame in timeline.frames) {
      packet.setRange(px, px + frame.data.length, frame.data);
      px += frame.data.length;
    }

    // ── CRC-16/CCITT ──────────────────────────────────────────────────────
    final int crcOffset = _headerSize + payloadBytes;
    final int crc       = _crc16(packet, crcOffset);
    packet[crcOffset]     = (crc >> 8) & 0xFF;
    packet[crcOffset + 1] =  crc       & 0xFF;

    return packet;
  }

  // ── CRC-16/CCITT — poly 0x1021, init 0xFFFF ────────────────────────────

  static int _crc16(Uint8List data, int length) {
    int crc = 0xFFFF;
    for (int i = 0; i < length; i++) {
      crc ^= data[i] << 8;
      for (int j = 0; j < 8; j++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Write [s] as ASCII into [packet] at [off], truncating or null-padding
  /// to exactly [len] bytes. Non-ASCII chars become '?' (0x3F).
  static void _writeFixedAscii(Uint8List packet, int off, String s, int len) {
    for (int i = 0; i < len; i++) {
      if (i < s.length) {
        final int code = s.codeUnitAt(i);
        packet[off + i] = (code > 0 && code < 0x80) ? code : 0x3F;
      } else {
        packet[off + i] = 0;
      }
    }
  }

  /// Returns the UTC offset in minutes for [tzId].
  /// Uses the system clock for 'local'. Looks up named zones in the
  /// embedded table so the second timezone in DualTimezone mode is correct.
  static int _tzOffsetForId(String tzId) {
    if (tzId == 'local') {
      return DateTime.now().timeZoneOffset.inMinutes;
    }
    final double? offsetHours = _kExportTzOffsets[tzId];
    if (offsetHours == null) return 0;
    return (offsetHours * 60).round();
  }

  /// UTC offset table — mirrors the one in clock_widget.dart and
  /// kTzShortLabels in layer.dart so all three agree.
  static const Map<String, double> _kExportTzOffsets = {
    'UTC':                 0,
    'Europe/London':       0,    'Europe/Lisbon':      0,
    'Europe/Paris':        1,    'Europe/Berlin':      1,
    'Europe/Rome':         1,    'Europe/Amsterdam':   1,
    'Europe/Madrid':       1,    'Europe/Warsaw':      1,
    'Europe/Athens':       2,    'Europe/Bucharest':   2,
    'Europe/Helsinki':     2,    'Europe/Istanbul':    3,
    'Europe/Moscow':       3,    'Asia/Riyadh':        3,
    'Asia/Dubai':          4,    'Asia/Baku':          4,
    'Asia/Kabul':          4.5,
    'Asia/Karachi':        5,    'Asia/Tashkent':      5,
    'Asia/Kolkata':        5.5,  'Asia/Colombo':       5.5,
    'Asia/Kathmandu':      5.75,
    'Asia/Dhaka':          6,    'Asia/Almaty':        6,
    'Asia/Rangoon':        6.5,
    'Asia/Bangkok':        7,    'Asia/Jakarta':       7,
    'Asia/Ho_Chi_Minh':    7,
    'Asia/Singapore':      8,    'Asia/Shanghai':      8,
    'Asia/Taipei':         8,    'Asia/Kuala_Lumpur':  8,
    'Asia/Manila':         8,
    'Asia/Seoul':          9,    'Asia/Tokyo':         9,
    'Australia/Darwin':    9.5,  'Australia/Adelaide': 9.5,
    'Australia/Brisbane':  10,   'Australia/Sydney':   10,
    'Pacific/Auckland':    12,   'Pacific/Fiji':       12,
    'Pacific/Honolulu':   -10,
    'America/Anchorage':  -9,
    'America/Los_Angeles':-8,
    'America/Denver':     -7,    'America/Phoenix':   -7,
    'America/Chicago':    -6,
    'America/New_York':   -5,    'America/Toronto':   -5,
    'America/Halifax':    -4,
    'America/Sao_Paulo':  -3,    'America/Buenos_Aires': -3,
    'Atlantic/Azores':    -1,
  };
}