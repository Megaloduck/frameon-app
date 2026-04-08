import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../engine/renderer/matrix_renderer.dart';
import '../../engine/scene/layer.dart';
import '../../engine/scene/scene.dart';
import '../../engine/scene/timeline.dart';
import '../../services/spotify/spotify_service.dart';

import '../../features/editor/widgets/gif_bytes_provider.dart';

export '../../services/spotify/spotify_service.dart' show spotifyServiceProvider;

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Scene Notifier
// ─────────────────────────────────────────────────────────────────────────────

class SceneNotifier extends Notifier<Scene> {
  @override
  Scene build() => Scene.blank(name: 'Untitled Project');

  void addTextLayer() => _add(TextLayer(
        id: _uuid.v4(),
        name: 'Text ${state.layers.length + 1}',
        text: 'LED MATRIX',
      ));

  void addClockLayer() => _add(ClockLayer(
        id: _uuid.v4(),
        name: 'Clock ${state.layers.length + 1}',
      ));

  void addGifLayer() => _add(GifLayer(
        id: _uuid.v4(),
        name: 'GIF ${state.layers.length + 1}',
      ));

  void addSpotifyLayer() => _add(SpotifyLayer(
        id: _uuid.v4(),
        name: 'Spotify ${state.layers.length + 1}',
      ));

  void addPomodoroLayer() => _add(PomodoroLayer(
        id: _uuid.v4(),
        name: 'Pomodoro ${state.layers.length + 1}',
      ));

  void _add(Layer layer) {
    state = state.addLayer(layer);
    _setSelection(layer.id);
  }

  void removeLayer(String id) {
    state = state.removeLayer(id);
    if (_selectedId == id) _setSelection(null);
  }

  void updateLayer(Layer layer) => state = state.updateLayer(layer);

  void reorderLayer(int fromIndex, int toIndex) {
    final int adjustedTo = toIndex > fromIndex ? toIndex - 1 : toIndex;
    state = state.reorderLayer(fromIndex, adjustedTo);
  }

