import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui_primitives.dart';

/// Compact HSV color picker that matches the toolbox panel aesthetic.
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
  late double _hue;
  late double _sat;
  late double _val;
  late double _opacity;

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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── SV square ──────────────────────────────────────────────────
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth.clamp(150.0, 280.0);
            return Center(
              child: SizedBox(
                width: size,
                height: size,
                child: _SVSquare(
                  hue: _hue,
                  sat: _sat,
                  val: _val,
                  onChanged: (s, v) {
                    setState(() {
                      _sat = s;
                      _val = v;
                    });
                    _emit();
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // ── Hue strip ──────────────────────────────────────────────────
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: _HueStrip(
                hue: _hue,
                onChanged: (h) {
                  setState(() => _hue = h);
                  _emit();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ── Opacity strip ───────────────────────────────────────────────
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: _OpacityStrip(
                hue: _hue,
                sat: _sat,
                val: _val,
                opacity: _opacity,
                onChanged: (o) {
                  setState(() => _opacity = o);
                  _emit();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                '${(_opacity * 100).round()}%',
                style: const TextStyle(fontSize: 11),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Hex + swatch ────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.tBorder),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _hexCtrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '#',
                  prefixStyle: TextStyle(color: context.tTextMuted),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: context.tBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: context.tBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: kGreen, width: 1.5),
                  ),
                ),
                onSubmitted: _applyHex,
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

// ── SV Square ──────────────────────────────────────────────────────────────

class _SVSquare extends StatelessWidget {
  final double hue, sat, val;
  final void Function(double sat, double val) onChanged;

  const _SVSquare(
      {required this.hue,
      required this.sat,
      required this.val,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart:  (d) => _update(d.localPosition, context),
      onPanUpdate: (d) => _update(d.localPosition, context),
      onTapDown:   (d) => _update(d.localPosition, context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.tBorder),
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
  }

  void _update(Offset local, BuildContext context) {
    final box  = context.findRenderObject() as RenderBox;
    final size = box.size;
    final s    = (local.dx / size.width).clamp(0.0, 1.0);
    final v    = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }
}

class _SVPainter extends CustomPainter {
  final double hue, sat, val;
  const _SVPainter(
      {required this.hue, required this.sat, required this.val});

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

    final cursor = Offset(sat * size.width, (1 - val) * size.height);
    canvas.drawCircle(
        cursor,
        6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawCircle(
        cursor,
        4,
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_SVPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}

// ── Hue Strip ──────────────────────────────────────────────────────────────

class _HueStrip extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueStrip({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: GestureDetector(
        onPanStart:  (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown:   (d) => _update(d.localPosition, context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.tBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(painter: _HuePainter(hue: hue)),
          ),
        ),
      ),
    );
  }

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
              Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
              Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
            stops: [0.0, 0.16, 0.33, 0.5, 0.66, 0.83, 1.0],
          ).createShader(rect));

    final cx = (hue / 360) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 2, 2, 4, size.height - 4),
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

// ── Opacity Strip ──────────────────────────────────────────────────────────

class _OpacityStrip extends StatelessWidget {
  final double hue, sat, val, opacity;
  final ValueChanged<double> onChanged;
  const _OpacityStrip(
      {required this.hue,
      required this.sat,
      required this.val,
      required this.opacity,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: GestureDetector(
        onPanStart:  (d) => _update(d.localPosition, context),
        onPanUpdate: (d) => _update(d.localPosition, context),
        onTapDown:   (d) => _update(d.localPosition, context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.tBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: _OpacityPainter(
                  hue: hue, sat: sat, val: val, opacity: opacity),
            ),
          ),
        ),
      ),
    );
  }

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
    final rect         = Offset.zero & size;
    const checkerSize  = 6.0;
    // Checkerboard uses neutral greys — fine as literal colours in a painter.
    final darkPaint  = Paint()..color = Colors.grey.shade300;
    final lightPaint = Paint()..color = Colors.grey.shade100;

    for (double y = 0; y < size.height; y += checkerSize) {
      for (double x = 0; x < size.width; x += checkerSize) {
        final isOdd = ((x ~/ checkerSize) + (y ~/ checkerSize)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y,
              math.min(checkerSize, size.width - x),
              math.min(checkerSize, size.height - y)),
          isOdd ? darkPaint : lightPaint,
        );
      }
    }

    final baseColor = HSVColor.fromAHSV(1, hue, sat, val).toColor();
    canvas.drawRect(
        rect,
        Paint()
          ..shader =
              LinearGradient(colors: [baseColor.withOpacity(0), baseColor])
                  .createShader(rect));

    final cx = opacity * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 2, 2, 4, size.height - 4),
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
// showColorPickerSheet
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the color picker in a modal bottom sheet.
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initialColor,
}) async {
  Color result = initialColor;

  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ctx.tSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ctx.tBorder),
      ),
      child: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pick Color',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ColorPicker(
              color: result,
              onChanged: (c) => setState(() => result = c),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, result),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

@Deprecated('Use showColorPickerSheet instead')
Future<Color?> showColorPicker(BuildContext context,
    {required Color initialColor}) {
  return showColorPickerSheet(context, initialColor: initialColor);
}