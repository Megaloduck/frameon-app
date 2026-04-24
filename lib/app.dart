import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/dark_theme.dart';
import 'core/theme/light_theme.dart';
import 'features/editor/pages/editor_page.dart';
import 'shared/providers/time_service.dart';

// ── Replace StateProvider with a proper Notifier ──────────────────────────────
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class FrameonApp extends ConsumerStatefulWidget {
  const FrameonApp({super.key});

  @override
  ConsumerState<FrameonApp> createState() => _FrameonAppState();
}

class _FrameonAppState extends ConsumerState<FrameonApp> {
  @override
  void dispose() {
    ref.read(timeServiceProvider.notifier).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Frameon',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const EditorPage(),
    );
  }
}