import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static design tokens — light-mode constants kept for backwards compatibility
// where a BuildContext is unavailable (e.g. CustomPainter, const widgets).
// Prefer the ThemeTokens extension below whenever context is available.
// ─────────────────────────────────────────────────────────────────────────────

const kGreen       = Color(0xFF21C32C);

// Light-mode palette (used as fallbacks / in non-theme-aware code)
const kSurface     = Color(0xFFF8F7F3);
const kSurfaceLow  = Color(0xFFECEAE3);
const kBorder      = Color(0xFFE0DDD6);
const kTextPrimary = Color(0xFF1A1A1A);
const kTextMuted   = Color(0xFF888580);
const kTextDim     = Color(0xFFB0ADA8);

// Dark-mode palette constants
const kSurfaceDark     = Color(0xFF242424);
const kSurfaceLowDark  = Color(0xFF1A1A1A);
const kBorderDark      = Color(0xFF3A3A3A);
const kTextPrimaryDark = Color(0xFFE8E8E8);
const kTextMutedDark   = Color(0xFF9E9E9E);
const kTextDimDark     = Color(0xFF6B6B6B);

const kRadiusSm = Radius.circular(6);
const kRadiusMd = Radius.circular(9);
const kRadiusLg = Radius.circular(12);

const kPanelBorder = BorderSide(color: kBorder);

// ─────────────────────────────────────────────────────────────────────────────
// ThemeTokens — context-aware token accessor
// ─────────────────────────────────────────────────────────────────────────────

extension ThemeTokens on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get tSurface     => isDark ? kSurfaceDark     : kSurface;
  Color get tSurfaceLow  => isDark ? kSurfaceLowDark  : kSurfaceLow;
  Color get tBorder      => isDark ? kBorderDark      : kBorder;
  Color get tTextPrimary => isDark ? kTextPrimaryDark : kTextPrimary;
  Color get tTextMuted   => isDark ? kTextMutedDark   : kTextMuted;
  Color get tTextDim     => isDark ? kTextDimDark     : kTextDim;

  BorderSide get tPanelBorder => BorderSide(color: tBorder);
}

// ─────────────────────────────────────────────────────────────────────────────
// PanelShell — outer wrapper for every side/bottom panel
// ─────────────────────────────────────────────────────────────────────────────

class PanelShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;

  const PanelShell({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.all(5),
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        decoration: BoxDecoration(
          color: context.tSurface,
          borderRadius: const BorderRadius.all(kRadiusLg),
          border: Border.all(color: context.tBorder),
        ),
        child: child,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionLabel
// ─────────────────────────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 6),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
            color: context.tTextDim,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hairline
// ─────────────────────────────────────────────────────────────────────────────

class Hairline extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  const Hairline({super.key, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        height: 1,
        color: context.tBorder,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PropRow
// ─────────────────────────────────────────────────────────────────────────────

class PropRow extends StatelessWidget {
  final String label;
  final Widget child;

  const PropRow({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: context.tTextMuted),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// GreenSwitch
// ─────────────────────────────────────────────────────────────────────────────

class GreenSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GreenSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerLeft,
        child: Switch(value: value, onChanged: onChanged),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LayerTypeBadge
// ─────────────────────────────────────────────────────────────────────────────

class LayerTypeBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const LayerTypeBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: const BorderRadius.all(kRadiusSm),
        ),
        child: Icon(icon, size: size * 0.5, color: color),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer type maps
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, Color> kLayerTypeColors = {
  'text':     Color(0xFF378ADD),
  'clock':    Color(0xFFEF9F27),
  'gif':      Color.fromARGB(255, 122, 33, 195),
  'spotify':  Color(0xFF1DB954),
  'pomodoro': Color(0xFFFFCC00),
};

const Map<String, IconData> kLayerTypeIcons = {
  'text':     Icons.text_fields_rounded,
  'clock':    Icons.schedule_rounded,
  'gif':      Icons.gif_box_rounded,
  'spotify':  Icons.music_note_rounded,
  'pomodoro': Icons.timer_rounded,
};