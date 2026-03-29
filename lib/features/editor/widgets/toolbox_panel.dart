import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';

class ToolboxPanel extends ConsumerWidget {
  const ToolboxPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: _titleFor(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: switch (layer.type) {
              LayerType.text     => _TextToolbox(layer: layer as TextLayer),
              LayerType.clock    => _ClockToolbox(layer: layer as ClockLayer),
              LayerType.gif      => _GifToolbox(layer: layer as GifLayer),
              LayerType.spotify  => _SpotifyToolbox(layer: layer as SpotifyLayer),
              LayerType.pomodoro => _PomodoroToolbox(layer: layer as PomodoroLayer),
            },
          ),
        ),
      ],
    );
  }

  String _titleFor(LayerType t) => switch (t) {
        LayerType.text     => 'TEXT COLOR',
        LayerType.clock    => 'CLOCK COLOR',
        LayerType.gif      => 'UPLOAD FILES',
        LayerType.spotify  => 'SPOTIFY SETTINGS',
        LayerType.pomodoro => 'POMODORO SETTINGS',
      };
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Text(title,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                letterSpacing: .08,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.5))),
      );
}

class _EmptyToolbox extends StatelessWidget {
  const _EmptyToolbox();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('Select a layer to edit',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.35))),
      );
}

Widget _row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: control),
      ]),
    );

Widget _toggle(bool value, ValueChanged<bool> onChanged) => Align(
      alignment: Alignment.centerLeft,
      child: Switch(
        value: value, onChanged: onChanged,
        activeColor: const Color(0xFF21C32C),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

// ── Per-type toolboxes ────────────────────────────────────────────────────────

class _TextToolbox extends ConsumerWidget {
  final TextLayer layer;
  const _TextToolbox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Text', TextField(
        controller: TextEditingController(text: layer.text),
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(isDense: true),
        onSubmitted: (v) => n.updateLayer(layer.copyWith(text: v)),
      )),
      _row('Effect', DropdownButton<AnimationEffect>(
        value: layer.effect, isExpanded: true, isDense: true,
        items: AnimationEffect.values.map((e) =>
            DropdownMenuItem(value: e, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => v != null ? n.updateLayer(layer.copyWith(effect: v)) : null,
      )),
      _row('Align', DropdownButton<TextAlignment>(
        value: layer.alignment, isExpanded: true, isDense: true,
        items: TextAlignment.values.map((e) =>
            DropdownMenuItem(value: e, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => v != null ? n.updateLayer(layer.copyWith(alignment: v)) : null,
      )),
      _row('Opacity', Slider(
        value: layer.opacity, min: 0, max: 1,
        activeColor: const Color(0xFF21C32C),
        onChanged: (v) => n.updateLayer(layer.copyWith(opacity: v)),
      )),
    ]);
  }
}

class _ClockToolbox extends ConsumerWidget {
  final ClockLayer layer;
  const _ClockToolbox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Format', DropdownButton<ClockFormat>(
        value: layer.format, isExpanded: true, isDense: true,
        items: ClockFormat.values.map((e) =>
            DropdownMenuItem(value: e, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => v != null ? n.updateLayer(layer.copyWith(format: v)) : null,
      )),
      _row('Show date',    _toggle(layer.showDate,    (v) => n.updateLayer(layer.copyWith(showDate: v)))),
      _row('Show seconds', _toggle(layer.showSeconds, (v) => n.updateLayer(layer.copyWith(showSeconds: v)))),
      _row('Blink colon',  _toggle(layer.blinkColon,  (v) => n.updateLayer(layer.copyWith(blinkColon: v)))),
      _row('Align', DropdownButton<ClockAlignment>(
        value: layer.alignment, isExpanded: true, isDense: true,
        items: ClockAlignment.values.map((e) =>
            DropdownMenuItem(value: e, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => v != null ? n.updateLayer(layer.copyWith(alignment: v)) : null,
      )),
    ]);
  }
}

class _GifToolbox extends ConsumerWidget {
  final GifLayer layer;
  const _GifToolbox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      // File picker — wired via file_picker package
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['gif', 'png', 'jpg', 'jpeg'],
            );
            if (result != null && result.files.single.path != null) {
              n.updateLayer(layer.copyWith(filePath: result.files.single.path));
            }
          },
          icon: const Icon(Icons.upload_file, size: 16),
          label: Text(
            layer.filePath != null
                ? layer.filePath!.split('/').last.split('\\').last
                : 'Upload JPG · PNG · GIF',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      const SizedBox(height: 8),
      _row('Layout', DropdownButton<MediaLayout>(
        value: layer.layout, isExpanded: true, isDense: true,
        items: MediaLayout.values.map((e) =>
            DropdownMenuItem(value: e, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => v != null ? n.updateLayer(layer.copyWith(layout: v)) : null,
      )),
      _row('Dithering',  _toggle(layer.dithering,   (v) => n.updateLayer(layer.copyWith(dithering: v)))),
      _row('Grayscale',  _toggle(layer.grayscale,   (v) => n.updateLayer(layer.copyWith(grayscale: v)))),
      _row('Invert',     _toggle(layer.invertColor, (v) => n.updateLayer(layer.copyWith(invertColor: v)))),
    ]);
  }
}

class _SpotifyToolbox extends ConsumerWidget {
  final SpotifyLayer layer;
  const _SpotifyToolbox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Layout', DropdownButton<SpotifyLayout>(
        value: layer.layout, isExpanded: true, isDense: true,
        items: SpotifyLayout.values.map((e) =>
            DropdownMenuItem(value: e, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) => v != null ? n.updateLayer(layer.copyWith(layout: v)) : null,
      )),
      _row('Show title',    _toggle(layer.showTitle,    (v) => n.updateLayer(layer.copyWith(showTitle: v)))),
      _row('Show artist',   _toggle(layer.showArtist,   (v) => n.updateLayer(layer.copyWith(showArtist: v)))),
      _row('Show progress', _toggle(layer.showProgress, (v) => n.updateLayer(layer.copyWith(showProgress: v)))),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.white),
          onPressed: () {
            // TODO: launch Spotify OAuth flow
          },
          child: const Text('Connect with Spotify', style: TextStyle(fontSize: 13)),
        ),
      ),
    ]);
  }
}

class _PomodoroToolbox extends ConsumerWidget {
  final PomodoroLayer layer;
  const _PomodoroToolbox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Focus (min)',  _stepper(layer.focusDurationMinutes,  (v) => n.updateLayer(layer.copyWith(focusDurationMinutes: v)))),
      _row('Short break',  _stepper(layer.shortBreakMinutes,     (v) => n.updateLayer(layer.copyWith(shortBreakMinutes: v)))),
      _row('Long break',   _stepper(layer.longBreakMinutes,      (v) => n.updateLayer(layer.copyWith(longBreakMinutes: v)))),
      _row('Sessions',     _stepper(layer.sessionsBeforeLongBreak,(v) => n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v)))),
      _row('Show seconds', _toggle(layer.showSeconds, (v) => n.updateLayer(layer.copyWith(showSeconds: v)))),
      _row('Blink color',  _toggle(layer.blinkColor,  (v) => n.updateLayer(layer.copyWith(blinkColor: v)))),
    ]);
  }

  Widget _stepper(int value, ValueChanged<int> onChange) => Row(children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 14),
          onPressed: value > 1 ? () => onChange(value - 1) : null,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
        ),
        SizedBox(width: 28,
            child: Text('$value', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13))),
        IconButton(
          icon: const Icon(Icons.add, size: 14),
          onPressed: () => onChange(value + 1),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
        ),
      ]);
}