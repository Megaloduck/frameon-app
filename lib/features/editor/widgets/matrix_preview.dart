import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/renderer/pixel_buffer.dart';
import '../../../engine/renderer/rgb565_encoder.dart';
import '../../../engine/scene/timeline.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/zoom_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MatrixPreview
// ─────────────────────────────────────────────────────────────────────────────

/// Live LED dot-matrix preview. Scales dot size based on [zoomProvider].
class MatrixPreview extends ConsumerStatefulWidget {
  const MatrixPreview({super.key});

  @override
  ConsumerState<MatrixPreview> createState() => _MatrixPreviewState();
}

class _MatrixPreviewState extends ConsumerState<MatrixPreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _elapsedMs = 0;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    if (_lastTick != null && ref.read(previewPlayingProvider)) {
      _elapsedMs += now.difference(_lastTick!).inMilliseconds;
      ref.read(previewElapsedMsProvider.notifier).state = _elapsedMs;
    }
    _lastTick = now;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(timelineProvider);
    final elapsedMs     = ref.watch(previewElapsedMsProvider);
    // Zoom is informational here — MatrixPreview fills its parent;
    // zoom is used by the parent to size the container if needed.
    // The dot size auto-scales to the available space.

    return Container(
      color: const Color(0xFF0A0A0A),
      child: AspectRatio(
        aspectRatio: 64 / 32,
        child: timelineAsync.when(
          loading: () => const _Loading(),
          error: (e, _) => const _Error(),
          data: (t) => _Canvas(timeline: t, elapsedMs: elapsedMs),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Canvas + Painter
// ─────────────────────────────────────────────────────────────────────────────

class _Canvas extends StatelessWidget {
  final Timeline timeline;
  final int elapsedMs;
  const _Canvas({required this.timeline, required this.elapsedMs});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _Painter(timeline: timeline, elapsedMs: elapsedMs),
        ),
      );
}

class _Painter extends CustomPainter {
  final Timeline timeline;
  final int elapsedMs;

  static const int _cols = 64;
  static const int _rows = 32;
  static const _dec = Rgb565Encoder();

  const _Painter({required this.timeline, required this.elapsedMs});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0A0A0A));

    final Frame? frame = timeline.frameAt(elapsedMs);
    if (frame == null) return;

    final PixelBuffer buf = _dec.decode(frame.data);
    final double dW = size.width / _cols;
    final double dH = size.height / _rows;
    // Dot radius = 78% of half a cell (leaves 22% gap — matches real LED panels)
    final double r = (dW < dH ? dW : dH) * 0.39;
    final Paint paint = Paint()..isAntiAlias = true;

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final int argb = buf.getPixel(col, row);
        final bool on  = (argb & 0x00FFFFFF) > 0x080808;
        paint.color = on ? Color(argb | 0xFF000000) : const Color(0xFF111111);
        canvas.drawCircle(
            Offset(col * dW + dW / 2, row * dH + dH / 2), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.elapsedMs != elapsedMs || old.timeline != timeline;
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / error states
// ─────────────────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF21C32C)),
        ),
      );
}

class _Error extends StatelessWidget {
  const _Error();
  @override
  Widget build(BuildContext context) => Center(
        child: Text('render error',
            style: TextStyle(color: Colors.red.shade400, fontSize: 11)),
      );
}