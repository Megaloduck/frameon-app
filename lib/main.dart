import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'shared/providers/time_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Create a provider container and initialize time service
  final container = ProviderContainer();
  await container.read(timeServiceProvider.notifier).initialize();
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FrameonApp(),
    ),
  );
}