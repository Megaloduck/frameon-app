import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import 'color_picker.dart';

class ToolboxPanel extends ConsumerWidget {
  const ToolboxPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _Empty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: _title(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: switch (layer.type) {
              LayerType.text     => _TextBox(layer: layer as TextLayer),
              LayerType.clock    => _ClockBox(layer: layer as ClockLayer),
              LayerType.gif      => _GifBox(layer: layer as GifLayer),
              LayerType.spotify  => _SpotifyBox(layer: layer as SpotifyLayer),
              LayerType.pomodoro => _PomodoroBox(layer: layer as PomodoroLayer),
            },
          ),
        ),
      ],
    );
  }

  String _title(LayerType t) => switch (t) {
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
                fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .08,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.5))),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Text('Select a layer to edit',
            style: TextStyle(fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.35))),
      );
}

Widget _row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: control),
      ]),
    );

Widget _toggle(bool value, ValueChanged<bool> onChange) => Align(
      alignment: Alignment.centerLeft,
      child: Switch(
          value: value, onChanged: onChange,
          activeColor: const Color(0xFF21C32C),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );

Widget _colorBtn(BuildContext ctx, Color color, ValueChanged<Color> onChange) =>
    GestureDetector(
      onTap: () async {
        final c = await showColorPicker(ctx, initialColor: color);
        if (c != null) onChange(c);
      },
      child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black.withOpacity(.2)))),
    );

Widget _dropdown<T extends Enum>(List<T> values, T current, ValueChanged<T> onChange) =>
    DropdownButton<T>(
      value: current, isExpanded: true, isDense: true,
      items: values.map((e) => DropdownMenuItem(value: e,
          child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
      onChanged: (v) { if (v != null) onChange(v); },
    );

// ── Text ──────────────────────────────────────────────────────────────────────

class _TextBox extends ConsumerWidget {
  final TextLayer layer;
  const _TextBox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Color', _colorBtn(context, layer.color,
          (c) => n.updateLayer(layer.copyWith(color: c)))),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ColorPicker(
          color: layer.color,
          onChanged: (c) => n.updateLayer(layer.copyWith(color: c)),
        ),
      ),
      _row('Text', TextField(
        controller: TextEditingController(text: layer.text),
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(isDense: true),
        onSubmitted: (v) => n.updateLayer(layer.copyWith(text: v)),
      )),
      _row('Font', _dropdown(PixelFontStyle.values, layer.fontStyle,
          (v) => n.updateLayer(layer.copyWith(fontStyle: v)))),
      _row('Effect', _dropdown(AnimationEffect.values, layer.effect,
          (v) => n.updateLayer(layer.copyWith(effect: v)))),
      // Speed slider — only relevant when effect is scroll/blink
      if (layer.effect != AnimationEffect.none) ...[
        _row('Speed', Slider(
          value: layer.effectSpeedMs.toDouble(),
          min: 20, max: 500,
          divisions: 24,
          label: '${layer.effectSpeedMs}ms',
          activeColor: const Color(0xFF21C32C),
          onChanged: (v) => n.updateLayer(layer.copyWith(effectSpeedMs: v.round())),
        )),
      ],
      _row('Align', _dropdown(TextAlignment.values, layer.alignment,
          (v) => n.updateLayer(layer.copyWith(alignment: v)))),
      _row('Opacity', Slider(
        value: layer.opacity, min: 0, max: 1,
        activeColor: const Color(0xFF21C32C),
        onChanged: (v) => n.updateLayer(layer.copyWith(opacity: v)),
      )),
    ]);
  }
}

// ── Clock ─────────────────────────────────────────────────────────────────────

class _ClockBox extends ConsumerWidget {
  final ClockLayer layer;
  const _ClockBox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Color', _colorBtn(context, layer.color,
          (c) => n.updateLayer(layer.copyWith(color: c)))),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ColorPicker(
          color: layer.color,
          onChanged: (c) => n.updateLayer(layer.copyWith(color: c)),
        ),
      ),
      _row('Format', _dropdown(ClockFormat.values, layer.format,
          (v) => n.updateLayer(layer.copyWith(format: v)))),
      _row('Align', _dropdown(ClockAlignment.values, layer.alignment,
          (v) => n.updateLayer(layer.copyWith(alignment: v)))),
      _row('Show date',    _toggle(layer.showDate,    (v) => n.updateLayer(layer.copyWith(showDate: v)))),
      _row('Show seconds', _toggle(layer.showSeconds, (v) => n.updateLayer(layer.copyWith(showSeconds: v)))),
      _row('Blink colon',  _toggle(layer.blinkColon,  (v) => n.updateLayer(layer.copyWith(blinkColon: v)))),
    ]);
  }
}

