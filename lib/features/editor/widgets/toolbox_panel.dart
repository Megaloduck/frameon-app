import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import 'color_picker.dart';
import 'gif_bytes_provider.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry-points used by editor_page.dart
// ─────────────────────────────────────────────────────────────────────────────

class ToolboxLeftPanel extends ConsumerWidget {
  const ToolboxLeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();
    return _ToolboxLeft(layer: layer);
  }
}

class ToolboxRightPanel extends ConsumerWidget {
  const ToolboxRightPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();
    return _ToolboxRight(layer: layer);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT sub-panel
// ─────────────────────────────────────────────────────────────────────────────

class _ToolboxLeft extends ConsumerWidget {
  final Layer layer;
  const _ToolboxLeft({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(_leftTitle(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: switch (layer.type) {
              LayerType.text     => _TextLeft(layer: layer as TextLayer, n: n),
              LayerType.clock    => _ClockLeft(layer: layer as ClockLayer, n: n),
              LayerType.gif      => _GifLeft(layer: layer as GifLayer, n: n),
              LayerType.spotify  => _SpotifyLeft(layer: layer as SpotifyLayer),
              // _PomodoroLeft fetches its own live layer via ref.watch —
              // this is the key fix so color swatches update immediately.
              LayerType.pomodoro => const _PomodoroLeft(),
            },
          ),
        ),
      ],
    );
  }

  String _leftTitle(LayerType t) => switch (t) {
        LayerType.text     => 'TEXT STYLE',
        LayerType.clock    => 'CLOCK STYLE',
        LayerType.gif      => 'UPLOAD FILES',
        LayerType.spotify  => 'SPOTIFY SETTINGS',
        LayerType.pomodoro => 'POMODORO SETTINGS',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT sub-panel
// ─────────────────────────────────────────────────────────────────────────────

class _ToolboxRight extends ConsumerWidget {
  final Layer layer;
  const _ToolboxRight({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(sceneProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(_rightTitle(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: switch (layer.type) {
              LayerType.text     => _TextRight(layer: layer as TextLayer, n: n),
              LayerType.clock    => _ClockRight(layer: layer as ClockLayer, n: n),
              LayerType.gif      => _GifRight(layer: layer as GifLayer, n: n),
              LayerType.spotify  => _SpotifyRight(layer: layer as SpotifyLayer, n: n),
              LayerType.pomodoro => const _PomodoroRight(),
            },
          ),
        ),
      ],
    );
  }

  String _rightTitle(LayerType t) => switch (t) {
        LayerType.text     => 'ANIMATION EFFECT',
        LayerType.clock    => 'DISPLAY FORMAT',
        LayerType.gif      => 'MEDIA LAYOUT',
        LayerType.spotify  => 'SPOTIFY LAYOUT',
        LayerType.pomodoro => 'POMODORO LAYOUT',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared chrome
// ─────────────────────────────────────────────────────────────────────────────

class _SubHeader extends StatelessWidget {
  final String title;
  const _SubHeader(this.title);
  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(border: Border(bottom: kPanelBorder)),
        child: Text(title,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.12, color: kTextDim)),
      );
}

class _EmptyToolbox extends StatelessWidget {
  const _EmptyToolbox();
  @override
  Widget build(BuildContext context) => Center(
        child: Text('Select a layer to edit',
            style: TextStyle(fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper widgets
// ─────────────────────────────────────────────────────────────────────────────

Widget _greenDropdown<T extends Enum>(
  List<T> values, T current, ValueChanged<T> onChange,
) =>
    Container(
      decoration: BoxDecoration(
        color: kGreen.withOpacity(0.1),
        border: Border.all(color: kGreen.withOpacity(0.5)),
        borderRadius: const BorderRadius.all(kRadiusSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: current, isExpanded: true, isDense: true,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kGreen),
          dropdownColor: kSurface,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: kGreen),
          items: values.map((e) => DropdownMenuItem(
                value: e, child: Text(e.name.toUpperCase()))).toList(),
          onChanged: (v) { if (v != null) onChange(v); },
        ),
      ),
    );

class _SegAlign extends StatelessWidget {
  final TextAlignment current;
  final ValueChanged<TextAlignment> onChange;
  const _SegAlign({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) => Row(
        children: TextAlignment.values.map((v) {
          final active = v == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChange(v),
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  color: active ? kGreen : kSurface,
                  border: Border.all(color: active ? kGreen : kBorder),
                  borderRadius: BorderRadius.horizontal(
                    left:  v == TextAlignment.left  ? const Radius.circular(6) : Radius.zero,
                    right: v == TextAlignment.right ? const Radius.circular(6) : Radius.zero,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(v.name.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: active ? Colors.white : kTextMuted)),
              ),
            ),
          );
        }).toList(),
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: kTextPrimary))),
          Transform.scale(
            scale: 0.75, alignment: Alignment.centerRight,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ]),
      );
}

