import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/scene.dart';
import '../../shared/providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProjectService — JSON serialisation (platform-safe, no dart:io)
// ─────────────────────────────────────────────────────────────────────────────

/// Serialises and deserialises [Scene] objects as pretty-printed JSON.
///
/// This class has **no `dart:io` import** and works on all platforms.
/// For file-system save/load on Desktop/Mobile use `ProjectServiceIO`
/// from `project_service_io.dart`.
class ProjectService {
  const ProjectService();

  /// Serialise [scene] to a formatted JSON string.
  String toJsonString(Scene scene) =>
      const JsonEncoder.withIndent('  ').convert(scene.toJson());

  /// Deserialise a [Scene] from a JSON string.
  /// Throws [FormatException] if the JSON is malformed.
  Scene fromJsonString(String json) =>
      Scene.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent projects registry
// ─────────────────────────────────────────────────────────────────────────────

class RecentProjectsNotifier extends Notifier<List<String>> {
  static const int _max = 10;

  @override
  List<String> build() => [];

  void add(String path) {
    final updated = [path, ...state.where((p) => p != path)];
    state = updated.take(_max).toList();
  }

  void remove(String path) => state = state.where((p) => p != path).toList();
  void clear() => state = [];
}

final recentProjectsProvider =
    NotifierProvider<RecentProjectsNotifier, List<String>>(
        RecentProjectsNotifier.new);

final projectServiceProvider =
    Provider<ProjectService>((_) => const ProjectService());

// ─────────────────────────────────────────────────────────────────────────────
// WidgetRef extensions
// ─────────────────────────────────────────────────────────────────────────────

extension ProjectJsonActions on WidgetRef {
  /// Serialise the current scene to JSON (e.g. for clipboard copy or web download).
  String exportJson() {
    final scene = read(sceneProvider);
    return read(projectServiceProvider).toJsonString(scene);
  }

  /// Replace the current scene from a JSON string.
  void importJson(String json) {
    final scene = read(projectServiceProvider).fromJsonString(json);
    read(sceneProvider.notifier).loadScene(scene);
  }
}