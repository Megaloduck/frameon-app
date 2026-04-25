import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'engine/widgets/clock_widget.dart';
import 'services/autosave/autosave_service.dart';
import 'shared/providers/providers.dart';
import 'shared/providers/time_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-warm SharedPreferences so the first call in AutosaveService is instant.
  await SharedPreferences.getInstance();

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(960, 620),
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final container = ProviderContainer();

  // ── Restore autosave ──────────────────────────────────────────────────────
  // Attempt to restore the last session before the UI is shown.
  // If no autosave exists (first launch) or if it's corrupt, the scene
  // stays as Scene.blank() — same as before this feature was added.
  final autosave = container.read(autosaveServiceProvider);
  final saved    = await autosave.restore();
  if (saved != null) {
    container.read(sceneProvider.notifier).loadScene(saved);
    debugPrint('[Autosave] Restored scene: ${saved.name} '
        '(${saved.layers.length} layers)');
  }

  // ── Register close handler ────────────────────────────────────────────────
  // window_manager requires a WindowListener to intercept close events.
  // We set preventClose(true) so we can save before actually closing.
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.setPreventClose(true);
    windowManager.addListener(
      _AutosaveWindowListener(container: container),
    );
  }

  // Give ClockWidget access to the live time via the static container ref.
  ClockWidget.init(container);

  // Start NTP sync + per-second tick.
  await container.read(timeServiceProvider.notifier).initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FrameonApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _AutosaveWindowListener
//
// Intercepts the window-close event, saves the scene, then allows the close
// to proceed. Using setPreventClose(true) + WindowListener is the correct
// pattern for window_manager — it gives us an async hook before destruction.
// ─────────────────────────────────────────────────────────────────────────────

class _AutosaveWindowListener extends WindowListener {
  final ProviderContainer container;
  _AutosaveWindowListener({required this.container});

  @override
  Future<void> onWindowClose() async {
    // 1. Save the current scene.
    final scene    = container.read(sceneProvider);
    final autosave = container.read(autosaveServiceProvider);
    await autosave.save(scene);
    debugPrint('[Autosave] Saved scene on close: ${scene.name} '
        '(${scene.layers.length} layers)');

    // 2. Allow the window to actually close now.
    await windowManager.destroy();
  }
}