import 'package:uuid/uuid.dart';
import 'layer.dart';

const _uuid = Uuid();

/// A [Scene] is the top-level project document — an ordered list of [Layer]s
/// composited together to produce each frame on the LED matrix.
///
/// Layers are stored bottom-to-top (index 0 = back, last = front).
/// All mutations return a new [Scene] — the model is fully immutable.
class Scene {
  final String id;
  final String name;
  final List<Layer> layers;
  final int matrixWidth;
  final int matrixHeight;
  final double fps;

  const Scene({
    required this.id,
    required this.name,
    required this.layers,
    this.matrixWidth = 64,
    this.matrixHeight = 32,
    this.fps = 10,
  });

  factory Scene.blank({String name = 'Untitled'}) => Scene(
        id: _uuid.v4(),
        name: name,
        layers: const [],
      );

  // ── Layer mutations (all return a new Scene) ─────────────────────────────

  Scene addLayer(Layer layer) =>
      _withLayers(List<Layer>.from(layers)..add(layer));

  Scene removeLayer(String id) =>
      _withLayers(layers.where((l) => l.id != id).toList());

  Scene updateLayer(Layer layer) =>
      _withLayers(layers.map((l) => l.id == layer.id ? layer : l).toList());

  /// Reorder a layer from [fromIndex] to [toIndex].
  ///
  /// Uses standard list-splice semantics: remove at [fromIndex], then insert
  /// at [toIndex]. No adjustment needed — callers (e.g. ReorderableListView)
  /// already pass the post-removal index.
  Scene reorderLayer(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return this;
    final updated = List<Layer>.from(layers);
    final item = updated.removeAt(fromIndex);
    updated.insert(toIndex, item);
    return _withLayers(updated);
  }

  Scene bringForward(String id) {
    final idx = _indexOfId(id);
    if (idx == -1 || idx == layers.length - 1) return this;
    return reorderLayer(idx, idx + 1);
  }

  Scene sendBackward(String id) {
    final idx = _indexOfId(id);
    if (idx <= 0) return this;
    return reorderLayer(idx, idx - 1);
  }

  /// Toggle the [visible] flag of the layer with [id].
  ///
  /// Previously this called copyWith() with no args (a no-op clone).
  /// Fixed: explicitly passes visible: !layer.visible.
  Scene toggleVisibility(String id) {
    final layer = layerById(id);
    if (layer == null) return this;
    return updateLayer(layer.copyWith(visible: !layer.visible));
  }

  // ── Queries ──────────────────────────────────────────────────────────────

  Layer? layerById(String id) {
    try {
      return layers.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Layer> get visibleLayers => layers.where((l) => l.visible).toList();

  bool get isEmpty => layers.isEmpty;

  // ── copyWith ─────────────────────────────────────────────────────────────

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

  // ── Serialisation ─────────────────────────────────────────────────────────

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

  // ── Private ───────────────────────────────────────────────────────────────

  Scene _withLayers(List<Layer> updated) => copyWith(layers: updated);

  int _indexOfId(String id) => layers.indexWhere((l) => l.id == id);
}