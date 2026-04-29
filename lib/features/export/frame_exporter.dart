import 'dart:ui';
import 'dart:typed_data';
import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';
import '../../engine/widgets/pomodoro_widget.dart';

/// Packet header magic bytes.
const List<int> _kMagic = [0x46, 0x52, 0x4D]; // "FRM"

/// Protocol flags.
const int _kVersionNormal = 0x02;
const int _kVersionNext   = 0x4E;

// ── Clock flag bits (must match frameon.h CLK_FLAG_*) ────────────────────────
const int _kClkPresent = 0x01;
const int _kClkH12     = 0x02;
const int _kClkSeconds = 0x04;
const int _kClkDate    = 0x08;
const int _kClkBlink   = 0x10;
const int _kClkAmPm    = 0x20;

// ── Pomodoro flag bits (must match frameon.h POMO_FLAG_*) ────────────────────
const int _kPomoPresent  = 0x01;
const int _kPomoRunning  = 0x02;
const int _kPomoSeconds  = 0x04;
const int _kPomoSession  = 0x08;
const int _kPomoBlink    = 0x10;

// ── Pomodoro phase values (must match POMO_PHASE_* in pomodorohelper.h) ──────
const int _kPomoPhasesFocus      = 0;
const int _kPomoPhasesShortBreak = 1;
const int _kPomoPhasesLongBreak  = 2;

/// Progress bar geometry per [SpotifyLayout].
int _colorToRgb565(Color color) {
  final int r = (color.red   >> 3) & 0x1F;
  final int g = (color.green >> 2) & 0x3F;
  final int b = (color.blue  >> 3) & 0x1F;
  return (r << 11) | (g << 5) | b;
}

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

/// The [FrameExporter] converts a [Timeline] into the binary packet format
/// transmitted to the LED matrix device over Serial.
///
/// ## Packet Layout v1.8 (header = 68 bytes)
///
/// ```
/// [0-2]   "FRM" magic
/// [3]     flags         0x02 normal | 0x4E next-song
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
/// ── v1.8 Pomodoro descriptor ─────────────────────────────────────────────
/// [52]    pomodoroFlags  uint8   bit0=present bit1=running bit2=seconds
///                                bit3=session bit4=blink
/// [53-56] pomodoroRemSec uint32 BE  seconds remaining at commit
/// [57]    pomodoroPhase  uint8   0=focus 1=shortBreak 2=longBreak
/// [58]    pomodoroSession uint8  current session (1-based)
/// [59]    pomodoroOffsetX int8
/// [60]    pomodoroOffsetY int8
/// [61-62] pomodoroColor  uint16 BE RGB565  (active phase colour)
/// [63-67] reserved       5 × 0x00
/// [68..N] RGB565 pixel data
/// [N+1-2] CRC-16/CCITT
/// ```
class FrameExporter {
  final int matrixWidth;
  final int matrixHeight;

  const FrameExporter({this.matrixWidth = 64, this.matrixHeight = 32});

  static const int _headerSize = 68; // v1.8

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

    // Magic
    packet[off++] = _kMagic[0];
    packet[off++] = _kMagic[1];
    packet[off++] = _kMagic[2];

    // Flags
    packet[off++] = flags;

    // Frame metadata
    bd.setUint16(off, frameCount,      Endian.big); off += 2;
    bd.setUint16(off, matrixWidth,     Endian.big); off += 2;
    bd.setUint16(off, matrixHeight,    Endian.big); off += 2;
    bd.setUint16(off, durationMs,      Endian.big); off += 2;
    bd.setUint32(off, payloadBytes,    Endian.big); off += 4;

    // Spotify progress bar
    bd.setUint32(off, startPositionMs, Endian.big); off += 4;
    bd.setUint32(off, trackDurationMs, Endian.big); off += 4;

    final int barColorRgb565 = _colorToRgb565(progressColor);
    packet[off++] = bar.barX;
    packet[off++] = bar.barY;
    packet[off++] = bar.barW;
    bd.setUint16(off, barColorRgb565,  Endian.big); off += 2;

