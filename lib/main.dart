import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'engine/widgets/clock_widget.dart';
import 'shared/providers/time_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hide the native title bar on desktop so our custom top bar
  // becomes the sole chrome. macOS keeps its traffic-light buttons
  // (they sit in the left margin of our bar); Windows/Linux get
  // the custom minimize/maximize/close buttons we render ourselves.
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