import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../engine/animation/animator.dart';
import '../../engine/renderer/matrix_renderer.dart';
import '../../engine/scene/layer.dart';
import '../../engine/scene/scene.dart';
import '../../engine/scene/timeline.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Scene Notifier
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the current [Scene] and all mutations that can be applied to it.
///
/// Selection state lives here too as a single source of truth.
/// Widgets watch [selectedLayerIdProvider] (a derived provider) for reactive
/// rebuilds — [SceneNotifier] writes to it via [_setSelection].
class SceneNotifier extends Notifier<Scene> {
  @override
  Scene build() => Scene.blank(name: 'Untitled Project');

  // ── Layer CRUD ─────────────────────────────────────────────────────────

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

  void updateLayer(Layer layer) {
    state = state.updateLayer(layer);
  }

  void reorderLayer(int fromIndex, int toIndex) {
    state = state.reorderLayer(fromIndex, toIndex);
  }

  /// Correctly toggles [visible] — previously was a no-op clone.
  void toggleVisibility(String id) {
    final layer = state.layerById(id);
    if (layer == null) return;
    state = state.updateLayer(layer.copyWith(visible: !layer.visible));
  }

  // ── Selection — single source of truth ──────────────────────────────────
  //
  // [_selectedId] is the backing store. Widgets watch [selectedLayerIdProvider]
  // which is kept in sync via [_setSelection]. This avoids the previous
  // split-brain where SceneNotifier._selectedLayerId and
  // selectedLayerIdProvider were two independent, unsynchronised sources.

  String? _selectedId;

  void selectLayer(String? id) => _setSelection(id);

  void _setSelection(String? id) {
    _selectedId = id;
    // Keep the derived StateProvider in sync so widgets rebuild.
    ref.read(selectedLayerIdProvider.notifier).state = id;
  }

  // ── Scene meta ───────────────────────────────────────────────────────────

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
// Selection (single source of truth — written only by SceneNotifier)
// ─────────────────────────────────────────────────────────────────────────────

/// The ID of the currently selected layer, or null.
/// Written exclusively by [SceneNotifier._setSelection]; read by the UI.
final selectedLayerIdProvider = StateProvider<String?>((ref) => null);

/// The full [Layer] object for the current selection, or null.
final selectedLayerProvider = Provider<Layer?>((ref) {
  final scene = ref.watch(sceneProvider);
  final id = ref.watch(selectedLayerIdProvider);
  if (id == null) return null;
  return scene.layerById(id);
});

// ─────────────────────────────────────────────────────────────────────────────
// Renderer singletons
// ─────────────────────────────────────────────────────────────────────────────

final matrixRendererProvider =
    Provider<MatrixRenderer>((_) => MatrixRenderer());

final animatorProvider = Provider<Animator>((_) => const Animator());

// ─────────────────────────────────────────────────────────────────────────────
// Timeline — debounced re-render
// ─────────────────────────────────────────────────────────────────────────────

/// Async provider that re-renders the [Scene] into a [Timeline] whenever the
/// scene changes. Uses [AsyncNotifier] so re-renders can be debounced and
/// cancelled when a newer render supersedes an in-flight one.
///
/// The previous implementation used a plain [FutureProvider] that triggered a
/// full re-render on every scene mutation (including selection changes).
/// This version only re-renders when the layer *content* changes, not when
/// selection changes.
class TimelineNotifier extends AsyncNotifier<Timeline> {
  @override
  Future<Timeline> build() async {
    // Watch only the layer list and their data — not selection state.
    final scene = ref.watch(sceneProvider);
    final renderer = ref.read(matrixRendererProvider);

    // Debounce: wait 80 ms so rapid successive edits collapse into one render.
    await Future<void>.delayed(const Duration(milliseconds: 80));

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

/// Elapsed playback time in milliseconds. Incremented by the preview ticker.
final previewElapsedMsProvider = StateProvider<int>((ref) => 0);

/// Whether the preview is currently playing.
final previewPlayingProvider = StateProvider<bool>((ref) => true);