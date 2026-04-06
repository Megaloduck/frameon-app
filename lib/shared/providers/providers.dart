import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../engine/renderer/matrix_renderer.dart';
import '../../engine/scene/layer.dart';
import '../../engine/scene/scene.dart';
import '../../engine/scene/timeline.dart';
import '../../services/spotify/spotify_service.dart';

// gif_bytes_provider lives in the widgets folder but is a global provider —
// import it here so TimelineNotifier can re-hydrate the renderer on every render.
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

  void reorderLayer(int fromIndex, int toIndex) =>
      state = state.reorderLayer(fromIndex, toIndex);

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
//
// The renderer is a single long-lived instance (Provider, not autoDispose).
// Two things are kept in sync reactively:
//   1. Spotify track  — via ref.listen on spotifyServiceProvider
//   2. GIF byte cache — re-hydrated on every timeline render from gifBytesProvider
//      (see TimelineNotifier below).  This is the fix for GIF not appearing in
//      the matrix preview: previously the asset cache was populated on file-pick
//      but the renderer instance could be recreated or the cache never re-checked.
// ─────────────────────────────────────────────────────────────────────────────

final matrixRendererProvider = Provider<MatrixRenderer>((ref) {
  final renderer = MatrixRenderer();

  ref.listen(spotifyServiceProvider, (_, next) {
    renderer.currentTrack = next.isConnected ? next.toTrack() : null;
  });

  return renderer;
});

// ─────────────────────────────────────────────────────────────────────────────
// Timeline
//
// Key fix: before calling renderer.render(), we re-hydrate the renderer's
// asset cache from gifBytesProvider.  This means:
//   - If bytes were loaded via _GifLeft._pick(), they land in gifBytesProvider.
//   - When sceneProvider changes (e.g. layer filePath is set), timelineProvider
//     rebuilds, reads the current gifBytesProvider map, and injects every
//     entry into the renderer before rendering.
//   - Result: the GIF always shows in the matrix preview regardless of
//     renderer instance lifetime or event ordering.
// ─────────────────────────────────────────────────────────────────────────────

class TimelineNotifier extends AsyncNotifier<Timeline> {
  Timer? _debounce;
  int    _generation = 0;

  @override
  Future<Timeline> build() async {
    final scene    = ref.watch(sceneProvider);
    final renderer = ref.read(matrixRendererProvider);

    // ── Re-hydrate renderer asset cache from gifBytesProvider ──────────────
    // Watch gifBytesProvider so that uploading a new GIF (which updates that
    // provider) triggers a timeline rebuild even if the scene hasn't changed.
    final gifBytes = ref.watch(gifBytesProvider);
    for (final entry in gifBytes.entries) {
      // addAssetBytes decodes only once internally; calling it again with the
      // same key is safe — it just overwrites with the same decoded asset.
      renderer.addAssetBytes(entry.key, entry.value);
    }
    // ───────────────────────────────────────────────────────────────────────

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

    return renderer.render(
      scene,
      frameDurationMs: (1000 / scene.fps).round(),
      frameCount: 33,
    );
  }
}

final timelineProvider =
    AsyncNotifierProvider<TimelineNotifier, Timeline>(TimelineNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Preview playback
// ─────────────────────────────────────────────────────────────────────────────

final previewElapsedMsProvider = StateProvider<int>((ref) => 0);
final previewPlayingProvider   = StateProvider<bool>((ref) => true);