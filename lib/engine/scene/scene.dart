import 'package:uuid/uuid.dart';
import 'layer.dart';

const _uuid = Uuid();

/// A [Scene] is the top-level project document — an ordered list of [Layer]s
/// that are composited together to produce each frame on the LED matrix.
///
/// Layers are stored bottom-to-top (index 0 = back, last index = front).
/// The [Scene] is immutable by design; mutations return a new [Scene].
class Scene {
  final String id;
  final String name;
  final List<Layer> layers;

  /// Matrix canvas dimensions in pixels.
  final int matrixWidth;
  final int matrixHeight;

  /// Target frame rate for preview and export (frames per second).
  final double fps;

  const Scene({
    required this.id,
    required this.name,
    required this.layers,
    this.matrixWidth = 64,
    this.matrixHeight = 32,
    this.fps = 10,
  });

  /// Create a blank scene with a default name.
  factory Scene.blank({String name = 'Untitled'}) => Scene(
        id: _uuid.v4(),
        name: name,
        layers: const [],
      );

  // ── Layer Operations (all return a new Scene) ───────────────────────────

  /// Add [layer] on top of the stack.
  Scene addLayer(Layer layer) {
    final updated = List<Layer>.from(layers)..add(layer);
    return _withLayers(updated);
  }

  /// Remove the layer with [id].
  Scene removeLayer(String id) {
    final updated = layers.where((l) => l.id != id).toList();
    return _withLayers(updated);
  }

  /// Replace the layer matching [layer.id] with the updated version.
  Scene updateLayer(Layer layer) {
    final updated = layers.map((l) => l.id == layer.id ? layer : l).toList();
    return _withLayers(updated);
  }

  /// Move a layer from [fromIndex] to [toIndex] (re-order).
  Scene reorderLayer(int fromIndex, int toIndex) {
    final updated = List<Layer>.from(layers);
    final item = updated.removeAt(fromIndex);
    final insertAt = toIndex > fromIndex ? toIndex - 1 : toIndex;
    updated.insert(insertAt, item);
    return _withLayers(updated);
  }

  /// Move a layer one step toward the front.
  Scene bringForward(String id) {
    final idx = _indexOfId(id);
    if (idx == -1 || idx == layers.length - 1) return this;
    return reorderLayer(idx, idx + 2);
  }

  /// Move a layer one step toward the back.
  Scene sendBackward(String id) {
    final idx = _indexOfId(id);
    if (idx <= 0) return this;
    return reorderLayer(idx, idx - 1);
  }

  /// Toggle visibility of a layer.
  Scene toggleVisibility(String id) {
    final layer = layerById(id);
    if (layer == null) return this;
    return updateLayer(layer.copyWith());
  }

  // ── Queries ─────────────────────────────────────────────────────────────

  Layer? layerById(String id) {
    try {
      return layers.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Layers ordered front-to-back (for rendering, iterate reversed).
  List<Layer> get visibleLayers =>
      layers.where((l) => l.visible).toList();

  bool get isEmpty => layers.isEmpty;

  // ── copyWith ────────────────────────────────────────────────────────────

  Scene copyWith({
    String? id,
    String? name,
    List<Layer>? layers,
    int? matrixWidth,
    int? matrixHeight,
    double? fps,
  }) =>
      Scene(
        id: id ?? this.id,
        name: name ?? this.name,
        layers: layers ?? this.layers,
        matrixWidth: matrixWidth ?? this.matrixWidth,
        matrixHeight: matrixHeight ?? this.matrixHeight,
        fps: fps ?? this.fps,
      );

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'matrixWidth': matrixWidth,
        'matrixHeight': matrixHeight,
        'fps': fps,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'] as String,
        name: j['name'] as String,
        matrixWidth: j['matrixWidth'] as int? ?? 64,
        matrixHeight: j['matrixHeight'] as int? ?? 32,
        fps: (j['fps'] as num?)?.toDouble() ?? 10,
        layers: (j['layers'] as List<dynamic>? ?? [])
            .map((e) => layerFromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // ── Private ──────────────────────────────────────────────────────────────

  Scene _withLayers(List<Layer> updated) => copyWith(layers: updated);

  int _indexOfId(String id) => layers.indexWhere((l) => l.id == id);
}