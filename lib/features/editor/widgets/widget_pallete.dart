import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';

class WidgetPalette extends ConsumerWidget {
  const WidgetPalette({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Colors.white.withOpacity(.35),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WIDGETS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .08,
              color: Colors.black.withOpacity(.45),
            ),
          ),
          const SizedBox(height: 8),
          _PaletteButton(
            icon: Icons.text_fields,
            label: 'Text',
            onTap: () => ref.read(sceneProvider.notifier).addTextLayer(),
          ),
          _PaletteButton(
            icon: Icons.schedule,
            label: 'Clock',
            onTap: () => ref.read(sceneProvider.notifier).addClockLayer(),
          ),
          _PaletteButton(
            icon: Icons.gif_box,
            label: 'GIF',
            onTap: () => ref.read(sceneProvider.notifier).addGifLayer(),
          ),
          _PaletteButton(
            icon: Icons.music_note,
            label: 'Spotify',
            onTap: () => ref.read(sceneProvider.notifier).addSpotifyLayer(),
          ),
          _PaletteButton(
            icon: Icons.timer,
            label: 'Pomodoro',
            onTap: () => ref.read(sceneProvider.notifier).addPomodoroLayer(),
          ),
        ],
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PaletteButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size.fromHeight(40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}