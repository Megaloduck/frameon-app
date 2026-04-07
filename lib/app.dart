import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/dark_theme.dart';
import 'core/theme/light_theme.dart';
import 'features/editor/pages/editor_page.dart';

final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.light);

class FrameonApp extends ConsumerWidget {
  const FrameonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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