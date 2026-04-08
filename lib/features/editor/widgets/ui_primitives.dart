import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

const kGreen       = Color(0xFF21C32C);
const kSurface     = Color(0xFFF8F7F3);
const kSurfaceLow  = Color(0xFFECEAE3);
const kBorder      = Color(0xFFE0DDD6);
const kTextPrimary = Color(0xFF1A1A1A);
const kTextMuted   = Color(0xFF888580);
const kTextDim     = Color(0xFFB0ADA8);

const kRadiusSm = Radius.circular(6);
const kRadiusMd = Radius.circular(9);
const kRadiusLg = Radius.circular(12);

const kPanelBorder = BorderSide(color: kBorder);

// ─────────────────────────────────────────────────────────────────────────────
// PanelShell — the outer wrapper every side/bottom panel uses
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
          color: kSurface,
          borderRadius: BorderRadius.all(kRadiusLg),
          border: Border.all(color: kBorder),
        ),
        child: child,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionLabel — uppercase panel section heading
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
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
            color: kTextDim,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hairline — a 1-pixel divider
// ─────────────────────────────────────────────────────────────────────────────

class Hairline extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  const Hairline({super.key, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        height: 1,
        color: kBorder,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PropRow — label + control row used throughout the toolbox
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
                style: const TextStyle(fontSize: 12, color: kTextMuted),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// GreenSwitch — a styled Switch that matches the theme
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
// LayerTypeBadge — colored icon badge in layer list and palette
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
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.all(kRadiusSm),
        ),
        child: Icon(icon, size: size * 0.5, color: color),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer type color map
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