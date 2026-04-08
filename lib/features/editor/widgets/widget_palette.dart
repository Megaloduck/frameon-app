import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WidgetPalette  (left panel, w = 160 px)
//
// Layout change from original:
//   - Removed tonal FilledButton in favour of a plain row with a typed icon
//     badge, label, and a subtle "+" affordance on hover.
//   - A short section divider groups widgets by category if needed later.
//   - No more per-button card border — the list itself is the boundary.
// ─────────────────────────────────────────────────────────────────────────────

class WidgetPalette extends ConsumerWidget {
  const WidgetPalette({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sceneProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Widgets'),
        const Hairline(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _PaletteEntry(
                icon:    Icons.text_fields_rounded,
                color:   const Color(0xFF378ADD),
                label:   'Text',
                onTap:   notifier.addTextLayer,
              ),
              _PaletteEntry(
                icon:    Icons.schedule_rounded,
                color:   const Color(0xFFEF9F27),
                label:   'Clock',
                onTap:   notifier.addClockLayer,
              ),
              _PaletteEntry(
                icon:    Icons.gif_box_rounded,
                color:   const Color.fromARGB(255, 122, 33, 195),
                label:   'GIF / Image',
                onTap:   notifier.addGifLayer,
              ),
              _PaletteEntry(
                icon:    Icons.music_note_rounded,
                color:   const Color(0xFF1DB954),
                label:   'Spotify',
                onTap:   notifier.addSpotifyLayer,
              ),
              _PaletteEntry(
                icon:    Icons.timer_rounded,
                color:   const Color(0xFFFFCC00),
                label:   'Pomodoro',
                onTap:   notifier.addPomodoroLayer,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Single palette entry ──────────────────────────────────────────────────────

class _PaletteEntry extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _PaletteEntry({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  State<_PaletteEntry> createState() => _PaletteEntryState();
}

class _PaletteEntryState extends State<_PaletteEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter:  (_) => setState(() => _hovered = true),
        onExit:   (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: _hovered ? widget.color.withOpacity(0.07) : Colors.transparent,
              borderRadius: const BorderRadius.all(kRadiusMd),
            ),
            child: Row(
              children: [
                LayerTypeBadge(icon: widget.icon, color: widget.color, size: 30),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _hovered ? kTextPrimary : kTextMuted,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 100),
                  child: Icon(Icons.add_rounded, size: 14, color: widget.color),
                ),
              ],
            ),
          ),
        ),
      );
}