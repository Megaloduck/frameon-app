import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/scene.dart';
import '../../shared/providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProjectService
// ─────────────────────────────────────────────────────────────────────────────

/// Serialises and deserialises [Scene] objects to/from disk as JSON.
///
/// File format: pretty-printed JSON with a `.frameon` extension.
/// All layer types use the same JSON schema defined in [Layer.toJson].
class ProjectService {
  const ProjectService();

  /// Save [scene] to [file]. Overwrites if the file already exists.
  Future<void> save(Scene scene, File file) async {
    final String json =
        const JsonEncoder.withIndent('  ').convert(scene.toJson());
    await file.writeAsString(json, encoding: utf8, flush: true);
  }

  /// Load a [Scene] from [file].
  /// Throws [FormatException] if the JSON is invalid.
  Future<Scene> load(File file) async {
    final String json = await file.readAsString(encoding: utf8);
    final Map<String, dynamic> map =
        jsonDecode(json) as Map<String, dynamic>;
    return Scene.fromJson(map);
  }

  /// Export [scene] as a JSON string (for clipboard or web download).
  String toJsonString(Scene scene) =>
      const JsonEncoder.withIndent('  ').convert(scene.toJson());

  /// Import a [Scene] from a raw JSON string.
  Scene fromJsonString(String json) =>
      Scene.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent projects registry
// ─────────────────────────────────────────────────────────────────────────────

/// Keeps an in-memory list of recently opened file paths.
/// Persisted to disk in future iteration via shared_preferences.
class RecentProjectsNotifier extends Notifier<List<String>> {
  static const int _maxRecent = 10;

  @override
  List<String> build() => [];

  void add(String path) {
    final updated = [path, ...state.where((p) => p != path)];
    state = updated.take(_maxRecent).toList();
  }

  void remove(String path) {
    state = state.where((p) => p != path).toList();
  }

  void clear() => state = [];
}

final recentProjectsProvider =
    NotifierProvider<RecentProjectsNotifier, List<String>>(
  RecentProjectsNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Convenience provider
// ─────────────────────────────────────────────────────────────────────────────

final projectServiceProvider =
    Provider<ProjectService>((_) => const ProjectService());

// ─────────────────────────────────────────────────────────────────────────────
// Actions wired to SceneNotifier
// ─────────────────────────────────────────────────────────────────────────────

extension ProjectActions on WidgetRef {
  /// Save the current scene to [file] and add it to recents.
  Future<void> saveProject(File file) async {
    final scene = read(sceneProvider);
    await read(projectServiceProvider).save(scene, file);
    read(recentProjectsProvider.notifier).add(file.path);
  }

  /// Load a scene from [file], replace the current scene, and add to recents.
  Future<void> openProject(File file) async {
    final scene = await read(projectServiceProvider).load(file);
    read(sceneProvider.notifier).loadScene(scene);
    read(recentProjectsProvider.notifier).add(file.path);
  }
}