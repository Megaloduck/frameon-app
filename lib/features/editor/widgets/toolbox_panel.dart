import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/scene/layer.dart';
import '../../../shared/providers/providers.dart';
import 'color_picker.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToolboxPanel
//
// The toolbox occupies the space to the right of the Layers panel.
// It is split into TWO side-by-side sub-panels, exactly matching the
// screenshots:
//
//   ┌──────────────────────┬──────────────────┐
//   │  LEFT sub-panel      │  RIGHT sub-panel  │
//   │  • Color picker      │  • Layout picker  │
//   │  • Content settings  │  • Options/FPS    │
//   │    (per layer type)  │    (per layer)    │
//   └──────────────────────┴──────────────────┘
//
// The two panels are rendered as siblings inside a Row in editor_page.dart
// (see _ToolboxRow). This file exports both via ToolboxLeft + ToolboxRight,
// plus the combined ToolboxPanel wrapper used when space allows.
// ─────────────────────────────────────────────────────────────────────────────

// ── Public combined widget (used by editor_page.dart) ─────────────────────────

class ToolboxPanel extends ConsumerWidget {
  const ToolboxPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);

    // When nothing is selected both sub-panels show a placeholder.
    if (layer == null) {
      return const _EmptyToolbox();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _ToolboxLeft(layer: layer)),
        const VerticalDivider(width: 1, thickness: 1),
        SizedBox(width: 190, child: _ToolboxRight(layer: layer)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT sub-panel — color picker + layer-specific content controls
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
        _SubPanelHeader(_leftTitle(layer.type)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: switch (layer.type) {
              LayerType.text     => _TextLeft(layer: layer as TextLayer, n: n),
              LayerType.clock    => _ClockLeft(layer: layer as ClockLayer, n: n),
              LayerType.gif      => _GifLeft(layer: layer as GifLayer, n: n, ref: ref),
              LayerType.spotify  => _SpotifyLeft(layer: layer as SpotifyLayer, ref: ref),
              LayerType.pomodoro => _PomodoroLeft(layer: layer as PomodoroLayer, n: n),
            },
          ),
        ),
      ],
    );
  }

  String _leftTitle(LayerType t) => switch (t) {
        LayerType.text     => 'TEXT COLOR',
        LayerType.clock    => 'CLOCK COLOR',
        LayerType.gif      => 'UPLOAD FILES',
        LayerType.spotify  => 'SPOTIFY SETTINGS',
        LayerType.pomodoro => 'POMODORO SETTINGS',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT sub-panel — layout selector + options + FPS slider
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
        _SubPanelHeader(_rightTitle(layer.type)),
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
// Sub-panel header — small ALL-CAPS label matching the screenshot style
// ─────────────────────────────────────────────────────────────────────────────

class _SubPanelHeader extends StatelessWidget {
  final String title;
  const _SubPanelHeader(this.title);

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(bottom: kPanelBorder),
        ),
        child: Text(
          title,
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
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyToolbox extends StatelessWidget {
  const _EmptyToolbox();

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          'Select a layer to edit',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Green pill dropdown — the primary selector on the right sub-panel.
Widget _greenDropdown<T extends Enum>(
  List<T> values,
  T current,
  ValueChanged<T> onChange,
) =>
    Container(
      decoration: BoxDecoration(
        color: kGreen.withOpacity(0.1),
        border: Border.all(color: kGreen.withOpacity(0.5)),
        borderRadius: const BorderRadius.all(kRadiusSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: current,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kGreen,
          ),
          dropdownColor: kSurface,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: kGreen),
          items: values
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.name.toUpperCase()),
                  ))
              .toList(),
          onChanged: (v) { if (v != null) onChange(v); },
        ),
      ),
    );

/// Segmented control — LEFT / CENTER / RIGHT alignment bar.
class _SegmentedAlign extends StatelessWidget {
  final TextAlignment current;
  final ValueChanged<TextAlignment> onChange;
  const _SegmentedAlign({required this.current, required this.onChange});

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
                    left:  v == TextAlignment.left   ? const Radius.circular(6) : Radius.zero,
                    right: v == TextAlignment.right  ? const Radius.circular(6) : Radius.zero,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  v.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : kTextMuted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
}