class _SpeedSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _SpeedSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 3),
          child: Slider(value: value.clamp(10, 500), min: 10, max: 500, onChanged: onChanged),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          Text('10ms fast',  style: TextStyle(fontSize: 9, color: kTextDim)),
          Text('500ms slow', style: TextStyle(fontSize: 9, color: kTextDim)),
        ]),
      ]);
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min, max;
  const _Stepper({required this.label, required this.value,
      required this.onChanged, this.unit = '', this.min = 1, this.max = 99});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: kTextPrimary))),
          _StepBtn(icon: Icons.remove_rounded, enabled: value > min, onTap: () => onChanged(value - 1)),
          SizedBox(width: 40, child: Text('$value$unit', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          _StepBtn(icon: Icons.add_rounded, enabled: value < max, onTap: () => onChanged(value + 1)),
        ]),
      );
}

class _StepBtn extends StatelessWidget {
  final IconData icon; final bool enabled; final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(border: Border.all(color: kBorder),
              borderRadius: const BorderRadius.all(kRadiusSm), color: kSurface),
          child: Icon(icon, size: 13, color: enabled ? kTextMuted : kTextDim),
        ),
      );
}

class _TransportBtn extends StatelessWidget {
  final IconData icon; final bool filled; final VoidCallback onTap;
  const _TransportBtn({required this.icon, required this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: filled ? kGreen : kSurface, shape: BoxShape.circle,
            border: Border.all(color: filled ? kGreen : kBorder),
          ),
          child: Icon(icon, size: 17, color: filled ? Colors.white : kTextMuted),
        ),
      );
}

/// Color swatch button.
///
/// Fix: the old version re-wrapped the returned color with .withOpacity()
/// which could zero out the alpha for certain hues (blue being most visible).
/// Now we pass the picked color through unchanged — showColorPickerSheet
/// already returns a fully valid Color with correct alpha.
Widget _colorBtn(BuildContext ctx, Color color, ValueChanged<Color> onChange) =>
    GestureDetector(
      onTap: () async {
        final picked = await showColorPickerSheet(ctx, initialColor: color);
        if (picked != null) onChange(picked);
      },
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(color: Colors.black.withOpacity(0.15)),
        ),
      ),
    );

class TbLabel extends StatelessWidget {
  final String text;
  const TbLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
          letterSpacing: 0.1, color: kTextDim));
}

class _TbDropdown<T extends Enum> extends StatelessWidget {
  final List<T> values; final T current; final ValueChanged<T> onChange;
  const _TbDropdown({required this.values, required this.current, required this.onChange});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: current, isDense: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: const BorderSide(color: kBorder)),
        ),
        style: const TextStyle(fontSize: 12, color: kTextPrimary),
        items: values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
        onChanged: (v) { if (v != null) onChange(v); },
      );
}

class _TbTextField extends StatefulWidget {
  final String value; final ValueChanged<String> onSubmitted;
  const _TbTextField({required this.value, required this.onSubmitted});
  @override
  State<_TbTextField> createState() => _TbTextFieldState();
}

class _TbTextFieldState extends State<_TbTextField> {
  late final TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.value); }
  @override void didUpdateWidget(_TbTextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) _ctrl.text = widget.value;
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: const BorderSide(color: kGreen, width: 1.5)),
        ),
        onSubmitted: widget.onSubmitted,
        onEditingComplete: () => widget.onSubmitted(_ctrl.text),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT
// ─────────────────────────────────────────────────────────────────────────────

