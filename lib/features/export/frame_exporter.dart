import 'dart:typed_data';
import '../engine/scene/timeline.dart';

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
/// [3]  Magic bytes: 0x46 0x52 0x4D ("FRM")
/// [1]  Protocol version: 0x01
/// [2]  Frame count (uint16 big-endian)
/// [2]  Frame width in pixels (uint16 big-endian)
/// [2]  Frame height in pixels (uint16 big-endian)
/// [2]  Frame duration in ms (uint16 big-endian) — applies to ALL frames
/// [4]  Total payload bytes (uint32 big-endian)
/// [N]  Raw RGB565 frame data (frame_count * width * height * 2 bytes)
/// [2]  CRC-16/CCITT checksum over header + payload
/// ```
///
/// Total header size: 16 bytes.
class FrameExporter {
  final int matrixWidth;
  final int matrixHeight;

  const FrameExporter({
    this.matrixWidth = 64,
    this.matrixHeight = 32,
  });

  /// Build the full transmission packet from [timeline].
  Uint8List export(Timeline timeline) {
    if (timeline.frameCount == 0) {
      throw StateError('Cannot export an empty timeline.');
    }

    final int frameCount = timeline.frameCount;
    final int frameDurationMs = timeline.frames.first.durationMs;
    final int pixelsPerFrame = matrixWidth * matrixHeight;
    final int bytesPerFrame = pixelsPerFrame * 2; // RGB565 = 2 bytes/pixel
    final int payloadBytes = frameCount * bytesPerFrame;

    // Header: 16 bytes
    const int headerSize = 16;
    final int totalSize = headerSize + payloadBytes + 2; // +2 for CRC
    final Uint8List packet = Uint8List(totalSize);
    final ByteData bd = ByteData.sublistView(packet);

    int offset = 0;

    // Magic
    for (final b in _kMagic) {
      packet[offset++] = b;
    }

    // Version
    packet[offset++] = _kVersion;

    // Frame count (uint16 BE)
    bd.setUint16(offset, frameCount, Endian.big);
    offset += 2;

    // Width (uint16 BE)
    bd.setUint16(offset, matrixWidth, Endian.big);
    offset += 2;

    // Height (uint16 BE)
    bd.setUint16(offset, matrixHeight, Endian.big);
    offset += 2;

    // Duration ms (uint16 BE)
    bd.setUint16(offset, frameDurationMs, Endian.big);
    offset += 2;

    // Payload size (uint32 BE)
    bd.setUint32(offset, payloadBytes, Endian.big);
    offset += 4;

    assert(offset == headerSize, 'Header size mismatch');

    // Pixel payload
    for (final frame in timeline.frames) {
      assert(
        frame.data.length == bytesPerFrame,
        'Frame data length mismatch: '
        'expected $bytesPerFrame, got ${frame.data.length}',
      );
      packet.setRange(offset, offset + bytesPerFrame, frame.data);
      offset += bytesPerFrame;
    }

    // CRC-16/CCITT over [0..offset)
    final int crc = _crc16(packet, 0, offset);
    bd.setUint16(offset, crc, Endian.big);

    return packet;
  }

  /// Parse and validate a received packet. Returns the [Timeline] or throws.
  Timeline import(Uint8List packet) {
    if (packet.length < 18) {
      throw FormatException('Packet too short: ${packet.length} bytes');
    }

    // Verify magic
    if (packet[0] != _kMagic[0] ||
        packet[1] != _kMagic[1] ||
        packet[2] != _kMagic[2]) {
      throw FormatException('Invalid magic bytes');
    }

    final ByteData bd = ByteData.sublistView(packet);
    final int frameCount = bd.getUint16(4, Endian.big);
    final int width = bd.getUint16(6, Endian.big);
    final int height = bd.getUint16(8, Endian.big);
    final int durationMs = bd.getUint16(10, Endian.big);
    final int payloadBytes = bd.getUint32(12, Endian.big);
    final int expectedTotal = 16 + payloadBytes + 2;

    if (packet.length != expectedTotal) {
      throw FormatException(
          'Packet length mismatch: expected $expectedTotal, got ${packet.length}');
    }

    // Verify CRC
    final int storedCrc = bd.getUint16(packet.length - 2, Endian.big);
    final int computedCrc = _crc16(packet, 0, packet.length - 2);
    if (storedCrc != computedCrc) {
      throw FormatException(
          'CRC mismatch: stored 0x${storedCrc.toRadixString(16)}, '
          'computed 0x${computedCrc.toRadixString(16)}');
    }

    final int bytesPerFrame = width * height * 2;
    final timeline = Timeline();
    int offset = 16;
    for (int i = 0; i < frameCount; i++) {
      final data = Uint8List.fromList(
          packet.sublist(offset, offset + bytesPerFrame));
      timeline.addFrame(Frame(data: data, durationMs: durationMs));
      offset += bytesPerFrame;
    }
    return timeline;
  }

  // ── CRC-16/CCITT (polynomial 0x1021, init 0xFFFF) ────────────────────────

  int _crc16(Uint8List data, int start, int end) {
    int crc = 0xFFFF;
    for (int i = start; i < end; i++) {
      crc ^= data[i] << 8;
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}