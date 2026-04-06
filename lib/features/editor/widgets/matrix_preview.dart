import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/renderer/pixel_buffer.dart';
import '../../../engine/renderer/rgb565_encoder.dart';
import '../../../engine/scene/timeline.dart';
import '../../../shared/providers/providers.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MatrixPreview — live LED dot-matrix preview widget.
//
// Exported names from this file:  MatrixPreview  (only).
// All other classes are private (_) so they cannot clash with names in
// other widget files (this was what caused the `ambiguous_import` error
// for `LayerPanel` — a previous version of this file accidentally declared
// a public LayerPanel class).
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
    final timelineAsync = ref.watch(timelineProvider);
    final elapsedMs = ref.watch(previewElapsedMsProvider);
    final playing = ref.watch(previewPlayingProvider);
    final scene = ref.watch(sceneProvider);

    return Column(
      children: [
        // Canvas — fills available space
        Expanded(
          child: _CanvasArea(
            timelineAsync: timelineAsync,
            elapsedMs: elapsedMs,
          ),
        ),

        // Playback controls
        _PlaybackBar(
          playing: playing,
          elapsedMs: elapsedMs,
          onToggle: () {
            ref.read(previewPlayingProvider.notifier).state = !playing;
          },
          onReset: () {
            _elapsedMs = 0;
            ref.read(previewElapsedMsProvider.notifier).state = 0;
          },
        ),

        // Info strip
        _InfoStrip(
          width: scene.matrixWidth,
          height: scene.matrixHeight,
          fps: scene.fps,
          timelineAsync: timelineAsync,
        ),
      ],
    );
  }
}

// ── Canvas area ───────────────────────────────────────────────────────────────

class _CanvasArea extends StatelessWidget {
  final AsyncValue<Timeline> timelineAsync;
  final int elapsedMs;

  const _CanvasArea({required this.timelineAsync, required this.elapsedMs});

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFE0DDD6), // warm dot-grid background
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Subtle dot-grid texture
            Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),

            // LED matrix frame
            DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
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
          ],
        ),
      );
}

// ── Dot-grid background painter ───────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double step = 16;
    const double r = 1.0;
    final paint = Paint()..color = Colors.black.withOpacity(0.06);
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter _) => false;
}

// ── LED canvas ────────────────────────────────────────────────────────────────

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

  static const int _cols = 64;
  static const int _rows = 32;
  static const _dec = Rgb565Encoder();

  const _LedPainter({required this.timeline, required this.elapsedMs});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0A0A),
    );

    final Frame? frame = timeline.frameAt(elapsedMs);
    if (frame == null) return;

    final PixelBuffer buf = _dec.decode(frame.data);
    final double dW = size.width / _cols;
    final double dH = size.height / _rows;
    final double r = (dW < dH ? dW : dH) * 0.38;
    final paint = Paint()..isAntiAlias = true;

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final int argb = buf.getPixel(col, row);
        final bool on = (argb & 0x00FFFFFF) > 0x080808;
        paint.color =
            on ? Color(argb | 0xFF000000) : const Color(0xFF181818);
        canvas.drawCircle(
          Offset(col * dW + dW / 2, row * dH + dH / 2),
          r,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LedPainter old) =>
      old.elapsedMs != elapsedMs || old.timeline != timeline;
}

// ── Playback bar ──────────────────────────────────────────────────────────────

class _PlaybackBar extends StatelessWidget {
  final bool playing;
  final int elapsedMs;
  final VoidCallback onToggle;
  final VoidCallback onReset;

  const _PlaybackBar({
    required this.playing,
    required this.elapsedMs,
    required this.onToggle,
    required this.onReset,
  });

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        decoration: const BoxDecoration(
          border: Border(top: kPanelBorder, bottom: kPanelBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _PlayPauseButton(playing: playing, onTap: onToggle),
            const SizedBox(width: 8),
            Text(
              _fmt(elapsedMs),
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: kTextMuted,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onReset,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.replay_rounded, size: 14, color: kTextDim),
              ),
            ),
          ],
        ),
      );
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayPauseButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: kGreen,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 14,
            color: Colors.white,
          ),
        ),
      );
}

// ── Info strip ────────────────────────────────────────────────────────────────

class _InfoStrip extends StatelessWidget {
  final int width;
  final int height;
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
    final frameInfo = timelineAsync.when(
      loading: () => '—',
      error: (_, __) => '!',
      data: (t) =>
          '${t.frameCount} frames · ${(t.totalBytes / 1024).toStringAsFixed(1)} KB',
    );

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: kGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$width × $height  ·  RGB565  ·  ${fps.toStringAsFixed(0)} fps',
            style: const TextStyle(fontSize: 10, color: kTextDim),
          ),
          const Spacer(),
          Text(
            frameInfo,
            style: const TextStyle(fontSize: 10, color: kTextDim),
          ),
        ],
      ),
    );
  }
}

// ── Loading / Error placeholders ──────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Container(
        width: 256,
        height: 128,
        color: const Color(0xFF0A0A0A),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: kGreen,
            ),
          ),
        ),
      );
}

class _Error extends StatelessWidget {
  const _Error();
  @override
  Widget build(BuildContext context) => Container(
        width: 256,
        height: 128,
        color: const Color(0xFF0A0A0A),
        child: Center(
          child: Text(
            'render error',
            style: TextStyle(color: Colors.red.shade400, fontSize: 10),
          ),
        ),
      );
}