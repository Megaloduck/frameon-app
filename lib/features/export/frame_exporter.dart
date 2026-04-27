import 'dart:typed_data';
import '../../engine/scene/layer.dart';
import '../../engine/scene/timeline.dart';

/// Packet header magic bytes.
const List<int> _kMagic = [0x46, 0x52, 0x4D]; // "FRM"

/// Protocol v1.3 flags.
const int _kVersionNormal = 0x02; // normal commit
const int _kVersionNext   = 0x4E; // 'N' — queue as next-song preload

/// Progress bar geometry per [SpotifyLayout].
///
/// These values must exactly match what [SpotifyWidget] bakes into every frame:
///
///   artAndText → bar right of the 32×32 art, 2 rows from bottom
///                barX = artSize+1 = 33,  barY = height-3 = 29,  barW = width-textX-1 = 30
///
///   textOnly   → full-width bar at very bottom
///                barX = 0,  barY = height-2 = 30,  barW = width-1 = 63
///
///   artOnly    → no progress bar (showProgress is ignored for artOnly)
///                barX = 0,  barY = 0,  barW = 0
///
/// barW = 0 tells the firmware to skip overdrawProgressBar entirely,
/// leaving album art completely untouched.
({int barX, int barY, int barW}) _barGeometry(
    SpotifyLayout layout, bool showProgress) {
  if (!showProgress) return (barX: 0, barY: 0, barW: 0);
  return switch (layout) {
    SpotifyLayout.artAndText => (barX: 33, barY: 29, barW: 30),
    SpotifyLayout.textOnly   => (barX: 0,  barY: 30, barW: 64),
    SpotifyLayout.artOnly    => (barX: 0,  barY: 0,  barW: 0),
  };
}

/// The [FrameExporter] converts a [Timeline] into the binary packet format
/// transmitted to the LED matrix device over Serial.
///
/// ## Packet Layout v1.3 (header = 28 bytes)
///
/// ```
/// [3]  Magic bytes: 0x46 0x52 0x4D  ("FRM")
/// [1]  Flags:       0x02 = normal  |  0x4E = next-song preload
/// [2]  Frame count         (uint16 BE)
/// [2]  Frame width         (uint16 BE)
/// [2]  Frame height        (uint16 BE)
/// [2]  Frame duration ms   (uint16 BE)
/// [4]  Total payload bytes (uint32 BE)
/// [4]  startPositionMs     (uint32 BE)
/// [4]  trackDurationMs     (uint32 BE)
/// [1]  barX                (uint8)   — progress bar left edge
/// [1]  barY                (uint8)   — progress bar top edge
/// [1]  barW                (uint8)   — bar width; 0 = no bar (artOnly)
/// [1]  reserved            (uint8)   — 0x00
/// [N]  RGB565 pixel data
/// [2]  CRC-16/CCITT
/// ```
///
/// barX/barY/barW let the firmware know exactly where to overdraw the
/// real-time progress bar without touching album art pixels.
class FrameExporter {
  final int matrixWidth;
  final int matrixHeight;

  const FrameExporter({this.matrixWidth = 64, this.matrixHeight = 32});

  static const int _headerSize = 28; // v1.3

  /// Build a normal-commit packet.
  ///
  /// [layout] and [showProgress] are used to derive bar geometry so the
  /// firmware overdraw matches what [SpotifyWidget] baked into the frames.
  /// Pass [layout] = null (default) and [showProgress] = false for non-Spotify
  /// scenes — firmware will skip bar overdraw entirely.
  Uint8List export(
    Timeline timeline, {
    int startPositionMs = 0,
    int trackDurationMs = 0,
    SpotifyLayout? layout,
    bool showProgress = false,
  }) =>
      _build(
        timeline,
        flags: _kVersionNormal,
        startPositionMs: startPositionMs,
        trackDurationMs: trackDurationMs,
        layout: layout,
        showProgress: showProgress,
      );

  /// Build a next-song preload packet (firmware flag 0x4E).
  Uint8List exportNext(
    Timeline timeline, {
    int startPositionMs = 0,
    int trackDurationMs = 0,
    SpotifyLayout? layout,
    bool showProgress = false,
  }) =>
      _build(
        timeline,
        flags: _kVersionNext,
        startPositionMs: startPositionMs,
        trackDurationMs: trackDurationMs,
        layout: layout,
        showProgress: showProgress,
      );

  Uint8List _build(
    Timeline timeline, {
    required int flags,
    required int startPositionMs,
    required int trackDurationMs,
    SpotifyLayout? layout,
    bool showProgress = false,
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

    // Derive bar geometry — (0,0,0) means no bar
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
    bd.setUint16(off, frameCount,       Endian.big); off += 2;
    bd.setUint16(off, matrixWidth,      Endian.big); off += 2;
    bd.setUint16(off, matrixHeight,     Endian.big); off += 2;
    bd.setUint16(off, durationMs,       Endian.big); off += 2;
    bd.setUint32(off, payloadBytes,     Endian.big); off += 4;

    // Progress-bar prediction (v1.2+)
    bd.setUint32(off, startPositionMs,  Endian.big); off += 4;
    bd.setUint32(off, trackDurationMs,  Endian.big); off += 4;

    // Bar geometry (v1.3)
    packet[off++] = bar.barX;
    packet[off++] = bar.barY;
    packet[off++] = bar.barW;
    packet[off++] = 0x00; // reserved

    assert(off == _headerSize, 'Header size mismatch: $off != $_headerSize');

    // Pixel payload
    for (final frame in timeline.frames) {
      assert(frame.data.length == bytesPerFrame);
      packet.setRange(off, off + bytesPerFrame, frame.data);
      off += bytesPerFrame;
    }

    // CRC
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