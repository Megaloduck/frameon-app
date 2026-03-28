import 'dart:typed_data';

/// A single rendered frame ready for output.
class Frame {
  /// RGB565-encoded pixel data (width * height * 2 bytes).
  final Uint8List data;

  /// Display duration in milliseconds.
  final int durationMs;

  const Frame({required this.data, required this.durationMs});
}

/// The [Timeline] accumulates rendered [Frame]s produced by the engine
/// and provides playback utilities for the preview and the exporter.
///
/// It is mutable — frames are appended during rendering, then consumed
/// for preview / export.
class Timeline {
  final List<Frame> _frames = [];

  /// All frames in render order.
  List<Frame> get frames => List.unmodifiable(_frames);

  /// Total number of frames.
  int get frameCount => _frames.length;

  /// Total animation duration in milliseconds.
  int get totalDurationMs =>
      _frames.fold(0, (sum, f) => sum + f.durationMs);

  /// Total byte payload (all frame data concatenated).
  int get totalBytes => _frames.fold(0, (sum, f) => sum + f.data.length);

  /// Frames per second (computed from first frame duration; fallback 10 fps).
  double get fps {
    if (_frames.isEmpty) return 10;
    return 1000 / _frames.first.durationMs;
  }

  // ── Mutation ────────────────────────────────────────────────────────────

  void addFrame(Frame frame) => _frames.add(frame);

  void clear() => _frames.clear();

  // ── Playback ────────────────────────────────────────────────────────────

  /// Return the frame index active at [elapsedMs] within a looping animation.
  int frameIndexAt(int elapsedMs) {
    if (_frames.isEmpty) return 0;
    final int loopMs = totalDurationMs;
    if (loopMs == 0) return 0;
    int t = elapsedMs % loopMs;
    for (int i = 0; i < _frames.length; i++) {
      t -= _frames[i].durationMs;
      if (t <= 0) return i;
    }
    return _frames.length - 1;
  }

  Frame? frameAt(int elapsedMs) {
    if (_frames.isEmpty) return null;
    return _frames[frameIndexAt(elapsedMs)];
  }

  // ── Export ───────────────────────────────────────────────────────────────

  /// Concatenate all frame byte payloads into a single flat [Uint8List].
  /// Used by the device protocol layer to build the transmission packet.
  Uint8List toFlatBytes() {
    final int total = totalBytes;
    final Uint8List out = Uint8List(total);
    int offset = 0;
    for (final f in _frames) {
      out.setRange(offset, offset + f.data.length, f.data);
      offset += f.data.length;
    }
    return out;
  }
}