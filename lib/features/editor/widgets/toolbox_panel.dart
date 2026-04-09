import 'dart:io';

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
              LayerType.pomodoro => _PomodoroLeft(layer: layer as PomodoroLayer, n: n),
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
              LayerType.pomodoro => _PomodoroRight(layer: layer as PomodoroLayer, n: n),
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

/// Green pill dropdown (right sub-panel primary selector).
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

Widget _colorBtn(BuildContext ctx, Color color, ValueChanged<Color> onChange) =>
    GestureDetector(
      onTap: () async {
        final c = await showColorPicker(ctx, initialColor: color);
        if (c != null) onChange(c);
      },
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(color: color,
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: Colors.black.withOpacity(0.15))),
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
          ColorPicker(color: layer.color, onChanged: (c) => n.updateLayer(layer.copyWith(color: c))),
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
          // Individual element colors
          const TbLabel('Element Colors'),
          const SizedBox(height: 8),
          
          // Hours
          _ColorRow(
            label: 'Hours',
            color: layer.hoursColor,
            onChanged: (c) => n.updateLayer(layer.copyWith(hoursColor: c)),
          ),
          const SizedBox(height: 6),
          
          // Minutes
          _ColorRow(
            label: 'Minutes',
            color: layer.minutesColor,
            onChanged: (c) => n.updateLayer(layer.copyWith(minutesColor: c)),
          ),
          const SizedBox(height: 6),
          
          // Seconds (only shown if showSeconds is enabled)
          if (layer.showSeconds)
            _ColorRow(
              label: 'Seconds',
              color: layer.secondsColor,
              onChanged: (c) => n.updateLayer(layer.copyWith(secondsColor: c)),
            ),
          if (layer.showSeconds) const SizedBox(height: 6),
          
          // Date (only shown if showDate is enabled)
          if (layer.showDate)
            _ColorRow(
              label: 'Date',
              color: layer.dateColor,
              onChanged: (c) => n.updateLayer(layer.copyWith(dateColor: c)),
            ),
          if (layer.showDate) const SizedBox(height: 6),
          
          // Colon
          _ColorRow(
            label: 'Colon',
            color: layer.colonColor,
            onChanged: (c) => n.updateLayer(layer.copyWith(colonColor: c)),
          ),
        ],
      );
}

// Helper widget for color row with label and color picker
class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });
  
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: kTextMuted),
            ),
          ),
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
// GIF — LEFT  (upload + thumbnail)
//
// Fix summary:
//   1. After picking, bytes are stored in gifBytesProvider keyed by cache key.
//   2. The thumbnail reads from gifBytesProvider via ref.watch — it stays alive
//      across layer re-selection because the provider is global.
//   3. On desktop, bytes are read via compute(File.readAsBytesSync) and ALSO
//      passed to MatrixRenderer via addAssetBytes.
//   4. The thumbnail uses Image.memory(bytes, fit: BoxFit.cover).
//   5. Remove button clears both gifBytesProvider and the renderer cache.
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
        withData: true, // always request bytes — safest on all platforms
      );
    } catch (e) { _snack('Picker error: $e'); return; }

    if (result == null || !mounted) return;
    final pf = result.files.single;

    setState(() => _loading = true);
    try {
      Uint8List? bytes = pf.bytes;

      // On desktop the bytes field may be null even with withData:true due to a
      // file_picker bug — fall back to reading the file directly.
      if ((bytes == null || bytes.isEmpty) && !kIsWeb && pf.path != null) {
        bytes = await compute<String, Uint8List>(
          (path) => File(path).readAsBytesSync(), pf.path!);
      }

      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) { _snack('Could not read file.'); return; }

      final String key = pf.path ?? pf.name;

      // 1. Store raw bytes so the thumbnail can render
      ref.read(gifBytesProvider.notifier).set(key, bytes);

      // 2. Decode into renderer cache
      ref.read(matrixRendererProvider).addAssetBytes(key, bytes);

      // 3. Update the layer model
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
    final key      = widget.layer.filePath;
    final hasFile  = key != null;
    // Watch the bytes map — rebuilds when bytes are stored/removed
    final allBytes = ref.watch(gifBytesProvider);
    final bytes    = hasFile ? allBytes[key] : null;
    final fileName = hasFile ? key.split('/').last.split('\\').last : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header label matching the screenshot
        Row(children: [
          const Expanded(
            child: Text('JPG · PNG · GIF',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    letterSpacing: 0.08, color: kTextDim)),
          ),
        ]),
        const SizedBox(height: 8),

        // Upload area / thumbnail
        GestureDetector(
          onTap: _loading ? null : _pick,
          child: Container(
            height: 115,
            decoration: BoxDecoration(
              color: hasFile ? Colors.black : kSurfaceLow,
              borderRadius: const BorderRadius.all(kRadiusMd),
              border: hasFile
                  ? null
                  : Border.all(color: kBorder, style: BorderStyle.solid),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasFile && bytes != null
                // ── Thumbnail ────────────────────────────────────────────
                ? Stack(fit: StackFit.expand, children: [
                    Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                    // CHANGE overlay — top-right corner
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
                // ── Upload prompt ─────────────────────────────────────────
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_loading)
                      const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                    else
                      const Icon(Icons.upload_file_rounded, size: 28, color: kTextDim),
                    const SizedBox(height: 6),
                    Text(
                      _loading ? 'Loading…' : 'Click to upload',
                      style: const TextStyle(fontSize: 11, color: kTextDim),
                    ),
                  ]),
          ),
        ),

        // Filename + remove button - now in a row horizontally aligned
        if (hasFile) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              // Filename - expands to take available space
              Expanded(
                child: Text(
                  fileName ?? '',
                  style: const TextStyle(fontSize: 11, color: kTextMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Remove button - right aligned
              GestureDetector(
                onTap: _remove,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, size: 14, color: Colors.red.shade400),
                      const SizedBox(width: 2),
                      Text(
                        'Remove',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// GIF — RIGHT
// ─────────────────────────────────────────────────────────────────────────────

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
          _ToggleRow(label: 'Dithering',   value: layer.dithering,   onChanged: (v) => n.updateLayer(layer.copyWith(dithering: v))),
          _ToggleRow(label: 'Grayscale',   value: layer.grayscale,   onChanged: (v) => n.updateLayer(layer.copyWith(grayscale: v))),
          _ToggleRow(label: 'Invert color',value: layer.invertColor,  onChanged: (v) => n.updateLayer(layer.copyWith(invertColor: v))),
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

class _SpotifyLeft extends ConsumerWidget {
  final SpotifyLayer layer;
  const _SpotifyLeft({required this.layer});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spot = ref.watch(spotifyServiceProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kSurfaceLow,
            borderRadius: const BorderRadius.all(kRadiusMd), border: Border.all(color: kBorder)),
        child: spot.isConnected
            ? Row(children: [
                const Icon(Icons.music_note_rounded, size: 16, color: Color(0xFF1DB954)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(spot.currentTrackTitle ?? 'Playing',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(spot.currentArtist ?? '',
                      style: const TextStyle(fontSize: 11, color: kTextMuted),
                      overflow: TextOverflow.ellipsis),
                ])),
                IconButton(icon: const Icon(Icons.refresh_rounded, size: 14),
                    onPressed: () => ref.read(spotifyServiceProvider.notifier).refresh(),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: EdgeInsets.zero),
              ])
            : Column(children: [
                const Icon(Icons.queue_music_rounded, size: 28, color: Color(0xFF1DB954)),
                const SizedBox(height: 6),
                const Text('Connect to Spotify', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const Text('Authorise your account to continue',
                    style: TextStyle(fontSize: 10, color: kTextMuted), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => ref.read(spotifyServiceProvider.notifier).connect(),
                    icon: const Icon(Icons.link_rounded, size: 14),
                    label: const Text('Connect with Spotify', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(kRadiusSm))),
                  )),
              ]),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _TransportBtn(icon: Icons.skip_previous_rounded, onTap: () {}),
        const SizedBox(width: 8),
        _TransportBtn(icon: Icons.play_arrow_rounded, filled: true, onTap: () {}),
        const SizedBox(width: 8),
        _TransportBtn(icon: Icons.skip_next_rounded, onTap: () {}),
      ]),
    ]);
  }
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
// POMODORO
// ─────────────────────────────────────────────────────────────────────────────