    // ── v1.5 Clock descriptor [29..51] ───────────────────────────────────
    if (clockLayer != null && clockCommitTime != null) {
      int clockFlags = _kClkPresent;
      if (clockLayer.format == ClockFormat.h12) clockFlags |= _kClkH12;
      if (clockLayer.showSeconds)               clockFlags |= _kClkSeconds;
      if (clockLayer.showDate)                  clockFlags |= _kClkDate;
      if (clockLayer.blinkColon)                clockFlags |= _kClkBlink;
      if (clockLayer.format == ClockFormat.h12) clockFlags |= _kClkAmPm;

      final int epochSec = clockCommitTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      final int tzMin = clockLayer.timezone == 'local'
          ? clockCommitTime.timeZoneOffset.inMinutes
          : _tzOffsetForId(clockLayer.timezone);

      packet[off++] = clockFlags;
      bd.setUint32(off, epochSec,                   Endian.big); off += 4;
      bd.setInt16 (off, _tzMinToInt16(tzMin),        Endian.big); off += 2;
      packet[off++] = _fontIdToByte(clockLayer.fontId);
      packet[off++] = clockLayer.offset.dx.round().clamp(-128, 127) & 0xFF;
      packet[off++] = clockLayer.offset.dy.round().clamp(-128, 127) & 0xFF;
      packet[off++] = 0x00; // reserved [39]
      bd.setUint16(off, _colorToRgb565(clockLayer.hoursColor),   Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.minutesColor), Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.secondsColor), Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.colonColor),   Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.dateColor),    Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.ampmColor),    Endian.big); off += 2;
    } else {
      // No clock — write 23 zero bytes to fill [29..51].
      off += 23;
    }

    // ── v1.8 Pomodoro descriptor [52..67] ─────────────────────────────────
    if (pomodoroLayer != null && pomodoroState != null) {
      int pomoFlags = _kPomoPresent;
      if (pomodoroState.isRunning)    pomoFlags |= _kPomoRunning;
      if (pomodoroLayer.showSeconds)  pomoFlags |= _kPomoSeconds;
      if (pomodoroLayer.showSession)  pomoFlags |= _kPomoSession;
      if (pomodoroLayer.blinkColor)   pomoFlags |= _kPomoBlink;

      final int remainingSec = pomodoroState.remaining.inSeconds;

      final int phase = switch (pomodoroState.phase) {
        PomodoroState.focus      => _kPomoPhasesFocus,
        PomodoroState.shortBreak => _kPomoPhasesShortBreak,
        PomodoroState.longBreak  => _kPomoPhasesLongBreak,
      };

      // Active phase colour (focus / short break / long break).
      final Color activeColor = switch (pomodoroState.phase) {
        PomodoroState.focus      => pomodoroLayer.focusColor,
        PomodoroState.shortBreak => pomodoroLayer.breakColor,
        PomodoroState.longBreak  => pomodoroLayer.longBreakColor,
      };

      packet[off++] = pomoFlags;
      bd.setUint32(off, remainingSec,                     Endian.big); off += 4;
      packet[off++] = phase;
      packet[off++] = pomodoroState.session.clamp(0, 255);
      packet[off++] = pomodoroLayer.offset.dx.round().clamp(-128, 127) & 0xFF;
      packet[off++] = pomodoroLayer.offset.dy.round().clamp(-128, 127) & 0xFF;
      bd.setUint16(off, _colorToRgb565(activeColor),      Endian.big); off += 2;
      // 5 reserved bytes [63..67]
      for (int i = 0; i < 5; i++) packet[off++] = 0x00;
    } else {
      // No pomodoro — write 16 zero bytes to fill [52..67].
      off += 16;
    }

    // ── Pixel payload ─────────────────────────────────────────────────────
    assert(off == _headerSize, 'Header size mismatch: wrote $off, expected $_headerSize');
    int pixOff = _headerSize;
    for (final frame in timeline.frames) {
      for (int i = 0; i < frame.data.length; i++) {
        packet[pixOff++] = frame.data[i];
      }
    }

    // ── CRC-16/CCITT ──────────────────────────────────────────────────────
    final int crc = _crc16(packet, _headerSize + payloadBytes);
    packet[_headerSize + payloadBytes]     = (crc >> 8) & 0xFF;
    packet[_headerSize + payloadBytes + 1] =  crc       & 0xFF;

    return packet;
  }

  // ── CRC-16/CCITT (poly 0x1021, init 0xFFFF) ──────────────────────────────
  int _crc16(Uint8List data, int length) {
    int crc = 0xFFFF;
    for (int i = 0; i < length; i++) {
      crc ^= data[i] << 8;
      for (int j = 0; j < 8; j++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  // ── Timezone offset lookup (non-local IDs) ────────────────────────────────
  // Only a representative subset — extend as needed.
  static int _tzOffsetForId(String id) {
    const Map<String, int> _table = {
      'UTC': 0,
      'Europe/London': 0,
      'Europe/Lisbon': 0,
      'Europe/Paris': 60,
      'Europe/Berlin': 60,
      'Europe/Rome': 60,
      'Europe/Amsterdam': 60,
      'Europe/Madrid': 60,
      'Europe/Warsaw': 60,
      'Europe/Athens': 120,
      'Europe/Helsinki': 120,
      'Europe/Moscow': 180,
      'Asia/Dubai': 240,
      'Asia/Karachi': 300,
      'Asia/Kolkata': 330,
      'Asia/Dhaka': 360,
      'Asia/Bangkok': 420,
      'Asia/Singapore': 480,
      'Asia/Tokyo': 540,
      'Australia/Sydney': 600,
      'Pacific/Auckland': 720,
      'America/Sao_Paulo': -180,
      'America/New_York': -300,
      'America/Chicago': -360,
      'America/Denver': -420,
      'America/Los_Angeles': -480,
      'America/Anchorage': -540,
      'Pacific/Honolulu': -600,
    };
    return _table[id] ?? 0;
  }
}