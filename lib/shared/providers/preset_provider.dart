import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scene/scene.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PresetState — holds scene snapshots for every slot
// ─────────────────────────────────────────────────────────────────────────────

class PresetState {
  /// Maps slot label (1-based int) → saved [Scene] snapshot.
  /// A null value means the slot has never been saved (new/blank).
  final Map<int, Scene?> scenes;

  /// The currently active slot label.
  final int activeSlot;

  /// Ordered list of slot labels (user can add/remove).
  final List<int> slots;

  /// The next label to assign when a new slot is added.
  final int nextLabel;

  const PresetState({
    required this.scenes,
    required this.activeSlot,
    required this.slots,
    required this.nextLabel,
  });

  factory PresetState.initial() => PresetState(
        slots: [1, 2, 3, 4],
        activeSlot: 1,
        nextLabel: 5,
        scenes: const {1: null, 2: null, 3: null, 4: null},
      );

  PresetState copyWith({
    Map<int, Scene?>? scenes,
    int? activeSlot,
    List<int>? slots,
    int? nextLabel,
  }) =>
      PresetState(
        scenes: scenes ?? this.scenes,
        activeSlot: activeSlot ?? this.activeSlot,
        slots: slots ?? this.slots,
        nextLabel: nextLabel ?? this.nextLabel,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PresetNotifier
// ─────────────────────────────────────────────────────────────────────────────

class PresetNotifier extends Notifier<PresetState> {
  @override
  PresetState build() => PresetState.initial();

  /// Save [scene] into [slot] (defaults to active slot).
  void saveScene(Scene scene, {int? slot}) {
    final target = slot ?? state.activeSlot;
    state = state.copyWith(
      scenes: {...state.scenes, target: scene},
    );
  }

  /// Returns the scene for [slot], or null if never saved.
  Scene? sceneFor(int slot) => state.scenes[slot];

  /// Switch to [slot]. Returns the stored [Scene] (null if blank).
  Scene? switchTo(int slot) {
    state = state.copyWith(activeSlot: slot);
    return state.scenes[slot];
  }

  /// Add a new slot with an optional initial [scene].
  void addSlot({Scene? scene}) {
    final label = state.nextLabel;
    final newSlots = [...state.slots, label];
    final newScenes = {...state.scenes, label: scene};
    state = state.copyWith(
      slots: newSlots,
      scenes: newScenes,
      activeSlot: label,
      nextLabel: label + 1,
    );
  }

  /// Remove [slot]. Cannot remove the last slot.
  /// If the active slot is removed, falls back to the first remaining slot.
  void removeSlot(int slot) {
    if (state.slots.length <= 1) return;
    final newSlots = state.slots.where((s) => s != slot).toList();
    final newScenes = Map<int, Scene?>.from(state.scenes)..remove(slot);
    final newActive =
        state.activeSlot == slot ? newSlots.first : state.activeSlot;
    state = state.copyWith(
      slots: newSlots,
      scenes: newScenes,
      activeSlot: newActive,
    );
  }
}

final presetProvider =
    NotifierProvider<PresetNotifier, PresetState>(PresetNotifier.new);