class _TextLeft extends StatelessWidget {
  final TextLayer layer; final SceneNotifier n;
  const _TextLeft({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Changed: Color picker as simple row with color box (like pomodoro)
          Row(children: [
            _colorBtn(context, layer.color, (c) => n.updateLayer(layer.copyWith(color: c))),
            const SizedBox(width: 8),
            const Text('Text Color', style: TextStyle(fontSize: 11, color: kTextMuted)),
          ]),
          const SizedBox(height: 10),
          TbLabel('Font Style'), const SizedBox(height: 4),
          _TbDropdown(values: PixelFontStyle.values, current: layer.fontStyle,
              onChange: (v) => n.updateLayer(layer.copyWith(fontStyle: v))),
          const SizedBox(height: 8),
          TbLabel('Display Text'), const SizedBox(height: 4),
          _TbTextField(value: layer.text, onSubmitted: (v) => n.updateLayer(layer.copyWith(text: v))),
        ],
      );
}

class _TextRight extends StatelessWidget {
  final TextLayer layer; final SceneNotifier n;
  const _TextRight({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<AnimationEffect>(AnimationEffect.values, layer.effect,
              (v) => n.updateLayer(layer.copyWith(effect: v))),
          const SizedBox(height: 12),
          if (layer.effect != AnimationEffect.none) ...[
            TbLabel('Speed'),
            _SpeedSlider(value: layer.effectSpeedMs.toDouble(),
                onChanged: (v) => n.updateLayer(layer.copyWith(effectSpeedMs: v.round()))),
            const SizedBox(height: 8),
          ],
          TbLabel('Alignment'), const SizedBox(height: 4),
          _SegAlign(current: layer.alignment,
              onChange: (v) => n.updateLayer(layer.copyWith(alignment: v))),
          const SizedBox(height: 12),
          TbLabel('Opacity'),
          Slider(value: layer.opacity, min: 0, max: 1,
              onChanged: (v) => n.updateLayer(layer.copyWith(opacity: v))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOCK
// ─────────────────────────────────────────────────────────────────────────────

class _ClockLeft extends StatelessWidget {
  final ClockLayer layer; final SceneNotifier n;
  const _ClockLeft({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TbLabel('Element Colors'),
          const SizedBox(height: 8),
          _ColorRow(label: 'Hours', color: layer.hoursColor,
              onChanged: (c) => n.updateLayer(layer.copyWith(hoursColor: c))),
          const SizedBox(height: 6),
          _ColorRow(label: 'Minutes', color: layer.minutesColor,
              onChanged: (c) => n.updateLayer(layer.copyWith(minutesColor: c))),
          const SizedBox(height: 6),
          if (layer.showSeconds) ...[
            _ColorRow(label: 'Seconds', color: layer.secondsColor,
                onChanged: (c) => n.updateLayer(layer.copyWith(secondsColor: c))),
            const SizedBox(height: 6),
          ],
          if (layer.showDate) ...[
            _ColorRow(label: 'Date', color: layer.dateColor,
                onChanged: (c) => n.updateLayer(layer.copyWith(dateColor: c))),
            const SizedBox(height: 6),
          ],
          _ColorRow(label: 'Colon', color: layer.colonColor,
              onChanged: (c) => n.updateLayer(layer.copyWith(colonColor: c))),
        ],
      );
}

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorRow({required this.label, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: kTextMuted))),
          _colorBtn(context, color, onChanged),
        ],
      );
}

