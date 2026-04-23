import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Frameon dark theme.
///
/// Palette:
///   Scaffold bg  #1A1A1A  — deep charcoal, easier on eyes
///   Surface      #242424  — panel background
///   Surface high #2D2D2D  — cards / inputs
///   Border       #3A3A3A  — subtle dividers
///   Primary      #21C32C  — LED green (same as light theme for consistency)
///   Secondary    #1A8C96  — teal accent (slightly brighter for dark bg)
///   On-surface   #E8E8E8  — off-white text
ThemeData buildDarkTheme() {
  const green = Color(0xFF21C32C);
  const teal  = Color(0xFF1A8C96);

  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    extensions: const [AppColors.dark],
    colorScheme: base.colorScheme.copyWith(
      primary:                 green,
      secondary:               teal,
      surface:                 Color(0xFF242424),
      onSurface:               Color(0xFFE8E8E8),
      surfaceContainerHighest: Color(0xFF2D2D2D),
      outline:                 Color(0xFF3A3A3A),
    ),
    scaffoldBackgroundColor: const Color(0xFF1A1A1A),
    dividerColor: const Color(0xFF3A3A3A),
    dividerTheme: const DividerThemeData(
      color:     Color(0xFF3A3A3A),
      space:     1,
      thickness: 1,
    ),
    cardTheme: const CardThemeData(
      margin:    EdgeInsets.zero,
      elevation: 0,
      color:     Color(0xFF242424),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: Color(0xFF3A3A3A)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense:        true,
      filled:         true,
      fillColor:      const Color(0xFF2D2D2D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide:   const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide:   const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide:   const BorderSide(color: green, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF6B6B6B),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? green : const Color(0xFF4A4A4A),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor:   green,
      inactiveTrackColor: Color(0xFF3A3A3A),
      thumbColor:         green,
      overlayColor:       Color(0x1521C32C),
      trackHeight:        3,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        iconSize:    WidgetStateProperty.all(16),
        iconColor:   WidgetStateProperty.all(const Color(0xFF9E9E9E)),
        padding:     WidgetStateProperty.all(const EdgeInsets.all(6)),
        minimumSize: WidgetStateProperty.all(const Size(30, 30)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        overlayColor: WidgetStateProperty.all(const Color(0x1AFFFFFF)),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      labelSmall: const TextStyle(
        fontSize:      10,
        fontWeight:    FontWeight.w600,
        letterSpacing: 0.08,
        color:         Color(0xFF8A8A8A),
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        color:    Color(0xFFA0A0A0),
      ),
      bodyMedium: const TextStyle(
        fontSize: 13,
        color:    Color(0xFFE8E8E8),
      ),
    ),
  );
}