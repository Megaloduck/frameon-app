import 'dart:ui';
import 'dart:typed_data';
import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';

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
/// ## Packet Layout v1.5 (header = 52 bytes)
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
/// [52..N] RGB565 pixel data
/// [N+1-2] CRC-16/CCITT
/// ```
class FrameExporter {
  final int matrixWidth;
  final int matrixHeight;

  const FrameExporter({this.matrixWidth = 64, this.matrixHeight = 32});

  static const int _headerSize = 52; // v1.5

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
        // next-song preload packets never carry a clock descriptor.
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
      // Build clockFlags
      int clockFlags = _kClkPresent;
      if (clockLayer.format == ClockFormat.h12) clockFlags |= _kClkH12;
      if (clockLayer.showSeconds)               clockFlags |= _kClkSeconds;
      if (clockLayer.showDate)                  clockFlags |= _kClkDate;
      if (clockLayer.blinkColon)                clockFlags |= _kClkBlink;
      if (clockLayer.format == ClockFormat.h12) clockFlags |= _kClkAmPm;

      // Unix epoch seconds at commit time (always UTC).
      final int epochSec = clockCommitTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      // Timezone offset in minutes.
      //
      // 'local' is special: instead of looking up a fixed offset table entry
      // (which would yield 0 = UTC), we read the actual OS timezone offset
      // directly from the commit DateTime. clockCommitTime is created by
      // DateTime.now() on the host machine, so timeZoneOffset is the real
      // local UTC offset including DST.
      final int tzMin = _tzOffsetMinutes(clockLayer.timezone, clockCommitTime);

      packet[off++] = clockFlags;                                    // [29]
      bd.setUint32(off, epochSec,   Endian.big); off += 4;          // [30-33]
      bd.setInt16(off,  tzMin,      Endian.big); off += 2;          // [34-35]
      packet[off++] = _fontIdToByte(clockLayer.fontId);             // [36]
      packet[off++] = clockLayer.offset.dx.round().clamp(-128,127); // [37] int8
      packet[off++] = clockLayer.offset.dy.round().clamp(-128,127); // [38] int8
      packet[off++] = 0x00;                                         // [39] reserved

      // Per-element colors [40-51]
      bd.setUint16(off, _colorToRgb565(clockLayer.hoursColor),   Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.minutesColor),  Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.secondsColor),  Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.colonColor),    Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.dateColor),     Endian.big); off += 2;
      bd.setUint16(off, _colorToRgb565(clockLayer.ampmColor),     Endian.big); off += 2;
    } else {
      // No clock — zero out all 23 clock descriptor bytes.
      for (int i = 0; i < 23; i++) packet[off++] = 0x00;
    }

    assert(off == _headerSize, 'Header size mismatch: $off != $_headerSize');

    // Pixel payload
    for (final frame in timeline.frames) {
      assert(frame.data.length == bytesPerFrame);
      packet.setRange(off, off + bytesPerFrame, frame.data);
      off += bytesPerFrame;
    }

    // CRC-16/CCITT trailer
    bd.setUint16(off, _crc16(packet, 0, off), Endian.big);
    return packet;
  }

  static int _crc16(Uint8List data, int start, int end) {
    int crc = 0xFFFF;
    for (int i = start; i < end; i++) {
      crc ^= data[i] << 8;
      for (int j = 0; j < 8; j++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }
}

/// Returns the signed timezone offset in minutes for the given [timezone] ID.
///
/// For the special value `'local'`, the offset is derived directly from
/// [commitTime]'s [DateTime.timeZoneOffset] — this is the real OS-level local
/// offset including DST, and avoids the old bug where 'local' mapped to 0
/// (UTC+0) via the lookup table.
///
/// For all named timezones, a static fixed-offset table is used. Note these
/// are standard (non-DST) offsets — users in DST regions should pick the
/// explicit timezone that matches their current wall time if DST is a concern.
int _tzOffsetMinutes(String timezone, DateTime commitTime) {
  // 'local' — use the host machine's actual UTC offset at commit time.
  // This is always correct regardless of DST because DateTime.now() already
  // has the right timeZoneOffset baked in by the Dart runtime.
  if (timezone == 'local') {
    return commitTime.timeZoneOffset.inMinutes;
  }

  const Map<String, double> offsets = {
    'UTC':                  0,
    'Europe/London':        0,   'Europe/Lisbon':        0,
    'Europe/Paris':         1,   'Europe/Berlin':        1,
    'Europe/Rome':          1,   'Europe/Amsterdam':     1,
    'Europe/Madrid':        1,   'Europe/Warsaw':        1,
    'Europe/Athens':        2,   'Europe/Bucharest':     2,
    'Europe/Helsinki':      2,   'Europe/Istanbul':      3,
    'Europe/Moscow':        3,   'Asia/Riyadh':          3,
    'Asia/Dubai':           4,   'Asia/Baku':            4,
    'Asia/Kabul':           4.5, 'Asia/Karachi':         5,
    'Asia/Tashkent':        5,   'Asia/Kolkata':         5.5,
    'Asia/Colombo':         5.5, 'Asia/Kathmandu':       5.75,
    'Asia/Dhaka':           6,   'Asia/Almaty':          6,
    'Asia/Rangoon':         6.5, 'Asia/Bangkok':         7,
    'Asia/Jakarta':         7,   'Asia/Ho_Chi_Minh':     7,
    'Asia/Singapore':       8,   'Asia/Shanghai':        8,
    'Asia/Taipei':          8,   'Asia/Kuala_Lumpur':    8,
    'Asia/Manila':          8,   'Asia/Seoul':           9,
    'Asia/Tokyo':           9,   'Australia/Darwin':     9.5,
    'Australia/Brisbane':   10,  'Australia/Adelaide':   9.5,
    'Australia/Sydney':     10,  'Pacific/Auckland':     12,
    'Pacific/Fiji':         12,  'Pacific/Honolulu':    -10,
    'America/Anchorage':   -9,   'America/Los_Angeles': -8,
    'America/Denver':      -7,   'America/Phoenix':     -7,
    'America/Chicago':     -6,   'America/New_York':    -5,
    'America/Toronto':     -5,   'America/Halifax':     -4,
    'America/Sao_Paulo':   -3,   'America/Buenos_Aires':-3,
    'Atlantic/Azores':     -1,
  };

  final double hours = offsets[timezone] ?? 0;
  return (hours * 60).round();
}