import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../engine/animation/animator.dart';
import '../../../../engine/renderer/font_effects.dart';
import '../../../../engine/renderer/lighting_effects.dart';
import '../../../../engine/renderer/font_organizer.dart';
import '../../../../engine/scene/layer.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PropertiesCustomizer
// ─────────────────────────────────────────────────────────────────────────────

class PropertiesCustomizer extends StatefulWidget {
  final Color initialColor;
  final LedFontId? initialFontId;
  final AnimationEffect? initialEffect;
  final int initialEffectSpeedMs;
  final AnimationEffect? initialLightingEffect;
  final int initialLightingSpeedMs;
  final bool showFont;
  final bool showFontEffect;
  final bool showLightingEffect;

  const PropertiesCustomizer({
    super.key,
    required this.initialColor,
    this.initialFontId,
    this.initialEffect,
    this.initialEffectSpeedMs = 100,
    this.initialLightingEffect,
    this.initialLightingSpeedMs = 100,
    this.showFont = true,
    this.showFontEffect = true,
    this.showLightingEffect = true,
  });

  @override
  State<PropertiesCustomizer> createState() => _PropertiesCustomizerState();
}

class _PropertiesCustomizerState extends State<PropertiesCustomizer> {
  late double _hue;
  late double _sat;
  late double _val;
  late double _opacity;
  late TextEditingController _hexCtrl;
  late LedFontId _fontId;
  late AnimationEffect _effect;
  late double _effectSpeedMs;
  late AnimationEffect _lightingEffect;
  late double _lightingSpeedMs;

  @override
  void initState() {
    super.initState();
    _fromColor(widget.initialColor);
    _hexCtrl = TextEditingController(text: _toHex());
    _fontId = widget.initialFontId ?? LedFontId.polymorph;
    _effect = widget.initialEffect ?? AnimationEffect.none;
    _effectSpeedMs = widget.initialEffectSpeedMs.toDouble();
    _lightingEffect = widget.initialLightingEffect ?? AnimationEffect.none;
    _lightingSpeedMs = widget.initialLightingSpeedMs.toDouble();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _fromColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    _hue = hsv.hue;
    _sat = hsv.saturation;
    _val = hsv.value;
    _opacity = c.opacity;
  }

  Color get _currentColor =>
      HSVColor.fromAHSV(_opacity, _hue, _sat, _val).toColor();

  String _toHex() {
    final c = _currentColor;
    return '${c.red.toRadixString(16).padLeft(2, '0')}'
            '${c.green.toRadixString(16).padLeft(2, '0')}'
            '${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  void _onColorChanged() {
    setState(() {});
    _hexCtrl.text = _toHex();
  }

