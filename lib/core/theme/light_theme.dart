import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Frameon light theme.
///
/// Palette:
///   Scaffold bg  #ECEAE3  — warm off-white, like paper
///   Surface      #F8F7F3  — panel background
///   Surface high #FFFFFF  — cards / inputs
///   Border       #E0DDD6  — subtle warm grey dividers
///   Primary      #21C32C  — LED green
///   Secondary    #0E7C86  — teal accent
///   On-surface   #1A1A1A  — near-black text
ThemeData buildLightTheme() {
  const green = Color(0xFF21C32C);
  const teal  = Color(0xFF0E7C86);

  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    extensions: const [AppColors.light],
    colorScheme: base.colorScheme.copyWith(
      primary:                 green,
      secondary:               teal,
      surface:                 Color(0xFFF8F7F3),
      onSurface:               Color(0xFF1A1A1A),
      surfaceContainerHighest: Color(0xFFECEAE3),
      outline:                 Color(0xFFE0DDD6),
    ),
    scaffoldBackgroundColor: const Color(0xFFECEAE3),
    dividerColor: const Color(0xFFE0DDD6),
    dividerTheme: const DividerThemeData(
      color:     Color(0xFFE0DDD6),
      space:     1,
      thickness: 1,
    ),
    cardTheme: const CardThemeData(
      margin:    EdgeInsets.zero,
      elevation: 0,
      color:     Color(0xFFF8F7F3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: Color(0xFFE0DDD6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense:        true,
      filled:         true,
      fillColor:      const Color(0xFFFFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide:   const BorderSide(color: Color(0xFFE0DDD6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide:   const BorderSide(color: Color(0xFFE0DDD6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide:   const BorderSide(color: green, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFFBBB8B0),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? green : const Color(0xFFDDDDD8),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor:   green,
      inactiveTrackColor: Color(0xFFE0DDD6),
      thumbColor:         green,
      overlayColor:       Color(0x1521C32C),
      trackHeight:        3,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        iconSize:    WidgetStateProperty.all(16),
        iconColor:   WidgetStateProperty.all(const Color(0xFF888580)),
        padding:     WidgetStateProperty.all(const EdgeInsets.all(6)),
        minimumSize: WidgetStateProperty.all(const Size(30, 30)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        overlayColor: WidgetStateProperty.all(const Color(0x0F000000)),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      labelSmall: const TextStyle(
        fontSize:      10,
        fontWeight:    FontWeight.w600,
        letterSpacing: 0.08,
        color:         Color(0xFF999690),
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        color:    Color(0xFF666360),
      ),
      bodyMedium: const TextStyle(
        fontSize: 13,
        color:    Color(0xFF1A1A1A),
      ),
    ),
  );
}