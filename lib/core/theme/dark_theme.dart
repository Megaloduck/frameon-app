import 'package:flutter/material.dart';

ThemeData buildDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: const Color(0xFF21C32C),
      secondary: const Color(0xFF0E7C86),
    ),
  );
}