import 'dart:typed_data';
import '../../engine/scene/timeline.dart';

/// Packet header magic bytes expected by the FrameOn firmware.
const List<int> _kMagic = [0x46, 0x52, 0x4D]; // "FRM"

/// Protocol version byte.
const int _kVersion = 0x01;

/// The [FrameExporter] converts a [Timeline] into the binary packet format
/// transmitted to the LED matrix device over Serial / WebSocket.
///
/// ## Packet Layout
///
/// ```
/// [3]  Magic bytes: 0x46 0x52 0x4D  ("FRM")
/// [1]  Protocol version: 0x01
/// [2]  Frame count         (uint16 BE)
/// [2]  Frame width         (uint16 BE)
/// [2]  Frame height        (uint16 BE)
/// [2]  Frame duration ms   (uint16 BE) — uniform across all frames
/// [4]  Total payload bytes (uint32 BE)
/// [N]  Raw RGB565 pixel data
/// [2]  CRC-16/CCITT over everything above
/// ```
class FrameExporter {
  final int matrixWidth;
  final int matrixHeight;

  const FrameExporter({this.matrixWidth = 64, this.matrixHeight = 32});

  /// Build the full transmission packet from [timeline].
  Uint8List export(Timeline timeline) {
    if (timeline.frameCount == 0) {
      throw StateError('Cannot export an empty timeline.');
    }

    final int frameCount    = timeline.frameCount;
    final int durationMs    = timeline.frames.first.durationMs;
    final int bytesPerFrame = matrixWidth * matrixHeight * 2;
    final int payloadBytes  = frameCount * bytesPerFrame;

    const int headerSize = 16;
    final Uint8List packet = Uint8List(headerSize + payloadBytes + 2);
    final ByteData bd = ByteData.sublistView(packet);

    int off = 0;

    // Magic + version
    packet[off++] = _kMagic[0];
    packet[off++] = _kMagic[1];
    packet[off++] = _kMagic[2];
    packet[off++] = _kVersion;

    bd.setUint16(off, frameCount,    Endian.big); off += 2;
    bd.setUint16(off, matrixWidth,   Endian.big); off += 2;
    bd.setUint16(off, matrixHeight,  Endian.big); off += 2;
    bd.setUint16(off, durationMs,    Endian.big); off += 2;
    bd.setUint32(off, payloadBytes,  Endian.big); off += 4;

    assert(off == headerSize, 'Header size mismatch');

    for (final frame in timeline.frames) {
      assert(frame.data.length == bytesPerFrame);
      packet.setRange(off, off + bytesPerFrame, frame.data);
      off += bytesPerFrame;
    }

    bd.setUint16(off, _crc16(packet, 0, off), Endian.big);
    return packet;
  }

  /// Parse and validate a received packet. Returns a [Timeline] or throws.
  Timeline import(Uint8List packet) {
    if (packet.length < 18) {
      throw FormatException('Packet too short (${packet.length} bytes)');
    }
    if (packet[0] != _kMagic[0] ||
        packet[1] != _kMagic[1] ||
        packet[2] != _kMagic[2]) {
      throw FormatException('Invalid magic bytes');
    }

    final ByteData bd = ByteData.sublistView(packet);
    final int frameCount   = bd.getUint16(4,  Endian.big);
    final int width        = bd.getUint16(6,  Endian.big);
    final int height       = bd.getUint16(8,  Endian.big);
    final int durationMs   = bd.getUint16(10, Endian.big);
    final int payloadBytes = bd.getUint32(12, Endian.big);

    final int expected = 16 + payloadBytes + 2;
    if (packet.length != expected) {
      throw FormatException(
          'Length mismatch: expected $expected, got ${packet.length}');
    }

    final int stored   = bd.getUint16(packet.length - 2, Endian.big);
    final int computed = _crc16(packet, 0, packet.length - 2);
    if (stored != computed) {
      throw FormatException('CRC mismatch: '
          'stored 0x${stored.toRadixString(16)}, '
          'computed 0x${computed.toRadixString(16)}');
    }

    final int bpf = width * height * 2;
    final timeline = Timeline();
    int off = 16;
    for (int i = 0; i < frameCount; i++) {
      timeline.addFrame(Frame(
        data: Uint8List.fromList(packet.sublist(off, off + bpf)),
        durationMs: durationMs,
      ));
      off += bpf;
    }
    return timeline;
  }

  // ── CRC-16/CCITT (poly 0x1021, init 0xFFFF) ──────────────────────────────

  int _crc16(Uint8List data, int start, int end) {
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