/// Compact toggle row: label on left, Switch on right.
class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12, color: kTextPrimary)),
            ),
            Transform.scale(
              scale: 0.75,
              alignment: Alignment.centerRight,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      );
}

/// FPS / speed slider with "10ms fast … 500ms slow" labels.
class _SpeedSlider extends StatelessWidget {
  final double value;      // 10–500
  final ValueChanged<double> onChanged;
  final String leftLabel;
  final String rightLabel;

  const _SpeedSlider({
    required this.value,
    required this.onChanged,
    this.leftLabel  = '10ms fast',
    this.rightLabel = '500ms slow',
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(
              value: value,
              min: 10, max: 500,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leftLabel,  style: const TextStyle(fontSize: 9, color: kTextDim)),
              Text(rightLabel, style: const TextStyle(fontSize: 9, color: kTextDim)),
            ],
          ),
        ],
      );
}

/// +/− integer stepper.
class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.unit = '',
    this.min  = 1,
    this.max  = 99,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Row(children: [
                Icon(_labelIcon(label), size: 13, color: kTextDim),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(fontSize: 12, color: kTextPrimary)),
              ]),
            ),
            _StepBtn(
              icon: Icons.remove_rounded,
              enabled: value > min,
              onTap: () => onChanged(value - 1),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '$value$unit',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            _StepBtn(
              icon: Icons.add_rounded,
              enabled: value < max,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      );

  IconData _labelIcon(String l) {
    if (l.toLowerCase().contains('focus'))   return Icons.timer_rounded;
    if (l.toLowerCase().contains('short'))   return Icons.coffee_rounded;
    if (l.toLowerCase().contains('long'))    return Icons.hotel_rounded;
    if (l.toLowerCase().contains('session')) return Icons.repeat_rounded;
    return Icons.tune_rounded;
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            border: Border.all(color: kBorder),
            borderRadius: const BorderRadius.all(kRadiusSm),
            color: kSurface,
          ),
          child: Icon(icon, size: 13, color: enabled ? kTextMuted : kTextDim),
        ),
      );
}

