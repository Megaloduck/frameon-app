import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'engine/widgets/clock_widget.dart';
import 'shared/providers/time_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  // Give ClockWidget access to the live time via the static container ref
  ClockWidget.init(container);

  // Start NTP sync + per-second tick
  await container.read(timeServiceProvider.notifier).initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FrameonApp(),
    ),
  );
}