  void _applyHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return;
    try {
      final value = int.parse(clean, radix: 16);
      final c = Color(0xFF000000 | value);
      setState(() => _fromColor(c.withOpacity(_opacity)));
    } catch (_) {}
  }

  PropertiesResult get _result => PropertiesResult(
        color: _currentColor,
        fontId: _fontId,
        effect: _effect,
        effectSpeedMs: _effectSpeedMs.round(),
        lightingEffect: _lightingEffect,
        lightingSpeedMs: _lightingSpeedMs.round(),
      );

  bool get _isScrollEffect =>
      _effect == AnimationEffect.scrollLeft ||
      _effect == AnimationEffect.scrollRight;

  static const _fontEffects = [
    AnimationEffect.none,
    AnimationEffect.scrollLeft,
    AnimationEffect.scrollRight,
    AnimationEffect.blink,
    AnimationEffect.pulse,
    AnimationEffect.fade,
    AnimationEffect.burst,
  ];

  // Only effects that have a real LightingEffectProcessor implementation.
  // fade / burst / blink / scroll* have no lighting equivalent — excluded to
  // avoid silently doing nothing when selected.
  static const _lightingEffects = [
    AnimationEffect.none,
    AnimationEffect.pulse,
  ];

  String _effectLabel(AnimationEffect e) => switch (e) {
        AnimationEffect.none => 'Static',
        AnimationEffect.blink => 'Blink',
        AnimationEffect.scrollLeft => 'Scroll Left',
        AnimationEffect.scrollRight => 'Scroll Right',
        AnimationEffect.pulse => 'Pulse',
        AnimationEffect.fade => 'Fade',
        AnimationEffect.burst => 'Burst',
      };

  // Exhaustive — compiler will flag any new AnimationEffect values not handled.
  String _lightingLabel(AnimationEffect e) => switch (e) {
        AnimationEffect.none        => 'Static',
        AnimationEffect.pulse       => 'Breathing',
        // Not exposed in _lightingEffects but required for exhaustiveness:
        AnimationEffect.blink       => 'Blink',
        AnimationEffect.fade        => 'Fading',
        AnimationEffect.burst       => 'Burst',
        AnimationEffect.scrollLeft  => 'Scroll Left',
        AnimationEffect.scrollRight => 'Scroll Right',
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF242424) : const Color(0xFFF8F7F3);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0DDD6);
    final bg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFECEAE3);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Properties Customizer',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left: Color picker ──────────────────────────────────
                SizedBox(
                  width: 220,
                  child: _ColorPickerColumn(
                    hue: _hue,
                    sat: _sat,
                    val: _val,
                    opacity: _opacity,
                    hexCtrl: _hexCtrl,
                    currentColor: _currentColor,
                    onSVChanged: (s, v) {
                      _sat = s;
                      _val = v;
                      _onColorChanged();
                    },
                    onHueChanged: (h) {
                      _hue = h;
                      _onColorChanged();
                    },
                    onOpacityChanged: (o) {
                      _opacity = o;
                      _onColorChanged();
                    },
                    onHexSubmitted: _applyHex,
                  ),
                ),
                const SizedBox(width: 16),
                Container(width: 1, color: border),
                const SizedBox(width: 16),
                // ── Right: Controls ─────────────────────────────────────
                Expanded(
                  child: _ControlsColumn(
                    isDark: isDark,
                    surface: surface,
                    border: border,
                    showFont: widget.showFont,
                    fontId: _fontId,
                    onFontChanged: (v) => setState(() => _fontId = v),
                    showFontEffect: widget.showFontEffect,
                    effect: _effect,
                    isScrollEffect: _isScrollEffect,
                    effectSpeedMs: _effectSpeedMs,
                    fontEffects: _fontEffects,
                    effectLabel: _effectLabel,
                    onScrollLeft: () => setState(() {
                      _effect = _effect == AnimationEffect.scrollLeft
                          ? AnimationEffect.none
                          : AnimationEffect.scrollLeft;
                    }),
                    onScrollRight: () => setState(() {
                      _effect = _effect == AnimationEffect.scrollRight
                          ? AnimationEffect.none
                          : AnimationEffect.scrollRight;
                    }),
                    onEffectChanged: (v) => setState(() => _effect = v),
                    onEffectSpeedChanged: (v) =>
                        setState(() => _effectSpeedMs = v),
                    showLighting: widget.showLightingEffect,
                    lightingEffect: _lightingEffect,
                    lightingSpeedMs: _lightingSpeedMs,
                    lightingEffects: _lightingEffects,
                    lightingLabel: _lightingLabel,
                    onLightingChanged: (v) =>
                        setState(() => _lightingEffect = v),
                    onLightingSpeedChanged: (v) =>
                        setState(() => _lightingSpeedMs = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: kTextMuted)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context, _result),
                child: const Text('Apply',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Left column: Color picker
// FIX: Hue and Opacity strips now use LayoutBuilder so CustomPaint
//      receives a real finite size and actually renders.
// ─────────────────────────────────────────────────────────────────────────────

class _ColorPickerColumn extends StatelessWidget {
  final double hue, sat, val, opacity;
  final TextEditingController hexCtrl;
  final Color currentColor;
  final void Function(double s, double v) onSVChanged;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<String> onHexSubmitted;

  const _ColorPickerColumn({
    required this.hue,
    required this.sat,
    required this.val,
    required this.opacity,
    required this.hexCtrl,
    required this.currentColor,
    required this.onSVChanged,
    required this.onHueChanged,
    required this.onOpacityChanged,
    required this.onHexSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Color Picker',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
              color: kTextMuted),
        ),
        const SizedBox(height: 8),

        // ── SV Square ───────────────────────────────────────────────────
        SizedBox(
          width: 220,
          height: 220,
          child: _SVSquare(
            hue: hue,
            sat: sat,
            val: val,
            onChanged: onSVChanged,
          ),
        ),

        const SizedBox(height: 10),

        // ── Hue strip ───────────────────────────────────────────────────
        // FIX: wrap in SizedBox with explicit width so CustomPaint
        //      gets a finite constraint and renders visibly.
        SizedBox(
          width: 220,
          height: 16,
          child: _HueStrip(hue: hue, onChanged: onHueChanged),
        ),

        const SizedBox(height: 6),

        // ── Opacity strip ────────────────────────────────────────────────
        // FIX: same explicit size fix as hue strip above.
        SizedBox(
          width: 220,
          height: 16,
          child: _OpacityStrip(
            hue: hue,
            sat: sat,
            val: val,
            opacity: opacity,
            onChanged: onOpacityChanged,
          ),
        ),

        const SizedBox(height: 10),

        // ── Swatch + hex input ───────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black.withOpacity(0.15)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: hexCtrl,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '#',
                    prefixStyle: const TextStyle(color: kTextMuted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: Color(0xFFE0DDD6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: Color(0xFFE0DDD6)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: kGreen, width: 1.5),
                    ),
                  ),
                  onSubmitted: onHexSubmitted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right column: Font + Effect controls
// ─────────────────────────────────────────────────────────────────────────────

class _ControlsColumn extends StatelessWidget {
  final bool isDark;
  final Color surface, border;
  final bool showFont;
  final LedFontId fontId;
  final ValueChanged<LedFontId> onFontChanged;
  final bool showFontEffect;
  final AnimationEffect effect;
  final bool isScrollEffect;
  final double effectSpeedMs;
  final List<AnimationEffect> fontEffects;
  final String Function(AnimationEffect) effectLabel;
  final VoidCallback onScrollLeft;
  final VoidCallback onScrollRight;
  final ValueChanged<AnimationEffect> onEffectChanged;
  final ValueChanged<double> onEffectSpeedChanged;
  final bool showLighting;
  final AnimationEffect lightingEffect;
  final double lightingSpeedMs;
  final List<AnimationEffect> lightingEffects;
  final String Function(AnimationEffect) lightingLabel;
  final ValueChanged<AnimationEffect> onLightingChanged;
  final ValueChanged<double> onLightingSpeedChanged;

  const _ControlsColumn({
    required this.isDark,
    required this.surface,
    required this.border,
    required this.showFont,
    required this.fontId,
    required this.onFontChanged,
    required this.showFontEffect,
    required this.effect,
    required this.isScrollEffect,
    required this.effectSpeedMs,
    required this.fontEffects,
    required this.effectLabel,
    required this.onScrollLeft,
    required this.onScrollRight,
    required this.onEffectChanged,
    required this.onEffectSpeedChanged,
    required this.showLighting,
    required this.lightingEffect,
    required this.lightingSpeedMs,
    required this.lightingEffects,
    required this.lightingLabel,
    required this.onLightingChanged,
    required this.onLightingSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFont) ...[
          _ControlLabel('Font Style'),
          const SizedBox(height: 6),
          _StyledDropdown<LedFontId>(
            value: fontId,
            items: LedFontId.values,
            labelFor: (v) => LedFontLibrary.get(v).name,
            onChanged: onFontChanged,
            surface: surface,
            border: border,
          ),
          const SizedBox(height: 14),
        ],
        if (showFontEffect) ...[
          _ControlLabel('Font Effect'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _ToggleButton(
                  label: 'Scroll Left',
                  active: effect == AnimationEffect.scrollLeft,
                  onTap: onScrollLeft,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ToggleButton(
                  label: 'Scroll Right',
                  active: effect == AnimationEffect.scrollRight,
                  onTap: onScrollRight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StyledDropdown<AnimationEffect>(
            value: isScrollEffect ? AnimationEffect.none : effect,
            items: fontEffects
                .where((e) =>
                    e != AnimationEffect.scrollLeft &&
                    e != AnimationEffect.scrollRight)
                .toList(),
            labelFor: effectLabel,
            onChanged: onEffectChanged,
            surface: surface,
            border: border,
          ),
          // Speed slider is only meaningful when an effect is active.
          if (effect != AnimationEffect.none) ...[
            const SizedBox(height: 10),
            _SpeedSlider(
              value: effectSpeedMs,
              onChanged: onEffectSpeedChanged,
            ),
          ],
          const SizedBox(height: 14),
        ],
        if (showLighting) ...[
          _ControlLabel('Lighting Effect'),
          const SizedBox(height: 6),
          _StyledDropdown<AnimationEffect>(
            value: lightingEffect,
            items: lightingEffects,
            labelFor: lightingLabel,
            onChanged: onLightingChanged,
            surface: surface,
            border: border,
          ),
          // Speed slider is only meaningful when a lighting effect is active.
          if (lightingEffect != AnimationEffect.none) ...[
            const SizedBox(height: 10),
            _SpeedSlider(
              value: lightingSpeedMs,
              onChanged: onLightingSpeedChanged,
            ),
          ],
        ],
        const Spacer(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ControlLabel extends StatelessWidget {
  final String text;
  const _ControlLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: kTextMuted),
      );
}

class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;
  final Color surface, border;

  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
    required this.surface,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: kTextMuted),
          style: const TextStyle(fontSize: 12, color: kTextPrimary),
          dropdownColor: surface,
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(labelFor(e)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? kGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: active ? kGreen : const Color(0xFFE0DDD6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : kTextMuted,
            ),
          ),
        ),
      );
}

class _SpeedSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _SpeedSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: kGreen,
              inactiveTrackColor: const Color(0xFFE0DDD6),
              thumbColor: kGreen,
              overlayColor: kGreen.withOpacity(0.12),
            ),
            child: Slider(
              value: value.clamp(10, 500),
              min: 10,
              max: 500,
              onChanged: onChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Slow', style: TextStyle(fontSize: 9, color: kTextDim)),
                Text('Normal',
                    style: TextStyle(fontSize: 9, color: kTextDim)),
                Text('Fast', style: TextStyle(fontSize: 9, color: kTextDim)),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SV Square
// ─────────────────────────────────────────────────────────────────────────────

class _SVSquare extends StatelessWidget {
  final double hue, sat, val;
  final void Function(double s, double v) onChanged;

  const _SVSquare({
    required this.hue,
    required this.sat,
    required this.val,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onPanStart: (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown: (d) => _update(d.localPosition, context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black.withOpacity(0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              painter: _SVPainter(hue: hue, sat: sat, val: val),
              size: Size.infinite,
            ),
          ),
        ),
      );

  void _update(Offset local, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final size = box.size;
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }
}

class _SVPainter extends CustomPainter {
  final double hue, sat, val;
  const _SVPainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white,
              HSVColor.fromAHSV(1, hue, 1, 1).toColor()
            ],
          ).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(rect));

    final cx = sat * size.width;
    final cy = (1 - val) * size.height;
    canvas.drawCircle(
        Offset(cx, cy),
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()
          ..color = Colors.black.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_SVPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hue Strip
// FIX: GestureDetector now wraps a Container with explicit size, then
//      CustomPaint fills it — ensures painter always gets finite constraints.
// ─────────────────────────────────────────────────────────────────────────────

class _HueStrip extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueStrip({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onPanStart: (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown: (d) => _update(d.localPosition, context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _HuePainter(hue: hue),
            // FIX: size must be non-zero. The parent SizedBox(220×16)
            // supplies the constraints; Size.infinite lets it fill them.
            size: Size.infinite,
          ),
        ),
      );

  void _update(Offset local, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    onChanged((local.dx / box.size.width).clamp(0.0, 1.0) * 360);
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
            stops: [0.0, 0.16, 0.33, 0.5, 0.66, 0.83, 1.0],
          ).createShader(rect));

    final cx = (hue / 360) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 2, 1, 4, size.height - 2),
          const Radius.circular(2)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

// ─────────────────────────────────────────────────────────────────────────────
// Opacity Strip
// FIX: same finite-size fix as HueStrip above.
// ─────────────────────────────────────────────────────────────────────────────

class _OpacityStrip extends StatelessWidget {
  final double hue, sat, val, opacity;
  final ValueChanged<double> onChanged;
  const _OpacityStrip({
    required this.hue,
    required this.sat,
    required this.val,
    required this.opacity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onPanStart: (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown: (d) => _update(d.localPosition, context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _OpacityPainter(
                hue: hue, sat: sat, val: val, opacity: opacity),
            // FIX: Size.infinite fills the parent SizedBox(220×16).
            size: Size.infinite,
          ),
        ),
      );

  void _update(Offset local, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    onChanged((local.dx / box.size.width).clamp(0.0, 1.0));
  }
}

class _OpacityPainter extends CustomPainter {
  final double hue, sat, val, opacity;
  const _OpacityPainter(
      {required this.hue,
      required this.sat,
      required this.val,
      required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const checker = 5.0;
    final dark = Paint()..color = Colors.grey.shade300;
    final light = Paint()..color = Colors.grey.shade100;

    for (double y = 0; y < size.height; y += checker) {
      for (double x = 0; x < size.width; x += checker) {
        final odd = ((x ~/ checker) + (y ~/ checker)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, math.min(checker, size.width - x),
              math.min(checker, size.height - y)),
          odd ? dark : light,
        );
      }
    }

    final base = HSVColor.fromAHSV(1, hue, sat, val).toColor();
    canvas.drawRect(
        rect,
        Paint()
          ..shader =
              LinearGradient(colors: [base.withOpacity(0), base])
                  .createShader(rect));

    final cx = opacity * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 2, 1, 4, size.height - 2),
          const Radius.circular(2)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_OpacityPainter old) =>
      old.hue != hue ||
      old.sat != sat ||
      old.val != val ||
      old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// Result model
// ─────────────────────────────────────────────────────────────────────────────

class PropertiesResult {
  final Color color;
  final LedFontId fontId;
  final AnimationEffect effect;
  final int effectSpeedMs;
  final AnimationEffect lightingEffect;
  final int lightingSpeedMs;

  const PropertiesResult({
    required this.color,
    required this.fontId,
    required this.effect,
    required this.effectSpeedMs,
    required this.lightingEffect,
    required this.lightingSpeedMs,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// showPropertiesCustomizer
// ─────────────────────────────────────────────────────────────────────────────

Future<PropertiesResult?> showPropertiesCustomizer(
  BuildContext context, {
  required Color initialColor,
  LedFontId? initialFontId,
  AnimationEffect? initialEffect,
  int initialEffectSpeedMs = 100,
  AnimationEffect? initialLightingEffect,
  int initialLightingSpeedMs = 100,
  bool showFont = true,
  bool showFontEffect = true,
  bool showLightingEffect = true,
}) {
  return showModalBottomSheet<PropertiesResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SingleChildScrollView(
      child: PropertiesCustomizer(
        initialColor: initialColor,
        initialFontId: initialFontId,
        initialEffect: initialEffect,
        initialEffectSpeedMs: initialEffectSpeedMs,
        initialLightingEffect: initialLightingEffect,
        initialLightingSpeedMs: initialLightingSpeedMs,
        showFont: showFont,
        showFontEffect: showFontEffect,
        showLightingEffect: showLightingEffect,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Backward-compat shim
// ─────────────────────────────────────────────────────────────────────────────

Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initialColor,
}) async {
  final result = await showPropertiesCustomizer(
    context,
    initialColor: initialColor,
    showFont: false,
    showFontEffect: false,
    showLightingEffect: false,
  );
  return result?.color;
}