class _PomodoroLeft extends StatelessWidget {
  final PomodoroLayer layer; final SceneNotifier n;
  const _PomodoroLeft({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Stepper(label: 'Focus duration',  value: layer.focusDurationMinutes,    unit: ' min', onChanged: (v) => n.updateLayer(layer.copyWith(focusDurationMinutes: v))),
          _Stepper(label: 'Short break',     value: layer.shortBreakMinutes,       unit: ' min', onChanged: (v) => n.updateLayer(layer.copyWith(shortBreakMinutes: v))),
          _Stepper(label: 'Long break',      value: layer.longBreakMinutes,        unit: ' min', onChanged: (v) => n.updateLayer(layer.copyWith(longBreakMinutes: v))),
          _Stepper(label: 'Sessions before long break', value: layer.sessionsBeforeLongBreak, onChanged: (v) => n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v))),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _TransportBtn(icon: Icons.restart_alt_rounded, onTap: () {}),
            const SizedBox(width: 8),
            _TransportBtn(icon: Icons.play_arrow_rounded, filled: true, onTap: () {}),
            const SizedBox(width: 8),
            _TransportBtn(icon: Icons.skip_next_rounded, onTap: () {}),
          ]),
        ],
      );
}

class _PomodoroRight extends StatelessWidget {
  final PomodoroLayer layer; final SceneNotifier n;
  const _PomodoroRight({required this.layer, required this.n});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<PomodoroLayout>(PomodoroLayout.values, layer.layout,
              (v) => n.updateLayer(layer.copyWith(layout: v))),
          const SizedBox(height: 8),
          _ToggleRow(label: 'Show seconds', value: layer.showSeconds, onChanged: (v) => n.updateLayer(layer.copyWith(showSeconds: v))),
          _ToggleRow(label: 'Show session', value: layer.showSession, onChanged: (v) => n.updateLayer(layer.copyWith(showSession: v))),
          _ToggleRow(label: 'Blink color',  value: layer.blinkColor,  onChanged: (v) => n.updateLayer(layer.copyWith(blinkColor: v))),
          const SizedBox(height: 8),
          TbLabel('Custom FPS'),
          _SpeedSlider(value: (1000 / layer.fps).clamp(10, 500),
              onChanged: (v) => n.updateLayer(layer.copyWith(fps: 1000 / v))),
          const SizedBox(height: 8),
          TbLabel('Session color'), const SizedBox(height: 4),
          Row(children: [
            _colorBtn(context, layer.focusColor, (c) => n.updateLayer(layer.copyWith(focusColor: c))),
            const SizedBox(width: 8),
            const Text('Focus', style: TextStyle(fontSize: 11, color: kTextMuted)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _colorBtn(context, layer.breakColor, (c) => n.updateLayer(layer.copyWith(breakColor: c))),
            const SizedBox(width: 8),
            const Text('Break', style: TextStyle(fontSize: 11, color: kTextMuted)),
          ]),
        ],
      );
}