class _ClockRight extends StatelessWidget {
  final ClockLayer layer; final SceneNotifier n;
  const _ClockRight({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<_TzOpt>(_TzOpt.values,
            _TzOpt.values.firstWhere((t) => t.name == layer.timezone, orElse: () => _TzOpt.local),
            (v) => n.updateLayer(layer.copyWith(timezone: v.name))),
          const SizedBox(height: 10),
          TbLabel('Alignment'), const SizedBox(height: 4),
          Row(children: ClockAlignment.values.map((v) {
            final active = v == layer.alignment;
            return Expanded(child: GestureDetector(
              onTap: () => n.updateLayer(layer.copyWith(alignment: v)),
              child: Container(height: 28,
                decoration: BoxDecoration(
                  color: active ? kGreen : kSurface,
                  border: Border.all(color: active ? kGreen : kBorder),
                  borderRadius: BorderRadius.horizontal(
                    left:  v == ClockAlignment.left  ? const Radius.circular(6) : Radius.zero,
                    right: v == ClockAlignment.right ? const Radius.circular(6) : Radius.zero),
                ),
                alignment: Alignment.center,
                child: Text(v.name.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: active ? Colors.white : kTextMuted)),
              ),
            ));
          }).toList()),
          const SizedBox(height: 10),
          _ToggleRow(label: '24-hour format', value: layer.format == ClockFormat.h24,
              onChanged: (v) => n.updateLayer(layer.copyWith(format: v ? ClockFormat.h24 : ClockFormat.h12))),
          _ToggleRow(label: 'Show date',    value: layer.showDate,    onChanged: (v) => n.updateLayer(layer.copyWith(showDate: v))),
          _ToggleRow(label: 'Show seconds', value: layer.showSeconds, onChanged: (v) => n.updateLayer(layer.copyWith(showSeconds: v))),
          _ToggleRow(label: 'Blink colon',  value: layer.blinkColon,  onChanged: (v) => n.updateLayer(layer.copyWith(blinkColon: v))),
        ],
      );
}

enum _TzOpt { local, utc, bangkok, tokyo, london, newYork }

// ─────────────────────────────────────────────────────────────────────────────
// GIF
// ─────────────────────────────────────────────────────────────────────────────

class _GifLeft extends ConsumerStatefulWidget {
  final GifLayer layer; final SceneNotifier n;
  const _GifLeft({required this.layer, required this.n});
  @override
  ConsumerState<_GifLeft> createState() => _GifLeftState();
}

class _GifLeftState extends ConsumerState<_GifLeft> {
  bool _loading = false;