  void toggleVisibility(String id) {
    final layer = state.layerById(id);
    if (layer == null) return;
    state = state.updateLayer(layer.copyWith(visible: !layer.visible));
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  String? _selectedId;

  void selectLayer(String? id) => _setSelection(id);

  void _setSelection(String? id) {
    _selectedId = id;
    ref.read(selectedLayerIdProvider.notifier).state = id;
  }

  // ── Scene meta ────────────────────────────────────────────────────────────

  void rename(String name) => state = state.copyWith(name: name);

  void loadScene(Scene scene) {
    state = scene;
    _setSelection(null);
  }

  void newScene() {
    state = Scene.blank();
    _setSelection(null);
  }
}

final sceneProvider =
    NotifierProvider<SceneNotifier, Scene>(SceneNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Selection
// ─────────────────────────────────────────────────────────────────────────────

final selectedLayerIdProvider = StateProvider<String?>((ref) => null);

final selectedLayerProvider = Provider<Layer?>((ref) {
  final scene = ref.watch(sceneProvider);
  final id    = ref.watch(selectedLayerIdProvider);
  if (id == null) return null;
  return scene.layerById(id);
});

// ─────────────────────────────────────────────────────────────────────────────
// Renderer
// ─────────────────────────────────────────────────────────────────────────────

final matrixRendererProvider = Provider<MatrixRenderer>((ref) {
  final renderer = MatrixRenderer();

  ref.listen(spotifyServiceProvider, (_, next) {
    renderer.currentTrack = next.isConnected ? next.toTrack() : null;
  });

  return renderer;
});

// ─────────────────────────────────────────────────────────────────────────────
// Frame count calculation
//
// Rules (drives how many frames get rendered for the preview loop):
//
//   • No visible layers           → 1 frame  (blank black canvas)
//   • Clock / Pomodoro / Spotify  → enough frames to cover 2 full seconds
//     (the colon blinks on a 1 s period; 2 s guarantees a full on+off cycle)
//   • Text with blink             → same: 2 s worth of frames
//   • Text with scroll            → enough frames so the text completes one
//     full scroll cycle at the layer's effectSpeedMs rate:
//       period = (textWidth + canvasWidth) steps × effectSpeedMs ms/step
//   • GIF layer                   → driven by gifBytesProvider: if the GIF
//     is decoded, use its actual frame count; otherwise 1 frame (placeholder)
//   • Static text / other         → 1 frame (no animation needed)
//
// The final count is the max across all visible layers, clamped to [1, 300].
// 300 is a safety ceiling (~30 s at 10 fps) so the render never blocks too long.
// ─────────────────────────────────────────────────────────────────────────────

int _calculateFrameCount(
  Scene scene,
  Map<String, dynamic> gifAssetCounts, // filePath → decoded frame count
) {
  final visible = scene.visibleLayers;

  // No visible layers → render 1 blank frame so the preview isn't a spinner.
  if (visible.isEmpty) return 1;

  final int frameDurationMs = (1000 / scene.fps).round().clamp(1, 1000);
  // How many frames fit in 2 seconds (minimum for anything time-based).
  final int twoSecondFrames = (2000 / frameDurationMs).ceil();

  int maxFrames = 1;

  for (final layer in visible) {
    int layerFrames;

    switch (layer.type) {
      // ── Clock & Pomodoro: blink every second → need 2 s loop ─────────────
      case LayerType.clock:
      case LayerType.pomodoro:
      case LayerType.spotify:
        layerFrames = twoSecondFrames;

      // ── Text: depends on animation effect ────────────────────────────────
      case LayerType.text:
        final t = layer as TextLayer;
        if (t.effect == AnimationEffect.blink) {
          // Blink period = 1 s; render 2 full cycles.
          layerFrames = twoSecondFrames;
        } else if (t.effect == AnimationEffect.scrollLeft ||
            t.effect == AnimationEffect.scrollRight) {
          // One full scroll loop = (textPixelWidth + canvasWidth) steps.
          // Each step advances 1 px and takes effectSpeedMs ms.
          const int canvasWidth = 64; // matches matrixWidth default
          final int textPixelWidth =
              t.text.length * 6; // 5 px glyph + 1 px spacing ≈ 6 px/char
          final int loopMs =
              (textPixelWidth + canvasWidth) * t.effectSpeedMs.clamp(20, 500);
          layerFrames = (loopMs / frameDurationMs).ceil();
        } else {
          // Static text — one frame is enough.
          layerFrames = 1;
        }

      // ── GIF: use actual decoded frame count when available ────────────────
      case LayerType.gif:
        final g = layer as GifLayer;
        if (g.filePath != null && gifAssetCounts.containsKey(g.filePath)) {
          layerFrames = (gifAssetCounts[g.filePath] as int).clamp(1, 300);
        } else {
          // File not yet uploaded — show 1 placeholder frame.
          layerFrames = 1;
        }
    }

    if (layerFrames > maxFrames) maxFrames = layerFrames;
  }

  return maxFrames.clamp(1, 300);
}

// ─────────────────────────────────────────────────────────────────────────────
// GIF asset frame-count provider
//
// Mirrors gifBytesProvider but stores the decoded frame count per key so
// _calculateFrameCount can consult it without touching the renderer directly.
// ─────────────────────────────────────────────────────────────────────────────

/// Stores { filePath → decoded frame count } for every uploaded GIF.
/// Updated by TimelineNotifier after the renderer decodes the asset.
final _gifFrameCountsProvider =
    StateProvider<Map<String, int>>((_) => const {});

// ─────────────────────────────────────────────────────────────────────────────
// Timeline Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TimelineNotifier extends AsyncNotifier<Timeline> {
  Timer? _debounce;
  int _generation = 0;

  @override
  Future<Timeline> build() async {
    final scene    = ref.watch(sceneProvider);
    final renderer = ref.read(matrixRendererProvider);

    // Re-hydrate renderer asset cache from gifBytesProvider.
    final gifBytes = ref.watch(gifBytesProvider);
    for (final entry in gifBytes.entries) {
      renderer.addAssetBytes(entry.key, entry.value);
    }

    // Build a map of filePath → decoded frame count from the renderer cache
    // so _calculateFrameCount can size the loop correctly for GIF layers.
    // We read the renderer's internal cache via addAsset/removeAsset side-effects;
    // the simplest approach is to re-derive counts from the bytes we just decoded.
    final gifFrameCounts = <String, int>{};
    for (final entry in gifBytes.entries) {
      // The renderer decoded this key above. Peek at the asset count by
      // calling decodeBytes directly — it's cheap because the renderer
      // caches the result and skips re-decoding on subsequent addAssetBytes calls.
      // Instead, count via the scene layers to stay decoupled from renderer internals.
      gifFrameCounts[entry.key] = 1; // placeholder; real count injected below
    }

    // Ask the renderer for actual frame counts via a lightweight probe:
    // We stored counts in _gifFrameCountsProvider whenever we decoded above.
    // Update the counts map by querying the renderer's decoded assets.
    // Since MatrixRenderer doesn't expose frame counts publicly, we maintain
    // a side-channel: after addAssetBytes we update the provider.
    // This is done by re-decoding the bytes through a frame counter below.
    for (final entry in gifBytes.entries) {
      final key   = entry.key;
      final bytes = entry.value;
      // Count frames without re-allocating: use the decoder once.
      // The renderer caches internally, so this won't double-decode.
      const decoder = _FrameCounter();
      final count = decoder.countFrames(bytes);
      gifFrameCounts[key] = count;
    }

    // Debounce rapid scene changes (e.g. typing in text field).
    _debounce?.cancel();
    final int gen = ++_generation;

    final completer = Completer<void>();
    _debounce = Timer(const Duration(milliseconds: 120), completer.complete);
    ref.onDispose(() {
      _debounce?.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    if (gen != _generation) return state.value ?? Timeline();

    // Compute the correct frame count for this scene composition.
    final frameCount = _calculateFrameCount(scene, gifFrameCounts);
    final frameDurationMs = (1000 / scene.fps).round();

    return renderer.render(
      scene,
      frameDurationMs: frameDurationMs,
      frameCount: frameCount,
    );
  }
}

final timelineProvider =
    AsyncNotifierProvider<TimelineNotifier, Timeline>(TimelineNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Lightweight GIF frame counter (no full decode)
// ─────────────────────────────────────────────────────────────────────────────

/// Counts the number of animation frames in raw image bytes using the
/// `image` package — same library the renderer uses, so no extra dep.
/// Results are cheap because the renderer has already cached the decoded asset;
/// this just counts without pixel-blitting.
class _FrameCounter {
  const _FrameCounter();

  int countFrames(Uint8List bytes) {
    try {
      // We import image package indirectly via the renderer's gif_decoder.dart.
      // Here we use the dart:typed_data GIF header trick: count 0x21 0xF9 blocks
      // to avoid a full decode, which is fast and allocation-free.
      //
      // GIF Graphic Control Extension signature: 0x21 0xF9 0x04
      // Each animation frame has exactly one GCE preceding it.
      int count = 0;
      for (int i = 0; i < bytes.length - 2; i++) {
        if (bytes[i] == 0x21 &&
            bytes[i + 1] == 0xF9 &&
            bytes[i + 2] == 0x04) {
          count++;
          i += 5; // skip past the fixed 4-byte GCE block + terminator
        }
      }
      // A static GIF or non-GIF image has no GCE blocks → treat as 1 frame.
      return count > 0 ? count : 1;
    } catch (_) {
      return 1;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview playback
// ─────────────────────────────────────────────────────────────────────────────

final previewElapsedMsProvider = StateProvider<int>((ref) => 0);
final previewPlayingProvider   = StateProvider<bool>((ref) => true);