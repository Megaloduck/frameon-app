import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color surface;
  final Color surfaceLow;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color textDim;

  const AppColors({
    required this.surface,
    required this.surfaceLow,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.textDim,
  });

  @override
  AppColors copyWith({
    Color? surface,
    Color? surfaceLow,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
    Color? textDim,
  }) =>
      AppColors(
        surface:     surface     ?? this.surface,
        surfaceLow:  surfaceLow  ?? this.surfaceLow,
        border:      border      ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted:   textMuted   ?? this.textMuted,
        textDim:     textDim     ?? this.textDim,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      surface:     Color.lerp(surface,     other.surface,     t)!,
      surfaceLow:  Color.lerp(surfaceLow,  other.surfaceLow,  t)!,
      border:      Color.lerp(border,      other.border,      t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted:   Color.lerp(textMuted,   other.textMuted,   t)!,
      textDim:     Color.lerp(textDim,     other.textDim,     t)!,
    );
  }

  static const light = AppColors(
    surface:     Color(0xFFF8F7F3),
    surfaceLow:  Color(0xFFECEAE3),
    border:      Color(0xFFE0DDD6),
    textPrimary: Color(0xFF1A1A1A),
    textMuted:   Color(0xFF888580),
    textDim:     Color(0xFFB0ADA8),
  );

  static const dark = AppColors(
    surface:     Color(0xFF242424),
    surfaceLow:  Color(0xFF1A1A1A),
    border:      Color(0xFF3A3A3A),
    textPrimary: Color(0xFFE8E8E8),
    textMuted:   Color(0xFF9E9E9E),
    textDim:     Color(0xFF6B6B6B),
  );
} 