  Future<void> _pick() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
    } catch (e) { _snack('Picker error: $e'); return; }

    if (result == null || !mounted) return;
    final pf = result.files.single;

    setState(() => _loading = true);
    try {
      Uint8List? bytes = pf.bytes;
      if ((bytes == null || bytes.isEmpty) && !kIsWeb && pf.path != null) {
        bytes = await compute<String, Uint8List>(
          (path) => File(path).readAsBytesSync(), pf.path!);
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) { _snack('Could not read file.'); return; }

      final String key = pf.path ?? pf.name;
      ref.read(gifBytesProvider.notifier).set(key, bytes);
      ref.read(matrixRendererProvider).addAssetBytes(key, bytes);
      widget.n.updateLayer(widget.layer.copyWith(filePath: key));
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _remove() {
    final key = widget.layer.filePath;
    if (key == null) return;
    ref.read(gifBytesProvider.notifier).remove(key);
    ref.read(matrixRendererProvider).removeAsset(key);
    widget.n.updateLayer(widget.layer.copyWith(clearFilePath: true));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final key     = widget.layer.filePath;
    final hasFile = key != null;
    final allBytes = ref.watch(gifBytesProvider);
    final bytes   = hasFile ? allBytes[key] : null;
    final fileName = hasFile ? key.split('/').last.split('\\').last : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(
            child: Text('JPG · PNG · GIF',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    letterSpacing: 0.08, color: kTextDim)),
          ),
        ]),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _loading ? null : _pick,
          child: Container(
            height: 115,
            decoration: BoxDecoration(
              color: hasFile ? Colors.black : kSurfaceLow,
              borderRadius: const BorderRadius.all(kRadiusMd),
              border: hasFile ? null : Border.all(color: kBorder, style: BorderStyle.solid),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasFile && bytes != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                    Positioned(
                      top: 6, right: 6,
                      child: GestureDetector(
                        onTap: _pick,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: const BorderRadius.all(kRadiusSm),
                          ),
                          child: const Text('CHANGE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_loading)
                      const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                    else
                      const Icon(Icons.upload_file_rounded, size: 28, color: kTextDim),
                    const SizedBox(height: 6),
                    Text(_loading ? 'Loading…' : 'Click to upload',
                        style: const TextStyle(fontSize: 11, color: kTextDim)),
                  ]),
          ),
        ),
        if (hasFile) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(fileName ?? '',
                  style: const TextStyle(fontSize: 11, color: kTextMuted),
                  overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: _remove,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 2),
                    Text('Remove', style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GifRight extends StatelessWidget {
  final GifLayer layer; final SceneNotifier n;
  const _GifRight({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<MediaLayout>(MediaLayout.values, layer.layout,
              (v) => n.updateLayer(layer.copyWith(layout: v))),
          const SizedBox(height: 10),
          _ToggleRow(label: 'Dithering',    value: layer.dithering,   onChanged: (v) => n.updateLayer(layer.copyWith(dithering: v))),
          _ToggleRow(label: 'Grayscale',    value: layer.grayscale,   onChanged: (v) => n.updateLayer(layer.copyWith(grayscale: v))),
          _ToggleRow(label: 'Invert color', value: layer.invertColor, onChanged: (v) => n.updateLayer(layer.copyWith(invertColor: v))),
          const SizedBox(height: 8),
          TbLabel('Custom FPS'),
          _SpeedSlider(value: layer.fpsOverride ?? 100,
              onChanged: (v) => n.updateLayer(layer.copyWith(fpsOverride: v))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SPOTIFY
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// SPOTIFY
// ─────────────────────────────────────────────────────────────────────────────

class _SpotifyLeft extends ConsumerWidget {
  final SpotifyLayer layer;
  const _SpotifyLeft({required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spot    = ref.watch(spotifyServiceProvider);
    final service = ref.read(spotifyServiceProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Status / now-playing card ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurfaceLow,
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: kBorder),
          ),
          child: spot.isConnected
              ? _NowPlayingCard(spot: spot, onRefresh: service.refresh)
              : spot.isConnecting
                  ? const _ConnectingCard()
                  : _DisconnectedCard(
                      errorMessage: spot.errorMessage,
                      onConnect: service.connect,
                    ),
        ),

        const SizedBox(height: 12),

        // ── Transport controls with disconnect on right ─────────────────
        if (spot.isConnected) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Transport buttons group
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TransportBtn(
                    icon: Icons.skip_previous_rounded,
                    onTap: () => service.skipPrevious(),
                  ),
                  const SizedBox(width: 8),
                  _TransportBtn(
                    icon: spot.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    filled: true,
                    onTap: () => service.togglePlayPause(),
                  ),
                  const SizedBox(width: 8),
                  _TransportBtn(
                    icon: Icons.skip_next_rounded,
                    onTap: () => service.skipNext(),
                  ),
                ],
              ),
              
              // Disconnect button on the right
              GestureDetector(
                onTap: service.disconnect,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: kSurfaceLow,
                    borderRadius: const BorderRadius.all(kRadiusSm),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.link_off_rounded, size: 12, color: kTextDim),
                      SizedBox(width: 4),
                      Text(
                        'Disconnect',
                        style: TextStyle(fontSize: 10, color: kTextDim),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Progress bar with timestamps ───────────────────────────
          Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.all(kRadiusSm),
                child: LinearProgressIndicator(
                  value: spot.progress,
                  minHeight: 4,
                  backgroundColor: kBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(spot.currentPosition),
                    style: const TextStyle(fontSize: 10, color: kTextDim),
                  ),
                  Text(
                    _formatDuration(spot.currentDuration),
                    style: const TextStyle(fontSize: 10, color: kTextDim),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NowPlayingCard extends StatelessWidget {
  final SpotifyState spot;
  final VoidCallback onRefresh;
  const _NowPlayingCard({required this.spot, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          // Album art with subtle shadow
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(kRadiusSm),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(kRadiusSm),
              child: spot.albumArtPixels != null
                  ? _AlbumArtThumbnail(
                      pixels: spot.albumArtPixels!,
                      size:   spot.albumArtSize,
                    )
                  : Container(
                      width: 60, height: 60,
                      color: const Color(0xFF282828),
                      child: const Icon(Icons.music_note_rounded,
                          size: 20, color: Color(0xFF1DB954)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Title + artist with better spacing
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.currentTrackTitle ?? '—',
                  style: const TextStyle(
                    fontSize: 13, 
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  spot.currentArtist ?? '',
                  style: const TextStyle(fontSize: 11, color: kTextMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                if (spot.currentAlbum != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    spot.currentAlbum!,
                    style: const TextStyle(fontSize: 9, color: kTextDim),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          
          // Refresh button with tooltip
          Tooltip(
            message: 'Refresh now playing',
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              onPressed: onRefresh,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              splashRadius: 20,
            ),
          ),
        ],
      );
}

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard();
  @override
  Widget build(BuildContext context) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF1DB954)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Opening Spotify in your browser…',
              style: TextStyle(fontSize: 11, color: kTextMuted),
            ),
          ),
        ],
      );
}

class _DisconnectedCard extends StatelessWidget {
  final String?    errorMessage;
  final Future<void> Function() onConnect;
  const _DisconnectedCard({this.errorMessage, required this.onConnect});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_rounded, size: 28, color: Color(0xFF1DB954)),
          const SizedBox(height: 6),
          const Text('Connect to Spotify',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          if (errorMessage != null)
            Text(
              errorMessage!,
              style: TextStyle(fontSize: 10, color: Colors.red.shade400),
              textAlign: TextAlign.center,
            )
          else
            const Text(
              'Sign in to display the current track',
              style: TextStyle(fontSize: 10, color: kTextMuted),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link_rounded, size: 14),
              label: const Text('Connect with Spotify',
                  style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(kRadiusSm)),
              ),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Album art thumbnail — renders ARGB pixels via CustomPainter
// (add this class anywhere in toolbox_panel.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _AlbumArtThumbnail extends StatelessWidget {
  final Uint32List pixels;
  final int        size;
  const _AlbumArtThumbnail({required this.pixels, required this.size});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(60, 60),
        painter: _ArtPainter(pixels: pixels, size: size),
      );
}

class _ArtPainter extends CustomPainter {
  final Uint32List pixels;
  final int        size;
  const _ArtPainter({required this.pixels, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint();
    final dW    = canvasSize.width  / size;
    final dH    = canvasSize.height / size;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        paint.color = Color(pixels[y * size + x] | 0xFF000000);
        canvas.drawRect(Rect.fromLTWH(x * dW, y * dH, dW, dH), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.pixels != pixels;
}

class _SpotifyRight extends StatelessWidget {
  final SpotifyLayer layer; final SceneNotifier n;
  const _SpotifyRight({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<SpotifyLayout>(SpotifyLayout.values, layer.layout,
              (v) => n.updateLayer(layer.copyWith(layout: v))),
          const SizedBox(height: 10),
          _ToggleRow(label: 'Show title',    value: layer.showTitle,    onChanged: (v) => n.updateLayer(layer.copyWith(showTitle: v))),
          _ToggleRow(label: 'Show artist',   value: layer.showArtist,   onChanged: (v) => n.updateLayer(layer.copyWith(showArtist: v))),
          _ToggleRow(label: 'Show progress', value: layer.showProgress, onChanged: (v) => n.updateLayer(layer.copyWith(showProgress: v))),
          const SizedBox(height: 8),
          TbLabel('Custom FPS'),
          _SpeedSlider(value: (1000 / layer.fps).clamp(10, 500),
              onChanged: (v) => n.updateLayer(layer.copyWith(fps: 1000 / v))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// POMODORO — LEFT
//
// Fix: reads layer via ref.watch(selectedLayerProvider) instead of accepting
// it as a constructor prop. This guarantees the widget rebuilds after every
// updateLayer() call, so the color swatch reflects the new value immediately.
//
// Additionally, _colorBtn no longer re-wraps the result with withOpacity(),
// which was zeroing out alpha for blue and other saturated hues.
// ─────────────────────────────────────────────────────────────────────────────

class _PomodoroLeft extends ConsumerWidget {
  const _PomodoroLeft();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider) as PomodoroLayer;
    final n = ref.read(sceneProvider.notifier);
    final timerState = ref.watch(pomodoroServiceProvider);
    final service = ref.read(pomodoroServiceProvider.notifier);

    final phaseLabel = switch (timerState.phase) {
      PomodoroState.focus      => 'Focus Session',
      PomodoroState.shortBreak => 'Short Break',
      PomodoroState.longBreak  => 'Long Break',
    };

    final phaseColor = switch (timerState.phase) {
      PomodoroState.focus      => layer.focusColor,
      PomodoroState.shortBreak => layer.breakColor,
      PomodoroState.longBreak  => layer.longBreakColor,
    };

    final mins = timerState.remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = timerState.remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Phase + live countdown ─────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: phaseColor.withOpacity(0.08),
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: phaseColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: timerState.isRunning ? phaseColor : kTextDim,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(phaseLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: phaseColor)),
              const Spacer(),
              Text('$mins:$secs',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: phaseColor, fontFamily: 'monospace')),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Focus ──────────────────────────────────────────────────────
        Row(children: [
          _colorBtn(context, layer.focusColor,
              (c) => n.updateLayer(layer.copyWith(focusColor: c))),
          const SizedBox(width: 8),
          const Text('Focus Session', style: TextStyle(fontSize: 11, color: kTextMuted)),
          const Spacer(),
          _DurationStepper(
            value: layer.focusDurationMinutes,
            unit: 'min',
            onChanged: (v) => n.updateLayer(layer.copyWith(focusDurationMinutes: v)),
          ),
        ]),
        const SizedBox(height: 8),

        // ── Short break ────────────────────────────────────────────────
        Row(children: [
          _colorBtn(context, layer.breakColor,
              (c) => n.updateLayer(layer.copyWith(breakColor: c))),
          const SizedBox(width: 8),
          const Text('Short break', style: TextStyle(fontSize: 11, color: kTextMuted)),
          const Spacer(),
          _DurationStepper(
            value: layer.shortBreakMinutes,
            unit: 'min',
            onChanged: (v) => n.updateLayer(layer.copyWith(shortBreakMinutes: v)),
          ),
        ]),
        const SizedBox(height: 8),

        // ── Long break ─────────────────────────────────────────────────
        Row(children: [
          _colorBtn(context, layer.longBreakColor,
              (c) => n.updateLayer(layer.copyWith(longBreakColor: c))),
          const SizedBox(width: 8),
          const Text('Long break', style: TextStyle(fontSize: 11, color: kTextMuted)),
          const Spacer(),
          _DurationStepper(
            value: layer.longBreakMinutes,
            unit: 'min',
            onChanged: (v) => n.updateLayer(layer.copyWith(longBreakMinutes: v)),
          ),
        ]),
        const SizedBox(height: 8),

        _Stepper(
          label: 'Sessions before long break',
          value: layer.sessionsBeforeLongBreak,
          onChanged: (v) => n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v)),
        ),
        const SizedBox(height: 10),

        // ── Transport ──────────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _TransportBtn(icon: Icons.restart_alt_rounded, onTap: () => service.reset(layer)),
          const SizedBox(width: 8),
          _TransportBtn(
            icon: timerState.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
            filled: true,
            onTap: () => service.togglePlayPause(layer),
          ),
          const SizedBox(width: 8),
          _TransportBtn(icon: Icons.skip_next_rounded, onTap: () => service.skip(layer)),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POMODORO — RIGHT
// ─────────────────────────────────────────────────────────────────────────────

class _PomodoroRight extends ConsumerWidget {
  const _PomodoroRight();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider) as PomodoroLayer;
    final n = ref.read(sceneProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _greenDropdown<PomodoroLayout>(PomodoroLayout.values, layer.layout,
            (v) => n.updateLayer(layer.copyWith(layout: v))),
        const SizedBox(height: 8),
        _ToggleRow(label: 'Show seconds', value: layer.showSeconds, onChanged: (v) => n.updateLayer(layer.copyWith(showSeconds: v))),
        _ToggleRow(label: 'Show session', value: layer.showSession, onChanged: (v) => n.updateLayer(layer.copyWith(showSession: v))),
        _ToggleRow(label: 'Blink colon',  value: layer.blinkColor,  onChanged: (v) => n.updateLayer(layer.copyWith(blinkColor: v))),
        const SizedBox(height: 8),
        TbLabel('Custom FPS'),
        _SpeedSlider(value: (1000 / layer.fps).clamp(10, 500),
            onChanged: (v) => n.updateLayer(layer.copyWith(fps: 1000 / v))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duration stepper
// ─────────────────────────────────────────────────────────────────────────────

class _DurationStepper extends StatelessWidget {
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min, max;

  const _DurationStepper({
    required this.value,
    required this.onChanged,
    this.unit = '',
    this.min = 1,
    this.max = 99,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(icon: Icons.remove_rounded, enabled: value > min, onTap: () => onChanged(value - 1)),
          SizedBox(
            width: 50,
            child: Text('$value $unit', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          _StepBtn(icon: Icons.add_rounded, enabled: value < max, onTap: () => onChanged(value + 1)),
        ],
      );
}