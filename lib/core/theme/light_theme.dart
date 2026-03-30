import 'package:flutter/material.dart';

ThemeData buildLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: const Color(0xFF21C32C),
      secondary: const Color(0xFF0E7C86),
      surface: const Color(0xFFF6F4EE),
    ),
    scaffoldBackgroundColor: const Color(0xFFE8E6E0),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
  );
}