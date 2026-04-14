import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../engine/renderer/matrix_renderer.dart';
import '../../engine/scene/layer.dart';
import '../../engine/scene/scene.dart';
import '../../engine/scene/timeline.dart';
import '../../services/spotify/spotify_service.dart';
import '../../services/pomodoro/pomodoro_service.dart';

import '../../features/editor/widgets/gif_bytes_provider.dart';
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
// Frame count calculation
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
      case LayerType.spotify:
        layerFrames = twoSecondFrames;

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

  return maxFrames.clamp(1, 300);
}

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

    // Determine which live-data layers are visible
    final hasTimeLayers = scene.visibleLayers.any((l) =>
        l.type == LayerType.clock || l.type == LayerType.pomodoro);
    final hasSpotifyLayers =
        scene.visibleLayers.any((l) => l.type == LayerType.spotify);

    if (hasTimeLayers) {
      ref.watch(timeServiceProvider);
      ref.watch(pomodoroServiceProvider);
    }

    // ── KEY FIX: watch Spotify state so album art + progress trigger re-render ──
    if (hasSpotifyLayers) {
      final spotifyState = ref.watch(spotifyServiceProvider);
      // Push latest track data into renderer before rendering frames
      renderer.currentTrack =
          spotifyState.isConnected ? spotifyState.toTrack() : null;
    }

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

    // Debounce rapid scene changes (e.g. typing in text field).
    // Skip debounce for live layers so clock/spotify update immediately.
    final isLive = hasTimeLayers || hasSpotifyLayers;
    if (!isLive) {
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
    }

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
// Preview playback
// ─────────────────────────────────────────────────────────────────────────────

final previewElapsedMsProvider = StateProvider<int>((ref) => 0);
final previewPlayingProvider   = StateProvider<bool>((ref) => true);