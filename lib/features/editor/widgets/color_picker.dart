import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compact HSV color picker that matches the toolbox panel aesthetic.
///
/// Shows:
/// - A saturation/value 2-D gradient square
/// - A hue rainbow strip below it
/// - An opacity strip
/// - A hex input field
/// - A live preview swatch
///
/// Usage:
/// ```dart
/// ColorPicker(
///   color: layer.color,
///   onChanged: (c) => notifier.updateLayer(layer.copyWith(color: c)),
/// )
/// ```
class ColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

  const ColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
  });

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late double _hue;        // 0–360
  late double _sat;        // 0–1
  late double _val;        // 0–1
  late double _opacity;    // 0–1

  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _fromColor(widget.color);
    _hexCtrl = TextEditingController(text: _toHex());
  }

  @override
  void didUpdateWidget(ColorPicker old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color) {
      _fromColor(widget.color);
      _hexCtrl.text = _toHex();
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  // ── Conversion helpers ────────────────────────────────────────────────────

  void _fromColor(Color c) {
    final HSVColor hsv = HSVColor.fromColor(c);
    _hue     = hsv.hue;
    _sat     = hsv.saturation;
    _val     = hsv.value;
    _opacity = c.opacity;
  }

  Color get _current =>
      HSVColor.fromAHSV(_opacity, _hue, _sat, _val).toColor();

  String _toHex() {
    final Color c = _current;
    return '${c.red.toRadixString(16).padLeft(2, '0')}'
        '${c.green.toRadixString(16).padLeft(2, '0')}'
        '${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  void _emit() {
    widget.onChanged(_current);
    _hexCtrl.text = _toHex();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── SV square ───────────────────────────────────────────────────────
        AspectRatio(
          aspectRatio: 1,
          child: _SVSquare(
            hue: _hue,
            sat: _sat,
            val: _val,
            onChanged: (s, v) {
              setState(() { _sat = s; _val = v; });
              _emit();
            },
          ),
        ),
        const SizedBox(height: 8),
        // ── Hue strip ───────────────────────────────────────────────────────
        _HueStrip(
          hue: _hue,
          onChanged: (h) {
            setState(() => _hue = h);
            _emit();
          },
        ),
        const SizedBox(height: 6),
        // ── Opacity strip ────────────────────────────────────────────────────
        _OpacityStrip(
          hue: _hue, sat: _sat, val: _val,
          opacity: _opacity,
          onChanged: (o) {
            setState(() => _opacity = o);
            _emit();
          },
        ),
        const SizedBox(height: 10),
        // ── Hex + swatch ─────────────────────────────────────────────────────
        Row(
          children: [
            // Swatch
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black.withOpacity(.15)),
              ),
            ),
            const SizedBox(width: 8),
            // Hex field
            Expanded(
              child: TextField(
                controller: _hexCtrl,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixText: '#',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _applyHex,
              ),
            ),
            const SizedBox(width: 8),
            // Opacity %
            SizedBox(
              width: 42,
              child: Text(
                '${(_opacity * 100).round()}%',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _applyHex(String hex) {
    final String clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return;
    try {
      final int value = int.parse(clean, radix: 16);
      final Color c = Color(0xFF000000 | value);
      setState(() => _fromColor(c.withOpacity(_opacity)));
      _emit();
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SV (Saturation/Value) square
// ─────────────────────────────────────────────────────────────────────────────

class _SVSquare extends StatelessWidget {
  final double hue, sat, val;
  final void Function(double sat, double val) onChanged;

  const _SVSquare({
    required this.hue,
    required this.sat,
    required this.val,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _update(d.localPosition, context),
      onPanUpdate: (d) => _update(d.localPosition, context),
      onTapDown: (d) => _update(d.localPosition, context),
      child: CustomPaint(
        painter: _SVPainter(hue: hue, sat: sat, val: val),
      ),
    );
  }

  void _update(Offset local, BuildContext ctx) {
    final RenderBox box = ctx.findRenderObject()! as RenderBox;
    final double s = (local.dx / box.size.width).clamp(0.0, 1.0);
    final double v = (1 - local.dy / box.size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }
}

class _SVPainter extends CustomPainter {
  final double hue, sat, val;
  const _SVPainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    // Saturation: white → hue
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    // Value: transparent → black (overlay)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    // Cursor circle
    final Offset cursor = Offset(sat * size.width, (1 - val) * size.height);
    canvas.drawCircle(
      cursor, 7,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2,
    );
    canvas.drawCircle(
      cursor, 5,
      Paint()..color = Colors.black.withOpacity(.3)..style = PaintingStyle.stroke..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SVPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hue strip
// ─────────────────────────────────────────────────────────────────────────────

class _HueStrip extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueStrip({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: GestureDetector(
        onPanStart:  (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown:   (d) => _update(d.localPosition, context),
        child: CustomPaint(painter: _HuePainter(hue: hue)),
      ),
    );
  }

  void _update(Offset local, BuildContext ctx) {
    final RenderBox box = ctx.findRenderObject()! as RenderBox;
    onChanged((local.dx / box.size.width).clamp(0.0, 1.0) * 360);
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    const int steps = 360;
    final double w = size.width / steps;

    for (int i = 0; i < steps; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * w, 0, w + 1, size.height),
        Paint()
          ..color = HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor(),
      );
    }

    // Border
    canvas.drawRect(rect,
        Paint()..color = Colors.black.withOpacity(.1)..style = PaintingStyle.stroke..strokeWidth = 1);

    // Cursor
    final double cx = hue / 360 * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 3, -1, 6, size.height + 2),
          const Radius.circular(3)),
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

// ─────────────────────────────────────────────────────────────────────────────
// Opacity strip
// ─────────────────────────────────────────────────────────────────────────────

class _OpacityStrip extends StatelessWidget {
  final double hue, sat, val, opacity;
  final ValueChanged<double> onChanged;

  const _OpacityStrip({
    required this.hue, required this.sat, required this.val,
    required this.opacity, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: GestureDetector(
        onPanStart:  (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown:   (d) => _update(d.localPosition, context),
        child: CustomPaint(
          painter: _OpacityPainter(
              hue: hue, sat: sat, val: val, opacity: opacity)),
      ),
    );
  }

  void _update(Offset local, BuildContext ctx) {
    final RenderBox box = ctx.findRenderObject()! as RenderBox;
    onChanged((local.dx / box.size.width).clamp(0.0, 1.0));
  }
}

class _OpacityPainter extends CustomPainter {
  final double hue, sat, val, opacity;
  const _OpacityPainter(
      {required this.hue, required this.sat, required this.val,
       required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    // Checkerboard background
    const double cs = 7;
    final Paint darkPaint = Paint()..color = Colors.grey.shade400;
    final Paint lightPaint = Paint()..color = Colors.grey.shade200;
    for (double y = 0; y < size.height; y += cs) {
      for (double x = 0; x < size.width; x += cs) {
        final bool dark = ((x ~/ cs) + (y ~/ cs)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, math.min(cs, size.width - x),
              math.min(cs, size.height - y)),
          dark ? darkPaint : lightPaint,
        );
      }
    }

    final Color base = HSVColor.fromAHSV(1, hue, sat, val).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [base.withOpacity(0), base],
        ).createShader(rect),
    );
    canvas.drawRect(rect,
        Paint()
          ..color = Colors.black.withOpacity(.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // Cursor
    final double cx = opacity * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 3, -1, 6, size.height + 2),
          const Radius.circular(3)),
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_OpacityPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val || old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience: show as a bottom sheet or popup
// ─────────────────────────────────────────────────────────────────────────────

/// Show the [ColorPicker] in a modal bottom sheet.
Future<Color?> showColorPicker(
  BuildContext context, {
  required Color initialColor,
}) async {
  Color result = initialColor;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pick colour',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ColorPicker(
              color: initialColor,
              onChanged: (c) => result = c,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF21C32C),
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Apply')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result;
}