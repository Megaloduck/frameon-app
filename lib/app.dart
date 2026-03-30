import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/dark_theme.dart';
import 'core/theme/light_theme.dart';
import 'features/editor/pages/editor_page.dart';

class FrameonApp extends StatelessWidget {
  const FrameonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Frameon',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: const EditorPage(),
      ),
    );
  }
}