/// Inline color swatch button that opens a color picker sheet.
Widget _colorBtn(BuildContext ctx, Color color, ValueChanged<Color> onChange) =>
    GestureDetector(
      onTap: () async {
        final c = await showColorPicker(ctx, initialColor: color);
        if (c != null) onChange(c);
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

// ─────────────────────────────────────────────────────────────────────────────
// TEXT  –  Left
// ─────────────────────────────────────────────────────────────────────────────

class _TextLeft extends StatelessWidget {
  final TextLayer layer;
  final SceneNotifier n;
  const _TextLeft({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inline color picker (always visible — matches screenshot)
          ColorPicker(
            color: layer.color,
            onChanged: (c) => n.updateLayer(layer.copyWith(color: c)),
          ),
          const SizedBox(height: 10),

          // Font style
          TbLabel('Font Style'),
          const SizedBox(height: 4),
          _TbDropdown(
            values: PixelFontStyle.values,
            current: layer.fontStyle,
            onChange: (v) => n.updateLayer(layer.copyWith(fontStyle: v)),
          ),
          const SizedBox(height: 8),

          // Display text
          TbLabel('Display Text'),
          const SizedBox(height: 4),
          _TbTextField(
            value: layer.text,
            onSubmitted: (v) => n.updateLayer(layer.copyWith(text: v)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT  –  Right
// ─────────────────────────────────────────────────────────────────────────────

class _TextRight extends StatelessWidget {
  final TextLayer layer;
  final SceneNotifier n;
  const _TextRight({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Effect dropdown (green pill)
          _greenDropdown<AnimationEffect>(
            AnimationEffect.values,
            layer.effect,
            (v) => n.updateLayer(layer.copyWith(effect: v)),
          ),
          const SizedBox(height: 12),

          // Speed slider (only when effect active)
          if (layer.effect != AnimationEffect.none) ...[
            TbLabel('Custom Speed'),
            _SpeedSlider(
              value: layer.effectSpeedMs.toDouble(),
              onChanged: (v) => n.updateLayer(layer.copyWith(effectSpeedMs: v.round())),
            ),
            const SizedBox(height: 8),
          ],

          // Alignment
          TbLabel('Alignment'),
          const SizedBox(height: 4),
          _SegmentedAlign(
            current: layer.alignment,
            onChange: (v) => n.updateLayer(layer.copyWith(alignment: v)),
          ),
          const SizedBox(height: 12),

          // Opacity
          TbLabel('Opacity'),
          Slider(
            value: layer.opacity,
            min: 0, max: 1,
            onChanged: (v) => n.updateLayer(layer.copyWith(opacity: v)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOCK  –  Left
// ─────────────────────────────────────────────────────────────────────────────

class _ClockLeft extends StatelessWidget {
  final ClockLayer layer;
  final SceneNotifier n;
  const _ClockLeft({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColorPicker(
            color: layer.color,
            onChanged: (c) => n.updateLayer(layer.copyWith(color: c)),
          ),
          const SizedBox(height: 10),
          // Per-component color hint rows (visual only, matching screenshot)
          ...['Hours', 'Minutes', 'Seconds', 'Date', 'Colon'].map(
            (label) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 11, color: kTextMuted)),
                  ),
                  Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: layer.color,
                      borderRadius: const BorderRadius.all(kRadiusSm),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOCK  –  Right
// ─────────────────────────────────────────────────────────────────────────────

class _ClockRight extends StatelessWidget {
  final ClockLayer layer;
  final SceneNotifier n;
  const _ClockRight({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timezone (green pill)
          _greenDropdown<_TzOption>(
            _TzOption.values,
            _TzOption.values.firstWhere(
              (t) => t.name == layer.timezone,
              orElse: () => _TzOption.local,
            ),
            (v) => n.updateLayer(layer.copyWith(timezone: v.name)),
          ),
          const SizedBox(height: 10),

          // Alignment
          TbLabel('Alignment'),
          const SizedBox(height: 4),
          Row(
            children: ClockAlignment.values.map((v) {
              final active = v == layer.alignment;
              return Expanded(
                child: GestureDetector(
                  onTap: () => n.updateLayer(layer.copyWith(alignment: v)),
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      color: active ? kGreen : kSurface,
                      border: Border.all(color: active ? kGreen : kBorder),
                      borderRadius: BorderRadius.horizontal(
                        left:  v == ClockAlignment.left   ? const Radius.circular(6) : Radius.zero,
                        right: v == ClockAlignment.right  ? const Radius.circular(6) : Radius.zero,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      v.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : kTextMuted,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Toggles
          _ToggleRow(
            label: '24-hour format',
            value: layer.format == ClockFormat.h24,
            onChanged: (v) => n.updateLayer(
              layer.copyWith(format: v ? ClockFormat.h24 : ClockFormat.h12),
            ),
          ),
          _ToggleRow(
            label: 'Show date',
            value: layer.showDate,
            onChanged: (v) => n.updateLayer(layer.copyWith(showDate: v)),
          ),
          _ToggleRow(
            label: 'Show seconds',
            value: layer.showSeconds,
            onChanged: (v) => n.updateLayer(layer.copyWith(showSeconds: v)),
          ),
          _ToggleRow(
            label: 'Blink colon',
            value: layer.blinkColon,
            onChanged: (v) => n.updateLayer(layer.copyWith(blinkColon: v)),
          ),
        ],
      );
}

// Timezone pseudo-enum for the dropdown
enum _TzOption { local, utc, bangkok, tokyo, london, newYork }

// ─────────────────────────────────────────────────────────────────────────────
// GIF  –  Left
// ─────────────────────────────────────────────────────────────────────────────

class _GifLeft extends ConsumerStatefulWidget {
  final GifLayer layer;
  final SceneNotifier n;
  final WidgetRef ref;
  const _GifLeft({required this.layer, required this.n, required this.ref});

  @override
  ConsumerState<_GifLeft> createState() => _GifLeftState();
}

class _GifLeftState extends ConsumerState<_GifLeft> {
  bool _loading = false;

  Future<void> _pick() async {
    final renderer = ref.read(matrixRendererProvider);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif', 'png', 'jpg', 'jpeg'],
        withData: kIsWeb,
      );
    } catch (e) {
      _snack('File picker error: $e'); return;
    }
    if (result == null || !mounted) return;
    final pf = result.files.single;
    setState(() => _loading = true);
    try {
      final bytes = await _readBytes(pf);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) { _snack('Could not read file.'); return; }
      final key = pf.path ?? pf.name;
      renderer.addAssetBytes(key, bytes);
      widget.n.updateLayer(widget.layer.copyWith(filePath: key));
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _readBytes(PlatformFile pf) async {
    if (!kIsWeb && pf.path != null) {
      try {
        return await compute<String, Uint8List>((p) => File(p).readAsBytesSync(), pf.path!);
      } catch (_) {}
    }
    return pf.bytes;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = widget.layer.filePath != null;
    final fileName = hasFile
        ? widget.layer.filePath!.split('/').last.split('\\').last
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Upload / thumbnail area
        GestureDetector(
          onTap: _loading ? null : _pick,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: hasFile ? Colors.black : kSurfaceLow,
              borderRadius: const BorderRadius.all(kRadiusMd),
              border: Border.all(
                color: hasFile ? Colors.transparent : kBorder,
                style: hasFile ? BorderStyle.none : BorderStyle.solid,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasFile
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Placeholder for image — real app would use Image.file
                      Container(color: const Color(0xFF1A1A1A)),
                      Positioned(
                        top: 6, right: 6,
                        child: GestureDetector(
                          onTap: _pick,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: const BorderRadius.all(kRadiusSm),
                            ),
                            child: const Text(
                              'CHANGE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _loading
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 26, color: kTextDim),
                      const SizedBox(height: 4),
                      Text(
                        _loading ? 'Loading…' : 'JPG · PNG · GIF',
                        style: const TextStyle(fontSize: 11, color: kTextDim),
                      ),
                    ],
                  ),
          ),
        ),

        if (hasFile) ...[
          const SizedBox(height: 6),
          Text(
            fileName ?? '',
            style: const TextStyle(fontSize: 11, color: kTextMuted),
            overflow: TextOverflow.ellipsis,
          ),
          TextButton(
            onPressed: () {
              ref.read(matrixRendererProvider).removeAsset(widget.layer.filePath!);
              widget.n.updateLayer(widget.layer.copyWith(clearFilePath: true));
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade400,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
            ),
            child: const Text('Remove file', style: TextStyle(fontSize: 11)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GIF  –  Right
// ─────────────────────────────────────────────────────────────────────────────

class _GifRight extends StatelessWidget {
  final GifLayer layer;
  final SceneNotifier n;
  const _GifRight({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<MediaLayout>(
            MediaLayout.values,
            layer.layout,
            (v) => n.updateLayer(layer.copyWith(layout: v)),
          ),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Dithering',
            value: layer.dithering,
            onChanged: (v) => n.updateLayer(layer.copyWith(dithering: v)),
          ),
          _ToggleRow(
            label: 'Grayscale',
            value: layer.grayscale,
            onChanged: (v) => n.updateLayer(layer.copyWith(grayscale: v)),
          ),
          _ToggleRow(
            label: 'Invert color',
            value: layer.invertColor,
            onChanged: (v) => n.updateLayer(layer.copyWith(invertColor: v)),
          ),
          const SizedBox(height: 8),
          TbLabel('Custom FPS'),
          _SpeedSlider(
            value: layer.fpsOverride ?? 100,
            onChanged: (v) => n.updateLayer(layer.copyWith(fpsOverride: v)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SPOTIFY  –  Left
// ─────────────────────────────────────────────────────────────────────────────

class _SpotifyLeft extends StatelessWidget {
  final SpotifyLayer layer;
  final WidgetRef ref;
  const _SpotifyLeft({required this.layer, required this.ref});

  @override
  Widget build(BuildContext context) {
    final spot = ref.watch(spotifyServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Connection card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurfaceLow,
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: kBorder),
          ),
          child: spot.isConnected
              ? Row(children: [
                  const Icon(Icons.music_note_rounded, size: 16, color: Color(0xFF1DB954)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.currentTrackTitle ?? 'Playing',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          spot.currentArtist ?? '',
                          style: const TextStyle(fontSize: 11, color: kTextMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    onPressed: () => ref.read(spotifyServiceProvider.notifier).refresh(),
                    tooltip: 'Refresh',
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                  ),
                ])
              : Column(
                  children: [
                    const Icon(Icons.queue_music_rounded, size: 28, color: Color(0xFF1DB954)),
                    const SizedBox(height: 6),
                    const Text(
                      'Connect to Spotify',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const Text(
                      'Authorise your account to continue',
                      style: TextStyle(fontSize: 10, color: kTextMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => ref.read(spotifyServiceProvider.notifier).connect(),
                        icon: const Icon(Icons.link_rounded, size: 14),
                        label: const Text('Connect with Spotify', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(kRadiusSm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),

        const SizedBox(height: 10),

        // Transport controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TransportBtn(icon: Icons.skip_previous_rounded, onTap: () {}),
            const SizedBox(width: 8),
            _TransportBtn(
              icon: Icons.play_arrow_rounded,
              filled: true,
              onTap: () {},
            ),
            const SizedBox(width: 8),
            _TransportBtn(icon: Icons.skip_next_rounded, onTap: () {}),
          ],
        ),
      ],
    );
  }
}

class _TransportBtn extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _TransportBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: filled ? kGreen : kSurface,
            shape: BoxShape.circle,
            border: Border.all(color: filled ? kGreen : kBorder),
          ),
          child: Icon(icon, size: 17, color: filled ? Colors.white : kTextMuted),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SPOTIFY  –  Right
// ─────────────────────────────────────────────────────────────────────────────

class _SpotifyRight extends StatelessWidget {
  final SpotifyLayer layer;
  final SceneNotifier n;
  const _SpotifyRight({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<SpotifyLayout>(
            SpotifyLayout.values,
            layer.layout,
            (v) => n.updateLayer(layer.copyWith(layout: v)),
          ),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Show title',
            value: layer.showTitle,
            onChanged: (v) => n.updateLayer(layer.copyWith(showTitle: v)),
          ),
          _ToggleRow(
            label: 'Show artist',
            value: layer.showArtist,
            onChanged: (v) => n.updateLayer(layer.copyWith(showArtist: v)),
          ),
          _ToggleRow(
            label: 'Show progress',
            value: layer.showProgress,
            onChanged: (v) => n.updateLayer(layer.copyWith(showProgress: v)),
          ),
          const SizedBox(height: 8),
          TbLabel('Custom FPS'),
          _SpeedSlider(
            value: (1000 / layer.fps).clamp(10, 500),
            onChanged: (v) => n.updateLayer(layer.copyWith(fps: 1000 / v)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// POMODORO  –  Left
// ─────────────────────────────────────────────────────────────────────────────

class _PomodoroLeft extends StatelessWidget {
  final PomodoroLayer layer;
  final SceneNotifier n;
  const _PomodoroLeft({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Stepper(
            label: 'Focus duration',
            value: layer.focusDurationMinutes,
            unit: ' min',
            onChanged: (v) => n.updateLayer(layer.copyWith(focusDurationMinutes: v)),
          ),
          _Stepper(
            label: 'Short break',
            value: layer.shortBreakMinutes,
            unit: ' min',
            onChanged: (v) => n.updateLayer(layer.copyWith(shortBreakMinutes: v)),
          ),
          _Stepper(
            label: 'Long break',
            value: layer.longBreakMinutes,
            unit: ' min',
            onChanged: (v) => n.updateLayer(layer.copyWith(longBreakMinutes: v)),
          ),
          _Stepper(
            label: 'Sessions before long break',
            value: layer.sessionsBeforeLongBreak,
            onChanged: (v) => n.updateLayer(layer.copyWith(sessionsBeforeLongBreak: v)),
          ),
          const SizedBox(height: 10),

          // Transport controls (same pattern as Spotify)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TransportBtn(icon: Icons.restart_alt_rounded, onTap: () {}),
              const SizedBox(width: 8),
              _TransportBtn(icon: Icons.play_arrow_rounded, filled: true, onTap: () {}),
              const SizedBox(width: 8),
              _TransportBtn(icon: Icons.skip_next_rounded, onTap: () {}),
            ],
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// POMODORO  –  Right
// ─────────────────────────────────────────────────────────────────────────────

class _PomodoroRight extends StatelessWidget {
  final PomodoroLayer layer;
  final SceneNotifier n;
  const _PomodoroRight({required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _greenDropdown<PomodoroLayout>(
            PomodoroLayout.values,
            layer.layout,
            (v) => n.updateLayer(layer.copyWith(layout: v)),
          ),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Show seconds',
            value: layer.showSeconds,
            onChanged: (v) => n.updateLayer(layer.copyWith(showSeconds: v)),
          ),
          _ToggleRow(
            label: 'Show session',
            value: layer.showSession,
            onChanged: (v) => n.updateLayer(layer.copyWith(showSession: v)),
          ),
          _ToggleRow(
            label: 'Blink color',
            value: layer.blinkColor,
            onChanged: (v) => n.updateLayer(layer.copyWith(blinkColor: v)),
          ),
          const SizedBox(height: 8),
          TbLabel('Custom FPS'),
          _SpeedSlider(
            value: (1000 / layer.fps).clamp(10, 500),
            onChanged: (v) => n.updateLayer(layer.copyWith(fps: 1000 / v)),
          ),
          const SizedBox(height: 8),

          // Focus / break color pair
          TbLabel('Focus color'),
          const SizedBox(height: 4),
          Row(children: [
            _colorBtn(context, layer.focusColor,
                (c) => n.updateLayer(layer.copyWith(focusColor: c))),
            const SizedBox(width: 8),
            const Text('Focus', style: TextStyle(fontSize: 11, color: kTextMuted)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _colorBtn(context, layer.breakColor,
                (c) => n.updateLayer(layer.copyWith(breakColor: c))),
            const SizedBox(width: 8),
            const Text('Break', style: TextStyle(fontSize: 11, color: kTextMuted)),
          ]),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Small ALL-CAPS label used inside toolbox sections.
class TbLabel extends StatelessWidget {
  final String text;
  const TbLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700,
          letterSpacing: 0.1, color: kTextDim,
        ),
      );
}

/// Plain (non-green) dropdown used inside left sub-panel.
class _TbDropdown<T extends Enum> extends StatelessWidget {
  final List<T> values;
  final T current;
  final ValueChanged<T> onChange;
  const _TbDropdown({required this.values, required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: current,
        isDense: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: const BorderSide(color: kBorder),
          ),
        ),
        style: const TextStyle(fontSize: 12, color: kTextPrimary),
        items: values
            .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
            .toList(),
        onChanged: (v) { if (v != null) onChange(v); },
      );
}

/// Plain text field used for the display-text input.
class _TbTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onSubmitted;
  const _TbTextField({required this.value, required this.onSubmitted});

  @override
  State<_TbTextField> createState() => _TbTextFieldState();
}

class _TbTextFieldState extends State<_TbTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TbTextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(kRadiusSm),
            borderSide: const BorderSide(color: kGreen, width: 1.5),
          ),
        ),
        onSubmitted: widget.onSubmitted,
        onEditingComplete: () => widget.onSubmitted(_ctrl.text),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry-points consumed by editor_page.dart
//
// editor_page.dart places these as two separate PanelShell siblings so they
// appear as distinct rounded cards, exactly like the screenshots.
// ─────────────────────────────────────────────────────────────────────────────

/// The LEFT toolbox sub-panel: color picker + layer-specific content controls.
/// Place inside a PanelShell in editor_page.dart.
class ToolboxLeftPanel extends ConsumerWidget {
  const ToolboxLeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();
    return _ToolboxLeft(layer: layer);
  }
}

/// The RIGHT toolbox sub-panel: layout dropdown + options/FPS.
/// Place inside a PanelShell in editor_page.dart.
class ToolboxRightPanel extends ConsumerWidget {
  const ToolboxRightPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(selectedLayerProvider);
    if (layer == null) return const _EmptyToolbox();
    return _ToolboxRight(layer: layer);
  }
}