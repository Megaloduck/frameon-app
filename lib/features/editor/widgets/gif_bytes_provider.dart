import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GifBytesNotifier
//
// Stores the raw image bytes for every GIF/image layer that has been uploaded.
// Keyed by the layer's cache key (file path on desktop, filename on web).
//
// Why separate from MatrixRenderer's asset cache?
// The renderer cache holds decoded DecodedFrame objects (ARGB pixels).
// We also need the original Uint8List to display a thumbnail via Image.memory.
// ─────────────────────────────────────────────────────────────────────────────

class GifBytesNotifier extends Notifier<Map<String, Uint8List>> {
  @override
  Map<String, Uint8List> build() => {};

  void set(String key, Uint8List bytes) {
    state = {...state, key: bytes};
  }

  void remove(String key) {
    final next = Map<String, Uint8List>.from(state)..remove(key);
    state = next;
  }

  Uint8List? get(String key) => state[key];
}

final gifBytesProvider =
    NotifierProvider<GifBytesNotifier, Map<String, Uint8List>>(
  GifBytesNotifier.new,
);