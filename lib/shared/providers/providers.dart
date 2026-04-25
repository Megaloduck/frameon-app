import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../engine/renderer/matrix_renderer.dart';
import '../../engine/renderer/pixel_buffer.dart';
import '../../engine/scene/layer.dart';
import '../../engine/scene/scene.dart';
import '../../engine/scene/timeline.dart';
import '../../services/spotify/spotify_service.dart';
import '../../services/pomodoro/pomodoro_service.dart';
import '../../services/autosave/autosave_service.dart';

import '../../features/editor/toolkits/gif_bytes_provider.dart';
import 'time_service.dart';

export '../../services/spotify/spotify_service.dart'
    show spotifyServiceProvider, SpotifyState, SpotifyConnectionStatus, SpotifyServiceNotifier;
export '../../services/pomodoro/pomodoro_service.dart' show pomodoroServiceProvider;

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
    ref.read(selectedLayerIdProvider.notifier).set(id);
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
    // Erase the autosave slot so re-launching doesn't restore the old scene.
    ref.read(autosaveServiceProvider).clear();
  }
}

final sceneProvider =
    NotifierProvider<SceneNotifier, Scene>(SceneNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Selection
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedLayerIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final selectedLayerIdProvider =
    NotifierProvider<_SelectedLayerIdNotifier, String?>(
        _SelectedLayerIdNotifier.new);

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

  // Wire Spotify track into renderer whenever state changes.
  ref.listen(spotifyServiceProvider, (_, next) {
    renderer.currentTrack = next.isConnected ? next.toTrack() : null;
  });

  // Wire Pomodoro timer state into renderer.
  ref.listen(pomodoroServiceProvider, (_, next) {
    renderer.currentPomodoroState = next;
  });

  return renderer;
});

// ─────────────────────────────────────────────────────────────────────────────
// Live preview frame provider
//
// Renders exactly ONE frame at the current elapsedMs directly into a
// PixelBuffer. No frame count estimation, no cap, no encode/decode round-trip.
//
// This is what drives the matrix preview widget. It re-computes whenever:
//   - elapsedMs ticks (every ~16ms via the Ticker)
//   - the scene changes (layer added/removed/edited)
//   - Spotify state changes (track, art, progress)
//   - Pomodoro state changes (remaining time, phase)
//   - clock ticks (every second via timeServiceProvider)
//   - GIF bytes change (new file uploaded)
// ─────────────────────────────────────────────────────────────────────────────

final previewFrameProvider = Provider<PixelBuffer>((ref) {
  final scene     = ref.watch(sceneProvider);
  final elapsedMs = ref.watch(previewElapsedMsProvider);
  final renderer  = ref.read(matrixRendererProvider);

  final visible = scene.visibleLayers;

  // Wire live service state into renderer before rendering this frame.
  if (visible.any((l) => l.type == LayerType.spotify)) {
    final spotify = ref.watch(spotifyServiceProvider);
    renderer.currentTrack = spotify.isConnected ? spotify.toTrack() : null;
  }

  if (visible.any((l) =>
      l.type == LayerType.clock || l.type == LayerType.pomodoro)) {
    // Watch both so a change in either triggers a re-render.
    ref.watch(timeServiceProvider);
    renderer.currentPomodoroState = ref.watch(pomodoroServiceProvider);
  }

  // Re-hydrate GIF assets into the renderer whenever the byte cache changes.
  final gifBytes = ref.watch(gifBytesProvider);
  for (final entry in gifBytes.entries) {
    renderer.addAssetBytes(entry.key, entry.value);
  }

  return renderer.renderFrameBuffer(scene, elapsedMs);
});

// ─────────────────────────────────────────────────────────────────────────────
// Frame count calculation — used only for device export (Timeline)
//
// For the preview, frame count is irrelevant — previewFrameProvider renders
// one frame at the current elapsedMs with no cap.
//
// For the device export we still need a loop length so the ESP32 knows when
// to wrap. We calculate the worst-case loop duration across all visible layers.
// ─────────────────────────────────────────────────────────────────────────────

