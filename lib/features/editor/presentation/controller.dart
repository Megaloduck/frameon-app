import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/scene.dart';
import '../../../shared/providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Editor state
// ─────────────────────────────────────────────────────────────────────────────

class EditorState {
  /// Whether the scene has unsaved changes.
  final bool isDirty;

  /// Path to the file last saved/opened, or null for a new project.
  final String? currentFilePath;

  /// How many undo steps are available.
  final int undoCount;

  /// How many redo steps are available.
  final int redoCount;

  const EditorState({
    this.isDirty       = false,
    this.currentFilePath,
    this.undoCount     = 0,
    this.redoCount     = 0,
  });

  bool get canUndo => undoCount > 0;
  bool get canRedo => redoCount > 0;
  bool get isNewProject => currentFilePath == null;

  EditorState copyWith({
    bool? isDirty,
    String? currentFilePath,
    bool clearFilePath = false,
    int? undoCount,
    int? redoCount,
  }) =>
      EditorState(
        isDirty: isDirty ?? this.isDirty,
        currentFilePath: clearFilePath ? null : (currentFilePath ?? this.currentFilePath),
        undoCount: undoCount ?? this.undoCount,
        redoCount: redoCount ?? this.redoCount,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor controller
// ─────────────────────────────────────────────────────────────────────────────

/// Manages editor-level concerns: undo/redo history, dirty state, and
/// file path tracking.
///
/// The undo/redo stack stores [Scene] snapshots. Each call to [_snapshot]
/// pushes the current scene onto the undo stack before a mutation.
///
/// Widgets interact with the scene via [SceneNotifier] as before; this
/// controller wraps those calls to intercept and snapshot where needed.
class EditorController extends Notifier<EditorState> {
  static const int _maxHistory = 50;

  final Queue<Scene> _undoStack = Queue();
  final Queue<Scene> _redoStack = Queue();

  @override
  EditorState build() => const EditorState();

  // ── History ───────────────────────────────────────────────────────────────

  /// Snapshot the current scene before a destructive edit.
  void snapshot() {
    final current = ref.read(sceneProvider);
    _undoStack.addLast(current);
    if (_undoStack.length > _maxHistory) _undoStack.removeFirst();
    _redoStack.clear();
    state = state.copyWith(
      isDirty: true,
      undoCount: _undoStack.length,
      redoCount: 0,
    );
  }

  /// Undo the last edit.
  void undo() {
    if (_undoStack.isEmpty) return;
    final current = ref.read(sceneProvider);
    _redoStack.addFirst(current);
    final previous = _undoStack.removeLast();
    ref.read(sceneProvider.notifier).loadScene(previous);
    state = state.copyWith(
      isDirty: _undoStack.isNotEmpty,
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  /// Redo the previously undone edit.
  void redo() {
    if (_redoStack.isEmpty) return;
    final current = ref.read(sceneProvider);
    _undoStack.addLast(current);
    final next = _redoStack.removeFirst();
    ref.read(sceneProvider.notifier).loadScene(next);
    state = state.copyWith(
      isDirty: true,
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  // ── File state ────────────────────────────────────────────────────────────

  /// Called after a successful save.
  void markSaved(String filePath) {
    state = state.copyWith(
      isDirty: false,
      currentFilePath: filePath,
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  /// Called after opening a file — resets undo history.
  void markOpened(String filePath) {
    _undoStack.clear();
    _redoStack.clear();
    state = EditorState(currentFilePath: filePath);
  }

  /// Reset everything for a new project.
  void newProject() {
    _undoStack.clear();
    _redoStack.clear();
    state = const EditorState();
  }
}

final editorControllerProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);