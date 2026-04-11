import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/renderer/pixel_buffer.dart';
import '../../../engine/renderer/rgb565_encoder.dart';
import '../../../engine/scene/timeline.dart';
import '../../../shared/providers/providers.dart';
import 'ui_primitives.dart';

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
    final scene         = ref.watch(sceneProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          const _PreviewLabel(),
          Expanded(
            child: _CanvasArea(
              timelineAsync: timelineAsync,
              elapsedMs: elapsedMs,
            ),
          ),
          _InfoStrip(
            width:         scene.matrixWidth,
            height:        scene.matrixHeight,
            fps:           scene.fps,
            timelineAsync: timelineAsync,
          ),
        ],
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
        child: Text(
          'MATRIX PREVIEW',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.08,
            color: context.tTextMuted.withOpacity(0.7),
          ),
        ),
      );
}

class _CanvasArea extends StatelessWidget {
  final AsyncValue<Timeline> timelineAsync;
  final int elapsedMs;
  const _CanvasArea({required this.timelineAsync, required this.elapsedMs});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _DotGridPainter(isDark: isDark)),
        ),
        Center(
          child: AspectRatio(
            aspectRatio: 64 / 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.5 : 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(kRadiusSm),
                  child: timelineAsync.when(
                    loading: () => const _Loading(),
                    error: (_, __) => const _Error(),
                    data: (t) => _LedCanvas(timeline: t, elapsedMs: elapsedMs),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final bool isDark;
  const _DotGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const double step = 18;
    const double r    = 1.2;
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.06)
          : Colors.black.withOpacity(0.055);
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.isDark != isDark;
}

class _LedCanvas extends StatelessWidget {
  final Timeline timeline;
  final int elapsedMs;
  const _LedCanvas({required this.timeline, required this.elapsedMs});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _LedPainter(timeline: timeline, elapsedMs: elapsedMs),
        ),
      );
}

class _LedPainter extends CustomPainter {
  final Timeline timeline;
  final int elapsedMs;

  static const int  _cols = 64;
  static const int  _rows = 32;
  static const _dec = Rgb565Encoder();

  const _LedPainter({required this.timeline, required this.elapsedMs});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0A0A));

    final Frame? frame = timeline.frameAt(elapsedMs);
    if (frame == null) return;

    final PixelBuffer buf = _dec.decode(frame.data);
    final double dW = size.width  / _cols;
    final double dH = size.height / _rows;
    final double r  = (dW < dH ? dW : dH) * 0.40;
    final paint = Paint()..isAntiAlias = true;

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final int argb = buf.getPixel(col, row);

        // ── "LED is on" check ──────────────────────────────────────────
        // Old check: (argb & 0x00FFFFFF) > 0x080808
        // Bug: treats the RGB value as a single 24-bit integer, so pure
        // blue (0x0000FF = 255) and any color where only the blue channel
        // is lit would fail the threshold (0x080808 = 526) and render dark.
        //
        // Fix: check each channel independently — a pixel is "on" if ANY
        // channel exceeds a small noise floor (8/255). This correctly
        // handles pure blue, pure green, dim colors, and everything else.
        final int r8 = (argb >> 16) & 0xFF;
        final int g8 = (argb >> 8)  & 0xFF;
        final int b8 =  argb        & 0xFF;
        final bool on = r8 > 8 || g8 > 8 || b8 > 8;

        paint.color = on ? Color(argb | 0xFF000000) : const Color(0xFF181818);
        canvas.drawCircle(
          Offset(col * dW + dW / 2, row * dH + dH / 2), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LedPainter old) =>
      old.elapsedMs != elapsedMs || old.timeline != timeline;
}

class _InfoStrip extends StatelessWidget {
  final int width, height;
  final double fps;
  final AsyncValue<Timeline> timelineAsync;
  const _InfoStrip({
    required this.width, required this.height,
    required this.fps, required this.timelineAsync,
  });

  @override
  Widget build(BuildContext context) {
    final right = timelineAsync.when(
      loading: () => '—',
      error: (_, __) => '!',
      data: (t) =>
          '${t.frameCount} frames · ${(t.totalBytes / 1024).toStringAsFixed(1)} KB',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$width × $height  –  RGB565',
            style: TextStyle(fontSize: 11, color: context.tTextMuted),
          ),
          const SizedBox(width: 12),
          Text(right, style: TextStyle(fontSize: 11, color: context.tTextDim)),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0A0A0A),
        child: const Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: kGreen),
          ),
        ),
      );
}

class _Error extends StatelessWidget {
  const _Error();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0A0A0A),
        child: Center(
          child: Text('render error',
              style: TextStyle(color: Colors.red.shade400, fontSize: 10)),
        ),
      );
}