int _calculateFrameCount(
  Scene scene,
  Map<String, dynamic> gifAssetCounts,
) {
  final visible = scene.visibleLayers;
  if (visible.isEmpty) return 1;

  final int frameDurationMs = (1000 / scene.fps).round().clamp(1, 1000);
  final int twoSecondFrames = (2000 / frameDurationMs).ceil();

  int maxFrames = 1;

  for (final layer in visible) {
    int layerFrames;

    switch (layer.type) {
      case LayerType.clock:
      case LayerType.pomodoro:
        // Clock and Pomodoro update every second; 2 seconds covers a full
        // blink cycle. On the device these will be stale — see architecture note.
        layerFrames = twoSecondFrames;

      case LayerType.spotify:
        final sp = layer as SpotifyLayer;
        // Viewport width: artAndText uses ~31px (64 - 32art - 1gap), else 64.
        final int viewportW = sp.layout == SpotifyLayout.artAndText ? 31 : 64;
        int maxSpotifyFrames = twoSecondFrames;

        for (final pair in [
          (sp.titleEffect,  sp.titleEffectSpeedMs),
          (sp.artistEffect, sp.artistEffectSpeedMs),
        ]) {
          final effect  = pair.$1;
          final speedMs = pair.$2;
          if (effect == AnimationEffect.scrollLeft ||
              effect == AnimationEffect.scrollRight) {
            // bufW = estimatedContentW + viewportW.
            // One full loop takes bufW * speedMs milliseconds.
            // 250px covers titles/artists up to ~40 chars in Polymorph font.
            const int estimatedContentW = 250;
            final int bufW   = estimatedContentW + viewportW;
            final int loopMs = bufW * speedMs;
            final int frames = (loopMs / frameDurationMs).ceil();
            if (frames > maxSpotifyFrames) maxSpotifyFrames = frames;
          }
        }
        layerFrames = maxSpotifyFrames;

      case LayerType.text:
        final t = layer as TextLayer;
        if (t.effect == AnimationEffect.blink) {
          layerFrames = twoSecondFrames;
        } else if (t.effect == AnimationEffect.scrollLeft ||
            t.effect == AnimationEffect.scrollRight) {
          const int canvasWidth = 64;
          final int textPixelWidth = t.text.length * 6;
          final int loopMs =
              (textPixelWidth + canvasWidth) * t.effectSpeedMs.clamp(20, 500);
          layerFrames = (loopMs / frameDurationMs).ceil();
        } else {
          layerFrames = 1;
        }

      case LayerType.gif:
        final g = layer as GifLayer;
        if (g.filePath != null && gifAssetCounts.containsKey(g.filePath)) {
          layerFrames = (gifAssetCounts[g.filePath] as int).clamp(1, 300);
        } else {
          layerFrames = 1;
        }
    }

    if (layerFrames > maxFrames) maxFrames = layerFrames;
  }

  // Cap at 300 frames for the device export packet size.
  // The preview is NOT subject to this cap.
  return maxFrames.clamp(1, 300);
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline Notifier — device export only
//
// This provider pre-renders a fixed loop of RGB565 frames for sending to the
// ESP32. It intentionally does NOT watch timeServiceProvider or Pomodoro/Spotify
// live state — those change constantly and would cause the entire timeline to
// re-render every second, which is wasteful now that the preview is decoupled.
//
// The timeline re-renders when:
//   - The scene structure changes (layers added/removed/edited)
//   - GIF bytes change
//   - The user explicitly triggers a re-export
//
// For the output panel stats display it remains reactive to scene changes.
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

    final gifFrameCounts = <String, int>{};
    for (final entry in gifBytes.entries) {
      const decoder = _FrameCounter();
      gifFrameCounts[entry.key] = decoder.countFrames(entry.value);
    }

    // Snapshot current live state at export time (not watched — intentional).
    // The exported timeline captures whatever is playing right now on the device.
    final spotifyState = ref.read(spotifyServiceProvider);
    renderer.currentTrack =
        spotifyState.isConnected ? spotifyState.toTrack() : null;
    renderer.currentPomodoroState = ref.read(pomodoroServiceProvider);

    // Debounce rapid scene changes (e.g. typing in a text field).
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

    final frameCount      = _calculateFrameCount(scene, gifFrameCounts);
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
// Lightweight GIF frame counter
// ─────────────────────────────────────────────────────────────────────────────

class _FrameCounter {
  const _FrameCounter();

  int countFrames(Uint8List bytes) {
    try {
      int count = 0;
      for (int i = 0; i < bytes.length - 2; i++) {
        if (bytes[i] == 0x21 &&
            bytes[i + 1] == 0xF9 &&
            bytes[i + 2] == 0x04) {
          count++;
          i += 5;
        }
      }
      return count > 0 ? count : 1;
    } catch (_) {
      return 1;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview playback state
// ─────────────────────────────────────────────────────────────────────────────

/// Continuously increasing elapsed time in milliseconds, driven by the
/// Ticker in MatrixPreview. previewFrameProvider watches this to trigger
/// re-renders at display refresh rate.

class _PreviewElapsedMsNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int ms) => state = ms;
}

final previewElapsedMsProvider =
    NotifierProvider<_PreviewElapsedMsNotifier, int>(
        _PreviewElapsedMsNotifier.new);

class _PreviewPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool playing) => state = playing;
}

final previewPlayingProvider =
    NotifierProvider<_PreviewPlayingNotifier, bool>(
        _PreviewPlayingNotifier.new);