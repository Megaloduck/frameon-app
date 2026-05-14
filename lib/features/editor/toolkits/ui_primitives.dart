import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static design tokens — only what genuinely cannot use a BuildContext:
// CustomPainter, const constructors, geometry constants.
// For everything else use the ThemeTokens extension below.
// ─────────────────────────────────────────────────────────────────────────────

const kGreen    = Color(0xFF21C32C);

const kRadiusSm = Radius.circular(6);
const kRadiusMd = Radius.circular(9);
const kRadiusLg = Radius.circular(12);

// ─────────────────────────────────────────────────────────────────────────────
// ThemeTokens — context-aware token accessor backed by AppColors extension
// ─────────────────────────────────────────────────────────────────────────────

extension ThemeTokens on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  Color get tSurface     => colors.surface;
  Color get tSurfaceLow  => colors.surfaceLow;
  Color get tBorder      => colors.border;
  Color get tTextPrimary => colors.textPrimary;
  Color get tTextMuted   => colors.textMuted;
  Color get tTextDim     => colors.textDim;

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
            fontSize:      9,
            fontWeight:    FontWeight.w700,
            letterSpacing: 0.12,
            color:         context.tTextDim,
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
  'text':        Color(0xFF378ADD),
  'clock':       Color(0xFFEF9F27),
  'gif':         Color.fromARGB(255, 122, 33, 195),
  'spotify':     Color(0xFF1DB954),
  'pomodoro':    Color(0xFFFFCC00),
  'slotMachine': Color(0xFFE91E63),   
};

const Map<String, IconData> kLayerTypeIcons = {
  'text':        Icons.text_fields_rounded,
  'clock':       Icons.schedule_rounded,
  'gif':         Icons.gif_box_rounded,
  'spotify':     Icons.music_note_rounded,
  'pomodoro':    Icons.timer_rounded,
  'slotMachine': Icons.casino_rounded,  
};