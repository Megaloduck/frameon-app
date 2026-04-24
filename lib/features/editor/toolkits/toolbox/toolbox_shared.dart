import 'package:flutter/material.dart';

import '../../../../engine/scene/layer.dart';
import '../color_picker.dart';
import '../ui_primitives.dart';

// tbGreenDropdown now takes BuildContext so it can read tSurface from the theme.
Widget tbGreenDropdown<T extends Enum>(
  BuildContext ctx,
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
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: current,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: kGreen),
          dropdownColor: ctx.tSurface,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: kGreen),
          items: values
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.name.toUpperCase()),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChange(v);
          },
        ),
      ),
    );

class TbSegAlign extends StatelessWidget {
  final TextAlignment current;
  final ValueChanged<TextAlignment> onChange;
  const TbSegAlign({super.key, required this.current, required this.onChange});

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
                  color: active ? kGreen : context.tSurface,
                  border: Border.all(
                      color: active ? kGreen : context.tBorder),
                  borderRadius: BorderRadius.horizontal(
                    left: v == TextAlignment.left
                        ? const Radius.circular(6)
                        : Radius.zero,
                    right: v == TextAlignment.right
                        ? const Radius.circular(6)
                        : Radius.zero,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(v.name.toUpperCase(),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : context.tTextMuted)),
              ),
            ),
          );
        }).toList(),
      );
}

class TbToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const TbToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Transform.scale(
            scale: 0.5,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class TbSpeedSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const TbSpeedSlider(
      {super.key, required this.value, required this.onChanged});

  static const List<int> _steps = [500, 350, 200, 100, 50, 25, 10];

  static int _msToIndex(double ms) {
    int best = 0;
    double minDiff = double.infinity;
    for (int i = 0; i < _steps.length; i++) {
      final diff = (_steps[i] - ms).abs();
      if (diff < minDiff) {
        minDiff = diff;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final index = _msToIndex(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 3),
          child: Slider(
            value: index.toDouble(),
            min: 0,
            max: 6,
            divisions: 6,
            onChanged: (v) => onChanged(_steps[v.round()].toDouble()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Slow',   style: TextStyle(fontSize: 9, color: context.tTextDim)),
            Text('Normal', style: TextStyle(fontSize: 9, color: context.tTextDim)),
            Text('Fast',   style: TextStyle(fontSize: 9, color: context.tTextDim)),
          ],
        ),
      ],
    );
  }
}

class TbStepper extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min, max;
  const TbStepper(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.unit = '',
      this.min = 1,
      this.max = 99});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, color: context.tTextPrimary))),
          TbStepBtn(
              icon: Icons.remove_rounded,
              enabled: value > min,
              onTap: () => onChanged(value - 1)),
          SizedBox(
              width: 40,
              child: Text('$value$unit',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          TbStepBtn(
              icon: Icons.add_rounded,
              enabled: value < max,
              onTap: () => onChanged(value + 1)),
        ]),
      );
}

class TbStepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const TbStepBtn(
      {super.key,
      required this.icon,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
              border: Border.all(color: context.tBorder),
              borderRadius: const BorderRadius.all(kRadiusSm),
              color: context.tSurface),
          child: Icon(icon,
              size: 13,
              color: enabled ? context.tTextMuted : context.tTextDim),
        ),
      );
}

class TbTransportBtn extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final bool active;
  final VoidCallback onTap;
  const TbTransportBtn(
      {super.key,
      required this.icon,
      required this.onTap,
      this.filled = false,
      this.active = false});

  @override
  Widget build(BuildContext context) {
    final isActive = active && !filled;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: filled
              ? const Color(0xFF1DB954)
              : (isActive
                  ? const Color(0xFF1DB954).withOpacity(0.15)
                  : context.tSurface),
          shape: BoxShape.circle,
          border: Border.all(
            color: filled
                ? const Color(0xFF1DB954)
                : (isActive
                    ? const Color(0xFF1DB954)
                    : context.tBorder),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Icon(icon,
            size: filled ? 17 : 16,
            color: filled
                ? Colors.white
                : (isActive
                    ? const Color(0xFF1DB954)
                    : context.tTextMuted)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// tbColorBtn
// ─────────────────────────────────────────────────────────────────────────────

Widget tbColorBtn(
        BuildContext ctx, Color color, ValueChanged<Color> onChange) =>
    GestureDetector(
      onTap: () async {
        final picked =
            await showColorPickerSheet(ctx, initialColor: color);
        if (picked != null) onChange(picked);
      },
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(kRadiusSm),
            border: Border.all(color: Colors.black.withOpacity(0.15))),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// TbColorAnimRow
// ─────────────────────────────────────────────────────────────────────────────

class TbColorAnimRow<T extends Enum> extends StatelessWidget {
  final String label;
  final Color color;
  final List<T> effectValues;
  final T currentEffect;
  final String Function(T) effectLabel;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<T> onEffectChanged;

  const TbColorAnimRow({
    super.key,
    required this.label,
    required this.color,
    required this.effectValues,
    required this.currentEffect,
    required this.effectLabel,
    required this.onColorChanged,
    required this.onEffectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.tSurfaceLow,
        borderRadius: const BorderRadius.all(kRadiusSm),
        border: Border.all(color: context.tBorder),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final picked =
                  await showColorPickerSheet(context, initialColor: color);
              if (picked != null) onColorChanged(picked);
            },
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(kRadiusSm),
                border:
                    Border.all(color: Colors.black.withOpacity(0.18)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: context.tTextMuted),
            ),
          ),
          _EffectChip<T>(
            values: effectValues,
            current: currentEffect,
            labelFor: effectLabel,
            onChanged: onEffectChanged,
          ),
        ],
      ),
    );
  }
}

