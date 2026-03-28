import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../engine/animation/animator.dart';
import '../engine/renderer/matrix_renderer.dart';
import '../engine/scene/layer.dart';
import '../engine/scene/scene.dart';
import '../engine/scene/timeline.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Scene Provider
// ─────────────────────────────────────────────────────────────────────────────

/// The single source of truth for the current [Scene] being edited.
///
/// UI components call `ref.read(sceneProvider.notifier)` to mutate the scene.
/// The [MatrixRenderer] and [FrameExporter] read from this provider.
class SceneNotifier extends Notifier<Scene> {
  @override
  Scene build() => Scene.blank(name: 'Untitled Project');

  // ── Layer CRUD ────────────────────────────────────────────────────────────

  void addTextLayer() {
    final layer = TextLayer(
      id: _uuid.v4(),
      name: 'Text ${state.layers.length + 1}',
      text: 'LED MATRIX',
    );
    state = state.addLayer(layer);
  }

  void addClockLayer() {
    final layer = ClockLayer(
      id: _uuid.v4(),
      name: 'Clock ${state.layers.length + 1}',
    );
    state = state.addLayer(layer);
  }

  void addGifLayer() {
    final layer = GifLayer(
      id: _uuid.v4(),
      name: 'GIF ${state.layers.length + 1}',
    );
    state = state.addLayer(layer);
  }

  void addSpotifyLayer() {
    final layer = SpotifyLayer(
      id: _uuid.v4(),
      name: 'Spotify ${state.layers.length + 1}',
    );
    state = state.addLayer(layer);
  }

  void addPomodoroLayer() {
    final layer = PomodoroLayer(
      id: _uuid.v4(),
      name: 'Pomodoro ${state.layers.length + 1}',
    );
    state = state.addLayer(layer);
  }

  void removeLayer(String id) {
    state = state.removeLayer(id);
    // Clear selection if the removed layer was selected
    if (_selectedLayerId == id) {
      _selectedLayerId = null;
    }
  }

  void updateLayer(Layer layer) {
    state = state.updateLayer(layer);
  }

  void reorderLayer(int fromIndex, int toIndex) {
    state = state.reorderLayer(fromIndex, toIndex);
  }

  void toggleVisibility(String id) {
    final layer = state.layerById(id);
    if (layer == null) return;
    state = state.updateLayer(layer.copyWith());
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  String? _selectedLayerId;
  String? get selectedLayerId => _selectedLayerId;

  void selectLayer(String? id) {
    _selectedLayerId = id;
  }

  Layer? get selectedLayer =>
      _selectedLayerId == null ? null : state.layerById(_selectedLayerId!);

  // ── Scene Meta ────────────────────────────────────────────────────────────

  void rename(String name) {
    state = state.copyWith(name: name);
  }

  void loadScene(Scene scene) {
    state = scene;
    _selectedLayerId = null;
  }

  void newScene() {
    state = Scene.blank();
    _selectedLayerId = null;
  }
}

final sceneProvider = NotifierProvider<SceneNotifier, Scene>(SceneNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Selected Layer Provider (derived)
// ─────────────────────────────────────────────────────────────────────────────

final selectedLayerIdProvider = StateProvider<String?>((ref) => null);

final selectedLayerProvider = Provider<Layer?>((ref) {
  final scene = ref.watch(sceneProvider);
  final id = ref.watch(selectedLayerIdProvider);
  if (id == null) return null;
  return scene.layerById(id);
});

// ─────────────────────────────────────────────────────────────────────────────
// Renderer + Timeline
// ─────────────────────────────────────────────────────────────────────────────

final matrixRendererProvider = Provider<MatrixRenderer>(
  (_) => MatrixRenderer(),
);

final animatorProvider = Provider<Animator>((_) => const Animator());

/// Async provider that re-renders whenever the [Scene] changes.
/// The UI watches this to update the matrix preview.
final timelineProvider = FutureProvider<Timeline>((ref) async {
  final scene = ref.watch(sceneProvider);
  final renderer = ref.read(matrixRendererProvider);
  return renderer.render(scene);
});

// ─────────────────────────────────────────────────────────────────────────────
// Preview Playback
// ─────────────────────────────────────────────────────────────────────────────

/// Elapsed playback time in milliseconds. Driven by the preview ticker.
final previewElapsedMsProvider = StateProvider<int>((ref) => 0);

/// Whether the preview is currently playing.
final previewPlayingProvider = StateProvider<bool>((ref) => true);