// ── GIF ───────────────────────────────────────────────────────────────────────

class _GifBox extends ConsumerWidget {
  final GifLayer layer;
  const _GifBox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n        = ref.read(sceneProvider.notifier);
    final renderer = ref.read(matrixRendererProvider);
    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['gif', 'png', 'jpg', 'jpeg'],
              withData: true, // ensures bytes available on all platforms
            );
            if (result == null) return;
            final pf = result.files.single;
            final String key = pf.path ?? pf.name;
            // Register bytes with renderer so it can decode immediately
            if (pf.bytes != null) renderer.addAssetBytes(key, pf.bytes!);
            n.updateLayer(layer.copyWith(filePath: key));
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
      if (layer.filePath != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextButton(
            onPressed: () {
              renderer.removeAsset(layer.filePath!);
              n.updateLayer(layer.copyWith(clearFilePath: true));
            },
            child: const Text('Remove file',
                style: TextStyle(fontSize: 11, color: Colors.red)),
          ),
        ),
      const SizedBox(height: 6),
      _row('Layout',    _dropdown(MediaLayout.values, layer.layout,
          (v) => n.updateLayer(layer.copyWith(layout: v)))),
      _row('Dithering', _toggle(layer.dithering,   (v) => n.updateLayer(layer.copyWith(dithering: v)))),
      _row('Grayscale', _toggle(layer.grayscale,   (v) => n.updateLayer(layer.copyWith(grayscale: v)))),
      _row('Invert',    _toggle(layer.invertColor, (v) => n.updateLayer(layer.copyWith(invertColor: v)))),
    ]);
  }
}

// ── Spotify ───────────────────────────────────────────────────────────────────

class _SpotifyBox extends ConsumerWidget {
  final SpotifyLayer layer;
  const _SpotifyBox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n    = ref.read(sceneProvider.notifier);
    final spot = ref.watch(spotifyServiceProvider);
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(.04),
            borderRadius: BorderRadius.circular(8)),
        child: spot.isConnected
            ? Row(children: [
                const Icon(Icons.music_note, size: 16, color: Color(0xFF1DB954)),
                const SizedBox(width: 6),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spot.currentTrackTitle ?? 'Playing',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    Text(spot.currentArtist ?? '',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        overflow: TextOverflow.ellipsis),
                  ],
                )),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: () => ref.read(spotifyServiceProvider.notifier).refresh(),
                  tooltip: 'Refresh track',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ])
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.white),
                  onPressed: () =>
                      ref.read(spotifyServiceProvider.notifier).connect(),
                  child: const Text('Connect with Spotify',
                      style: TextStyle(fontSize: 13)),
                ),
              ),
      ),
      const SizedBox(height: 10),
      _row('Layout',        _dropdown(SpotifyLayout.values, layer.layout,
          (v) => n.updateLayer(layer.copyWith(layout: v)))),
      _row('Show title',    _toggle(layer.showTitle,    (v) => n.updateLayer(layer.copyWith(showTitle: v)))),
      _row('Show artist',   _toggle(layer.showArtist,   (v) => n.updateLayer(layer.copyWith(showArtist: v)))),
      _row('Show progress', _toggle(layer.showProgress, (v) => n.updateLayer(layer.copyWith(showProgress: v)))),
    ]);
  }
}

// ── Pomodoro ──────────────────────────────────────────────────────────────────

class _PomodoroBox extends ConsumerWidget {
  final PomodoroLayer layer;
  const _PomodoroBox({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(children: [
      _row('Focus color', _colorBtn(context, layer.focusColor,
          (c) => n.updateLayer(layer.copyWith(focusColor: c)))),
      _row('Break color', _colorBtn(context, layer.breakColor,
          (c) => n.updateLayer(layer.copyWith(breakColor: c)))),
      const Divider(height: 16),
      _row('Focus (min)',  _stepper(layer.focusDurationMinutes,    (v) => n.updateLayer(layer.copyWith(focusDurationMinutes: v)))),
      _row('Short break',  _stepper(layer.shortBreakMinutes,       (v) => n.updateLayer(layer.copyWith(shortBreakMinutes: v)))),
      _row('Long break',   _stepper(layer.longBreakMinutes,        (v) => n.updateLayer(layer.copyWith(longBreakMinutes: v)))),
      _row('Sessions',     _stepper(layer.sessionsBeforeLongBreak, (v) => n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v)))),
      const Divider(height: 16),
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