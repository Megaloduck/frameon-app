import 'package:flutter/material.dart';

import '../../../../engine/scene/layer.dart';
import '../color_picker.dart';
import '../ui_primitives.dart';

Widget tbGreenDropdown<T extends Enum>(
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
          items: values.map((e) => DropdownMenuItem(value: e, child: Text(e.name.toUpperCase()))).toList(),
          onChanged: (v) { if (v != null) onChange(v); },
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
                  color: active ? kGreen : kSurface,
                  border: Border.all(color: active ? kGreen : kBorder),
                  borderRadius: BorderRadius.horizontal(
                    left: v == TextAlignment.left ? const Radius.circular(6) : Radius.zero,
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
      height: 28, // ↓ reduce row height (default ~48)
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11), // ↓ smaller text
            ),
          ),
          Transform.scale(
            scale: 0.75, // ↓ main size reduction
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
  final double value; final ValueChanged<double> onChanged;
  const TbSpeedSlider({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 3),
          child: Slider(value: value.clamp(10, 500), min: 10, max: 500, onChanged: onChanged),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          Text('10ms fast', style: TextStyle(fontSize: 9, color: kTextDim)),
          Text('500ms slow', style: TextStyle(fontSize: 9, color: kTextDim)),
        ]),
      ]);
}

class TbStepper extends StatelessWidget {
  final String label; final int value; final String unit;
  final ValueChanged<int> onChanged; final int min, max;
  const TbStepper({super.key, required this.label, required this.value,
      required this.onChanged, this.unit = '', this.min = 1, this.max = 99});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: kTextPrimary))),
          TbStepBtn(icon: Icons.remove_rounded, enabled: value > min, onTap: () => onChanged(value - 1)),
          SizedBox(width: 40, child: Text('$value$unit', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          TbStepBtn(icon: Icons.add_rounded, enabled: value < max, onTap: () => onChanged(value + 1)),
        ]),
      );
}

class TbStepBtn extends StatelessWidget {
  final IconData icon; final bool enabled; final VoidCallback onTap;
  const TbStepBtn({super.key, required this.icon, required this.enabled, required this.onTap});
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

class TbTransportBtn extends StatelessWidget {
  final IconData icon; final bool filled; final bool active; final VoidCallback onTap;
  const TbTransportBtn({super.key, required this.icon, required this.onTap,
      this.filled = false, this.active = false});
  @override
  Widget build(BuildContext context) {
    final isActive = active && !filled;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF1DB954) : (isActive ? const Color(0xFF1DB954).withOpacity(0.15) : kSurface),
          shape: BoxShape.circle,
          border: Border.all(
            color: filled ? const Color(0xFF1DB954) : (isActive ? const Color(0xFF1DB954) : kBorder),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Icon(icon, size: filled ? 17 : 16,
            color: filled ? Colors.white : (isActive ? const Color(0xFF1DB954) : kTextMuted)),
      ),
    );
  }
}

Widget tbColorBtn(BuildContext ctx, Color color, ValueChanged<Color> onChange) =>
    GestureDetector(
      onTap: () async {
        final picked = await showColorPickerSheet(ctx, initialColor: color);
        if (picked != null) onChange(picked);
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

/// Plain enum dropdown.
/// [labelFor] supplies a human-readable label per value; defaults to [Enum.name].
class TbDropdown<T extends Enum> extends StatelessWidget {
  final List<T> values;
  final T current;
  final ValueChanged<T> onChange;
  final String Function(T)? labelFor;
  const TbDropdown({super.key, required this.values, required this.current,
      required this.onChange, this.labelFor});
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
        items: values.map((e) => DropdownMenuItem(
              value: e,
              child: Text(labelFor != null ? labelFor!(e) : e.name),
            )).toList(),
        onChanged: (v) { if (v != null) onChange(v); },
      );
}

class TbTextField extends StatefulWidget {
  final String value; final ValueChanged<String> onSubmitted;
  const TbTextField({super.key, required this.value, required this.onSubmitted});
  @override
  State<TbTextField> createState() => _TbTextFieldState();
}

class _TbTextFieldState extends State<TbTextField> {
  late final TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.value); }
  @override void didUpdateWidget(TbTextField old) {
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

class TbDurationStepper extends StatelessWidget {
  final int value; final String unit;
  final ValueChanged<int> onChanged; final int min, max;
  const TbDurationStepper({super.key, required this.value, required this.onChanged,
      this.unit = '', this.min = 1, this.max = 99});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TbStepBtn(icon: Icons.remove_rounded, enabled: value > min, onTap: () => onChanged(value - 1)),
          SizedBox(width: 50, child: Text('$value $unit', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          TbStepBtn(icon: Icons.add_rounded, enabled: value < max, onTap: () => onChanged(value + 1)),
        ],
      );
}