class _EffectChip<T extends Enum> extends StatelessWidget {
  final List<T> values;
  final T current;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  const _EffectChip({
    required this.values,
    required this.current,
    required this.labelFor,
    required this.onChanged,
  });

  static const Map<String, IconData> _icons = {
    'none':        Icons.crop_square_rounded,
    'static_':     Icons.crop_square_rounded,
    'static':      Icons.crop_square_rounded,
    'blink':       Icons.flash_on_rounded,
    'scroll':      Icons.swap_horiz_rounded,
    'scrollLeft':  Icons.arrow_back_rounded,
    'scrollRight': Icons.arrow_forward_rounded,
    'pulse':       Icons.water_rounded,
    'fade':        Icons.gradient_rounded,
    'burst':       Icons.flash_auto_rounded,
  };

  IconData _iconFor(T value) =>
      _icons[value.name] ?? Icons.auto_awesome_rounded;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: 'Text animation',
      offset: const Offset(0, 28),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(kRadiusMd)),
      color: context.tSurface,
      elevation: 4,
      itemBuilder: (_) => values.map((v) {
        final active = v == current;
        return PopupMenuItem<T>(
          value: v,
          height: 32,
          child: Row(children: [
            Icon(_iconFor(v),
                size: 13, color: active ? kGreen : context.tTextMuted),
            const SizedBox(width: 8),
            Text(
              labelFor(v),
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
                color: active ? kGreen : context.tTextPrimary,
              ),
            ),
            if (active) ...[
              const Spacer(),
              const Icon(Icons.check_rounded, size: 12, color: kGreen),
            ],
          ]),
        );
      }).toList(),
      onSelected: onChanged,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: context.tSurface,
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(color: context.tBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_iconFor(current), size: 11, color: kGreen),
          const SizedBox(width: 4),
          Text(
            labelFor(current),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: kGreen),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.keyboard_arrow_down_rounded,
              size: 12, color: kGreen),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TbLabel
// ─────────────────────────────────────────────────────────────────────────────

class TbLabel extends StatelessWidget {
  final String text;
  const TbLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: context.tTextDim),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TbDropdown
// ─────────────────────────────────────────────────────────────────────────────

class TbDropdown<T extends Enum> extends StatelessWidget {
  final List<T> values;
  final T current;
  final ValueChanged<T> onChange;
  final String Function(T)? labelFor;
  const TbDropdown(
      {super.key,
      required this.values,
      required this.current,
      required this.onChange,
      this.labelFor});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: current,
        isDense: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: BorderSide(color: context.tBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: BorderSide(color: context.tBorder)),
        ),
        style: TextStyle(fontSize: 12, color: context.tTextPrimary),
        items: values
            .map((e) => DropdownMenuItem(
                  value: e,
                  child:
                      Text(labelFor != null ? labelFor!(e) : e.name),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChange(v);
        },
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TbTextField
// ─────────────────────────────────────────────────────────────────────────────

class TbTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onSubmitted;
  const TbTextField(
      {super.key, required this.value, required this.onSubmitted});

  @override
  State<TbTextField> createState() => _TbTextFieldState();
}

class _TbTextFieldState extends State<TbTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(TbTextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        style:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: BorderSide(color: context.tBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(kRadiusSm),
              borderSide: BorderSide(color: context.tBorder)),
          focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(kRadiusSm),
              borderSide: BorderSide(color: kGreen, width: 1.5)),
        ),
        onSubmitted: widget.onSubmitted,
        onEditingComplete: () => widget.onSubmitted(_ctrl.text),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TbDurationStepper
// ─────────────────────────────────────────────────────────────────────────────

class TbDurationStepper extends StatelessWidget {
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min, max;
  const TbDurationStepper(
      {super.key,
      required this.value,
      required this.onChanged,
      this.unit = '',
      this.min = 1,
      this.max = 99});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TbStepBtn(
              icon: Icons.remove_rounded,
              enabled: value > min,
              onTap: () => onChanged(value - 1)),
          SizedBox(
              width: 50,
              child: Text('$value $unit',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          TbStepBtn(
              icon: Icons.add_rounded,
              enabled: value < max,
              onTap: () => onChanged(value + 1)),
        ],
      );
}