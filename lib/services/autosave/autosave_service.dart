import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'; 
import 'package:shared_preferences/shared_preferences.dart';

import '../../engine/scene/scene.dart';
import '../../services/storage/project_service.dart';
import '../../shared/providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AutosaveService
//
// Saves the current scene to SharedPreferences on app close and restores it
// on the next launch. Uses the same JSON serialisation as ProjectService so
// the format is identical to .frameon project files.
//
// Key design decisions:
//   - Uses SharedPreferences (no file picker, no path_provider). The scene
//     JSON is stored as a single string under _kKey. This is ~20–200 KB for
//     typical scenes — well within SharedPreferences limits.
//   - save() is synchronous-feeling from the caller's perspective but uses
//     await internally; call it from onWindowClose before destroy.
//   - restore() returns null if nothing was saved (first launch or cleared).
//   - A separate _kVersionKey stores the app version so future migrations can
//     detect stale autosave data.
// ─────────────────────────────────────────────────────────────────────────────

const String _kKey        = 'autosave_scene_v1';
const String _kVersionKey = 'autosave_app_version';
const String _kAppVersion = '1.0.0';

class AutosaveService {
  const AutosaveService();

  /// Serialise [scene] and write to SharedPreferences.
  /// Called from [onWindowClose] — must complete before the window destroys.
  Future<void> save(Scene scene) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json  = const ProjectService().toJsonString(scene);
      await prefs.setString(_kKey, json);
      await prefs.setString(_kVersionKey, _kAppVersion);
    } catch (e) {
      // Non-fatal — worst case the user loses unsaved work on next launch.
      // Do not rethrow; we don't want to block the close sequence.
      debugPrint('[AutosaveService] save failed: $e');
    }
  }

  /// Read and deserialise the last autosaved scene.
  /// Returns null if no autosave exists or if the data is corrupt.
  Future<Scene?> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json  = prefs.getString(_kKey);
      if (json == null || json.isEmpty) return null;
      return const ProjectService().fromJsonString(json);
    } catch (e) {
      debugPrint('[AutosaveService] restore failed: $e');
      return null;
    }
  }

  /// Erase the autosave slot (e.g. when the user creates a New project).
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final autosaveServiceProvider =
    Provider<AutosaveService>((_) => const AutosaveService());