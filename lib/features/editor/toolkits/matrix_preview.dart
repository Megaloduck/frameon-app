import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/renderer/pixel_buffer.dart';
import '../../../engine/scene/timeline.dart';
import '../../../shared/providers/providers.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MatrixPreview
//
// Drives a continuous Ticker that increments previewElapsedMsProvider every
// frame. previewFrameProvider watches that value and re-renders one PixelBuffer
// frame per tick — no frame count, no cap, no encode/decode round-trip.
//
// The timelineProvider is still watched here solely for the info strip stats
// (frame count, byte size) shown below the preview canvas. It is NOT used
// for the actual preview rendering.
// ─────────────────────────────────────────────────────────────────────────────

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
    // Live PixelBuffer — one frame rendered at current elapsedMs.
    final buffer = ref.watch(previewFrameProvider);

    // Timeline is only needed for the stats strip (frame count, KB).
    // It is no longer needed for rendering the preview.
    final timelineAsync = ref.watch(timelineProvider);

    final scene = ref.watch(sceneProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          const _PreviewLabel(),
          Expanded(
            child: _CanvasArea(buffer: buffer),
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

// ─────────────────────────────────────────────────────────────────────────────
// Preview label
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Canvas area
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasArea extends StatelessWidget {
  final PixelBuffer buffer;
  const _CanvasArea({required this.buffer});

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
                  child: _LedCanvas(buffer: buffer),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot grid background painter
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// LED canvas — wraps the painter in a LayoutBuilder
// ─────────────────────────────────────────────────────────────────────────────

class _LedCanvas extends StatelessWidget {
  final PixelBuffer buffer;
  const _LedCanvas({required this.buffer});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _LedPainter(buffer: buffer),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LED painter
//
// Reads directly from the PixelBuffer — no RGB565 encode/decode round-trip.
// Each pixel is checked per-channel so dim blues and greens render correctly
// (the old single 24-bit threshold incorrectly dimmed pure-blue pixels).
// ─────────────────────────────────────────────────────────────────────────────

class _LedPainter extends CustomPainter {
  final PixelBuffer buffer;

  static const int _cols = 64;
  static const int _rows = 32;

  const _LedPainter({required this.buffer});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark LED panel background.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0A0A));

    final double dW = size.width  / _cols;
    final double dH = size.height / _rows;
    // LED dot radius — 40% of the smaller cell dimension.
    final double r  = (dW < dH ? dW : dH) * 0.40;
    final paint = Paint()..isAntiAlias = true;

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final int argb = buffer.getPixel(col, row);

        // Check each channel independently so any single channel lighting
        // a pixel (e.g. pure blue 0x0000FF) is correctly treated as "on".
        final int r8 = (argb >> 16) & 0xFF;
        final int g8 = (argb >> 8)  & 0xFF;
        final int b8 =  argb        & 0xFF;
        final bool on = r8 > 8 || g8 > 8 || b8 > 8;

        paint.color = on
            ? Color(argb | 0xFF000000)   // lit LED — use pixel colour
            : const Color(0xFF181818);   // unlit LED — dark grey

        canvas.drawCircle(
          Offset(col * dW + dW / 2, row * dH + dH / 2),
          r,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LedPainter old) => old.buffer != buffer;
}

// ─────────────────────────────────────────────────────────────────────────────
// Info strip — shows matrix dimensions and export stats
// ─────────────────────────────────────────────────────────────────────────────

class _InfoStrip extends StatelessWidget {
  final int width, height;
  final double fps;
  final AsyncValue<Timeline> timelineAsync;

  const _InfoStrip({
    required this.width,
    required this.height,
    required this.fps,
    required this.timelineAsync,
  });

  @override
  Widget build(BuildContext context) {
    final right = timelineAsync.when(
      loading: () => 'rendering…',
      error:   (_, __) => 'render error',
      data: (t) =>
          '${t.frameCount} frames · ${(t.totalBytes / 1024).toStringAsFixed(1)} KB',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: kGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$width × $height  –  RGB565',
            style: TextStyle(fontSize: 11, color: context.tTextMuted),
          ),
          const SizedBox(width: 12),
          Text(
            right,
            style: TextStyle(fontSize: 11, color: context.tTextDim),
          ),
        ],
      ),
    );
  }
}