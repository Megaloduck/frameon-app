import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/renderer/pixel_buffer.dart';
import '../../../engine/scene/layer.dart';
import '../../../engine/scene/timeline.dart';
import '../../../shared/providers/providers.dart';
import '../presentation/controller.dart';
import 'ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MatrixPreview
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
    final buffer        = ref.watch(previewFrameProvider);
    final timelineAsync = ref.watch(timelineProvider);
    final scene         = ref.watch(sceneProvider);
    final selectedLayer = ref.watch(selectedLayerProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          const _PreviewLabel(),
          Expanded(child: _CanvasArea(buffer: buffer)),
          _InfoStrip(
            width:         scene.matrixWidth,
            height:        scene.matrixHeight,
            fps:           scene.fps,
            timelineAsync: timelineAsync,
            selectedLayer: selectedLayer,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag-axis constraint
//
//   ClockLayer → horizontal only (Y stays fixed)
//   TextLayer  → vertical only   (X stays fixed)
//   everything else → free (both axes)
// ─────────────────────────────────────────────────────────────────────────────

enum _DragAxis { horizontal, vertical, free }

_DragAxis _axisFor(Layer? layer) => _DragAxis.free;

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

class _CanvasArea extends ConsumerWidget {
  final PixelBuffer buffer;
  const _CanvasArea({required this.buffer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark        = context.isDark;
    final selectedLayer = ref.watch(selectedLayerProvider);

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
                  child: _InteractiveLedCanvas(
                    buffer: buffer,
                    selectedLayer: selectedLayer,
                    onDragStart: () {
                      ref.read(editorControllerProvider.notifier).snapshot();
                    },
                    onOffsetChanged: (offset) {
                      if (selectedLayer != null) {
                        ref.read(sceneProvider.notifier).updateLayer(
                          selectedLayer.copyWith(offset: offset),
                        );
                      }
                    },
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

// ─────────────────────────────────────────────────────────────────────────────
// Interactive LED canvas
// ─────────────────────────────────────────────────────────────────────────────

class _InteractiveLedCanvas extends StatefulWidget {
  final PixelBuffer  buffer;
  final Layer?       selectedLayer;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onOffsetChanged;

  const _InteractiveLedCanvas({
    required this.buffer,
    required this.selectedLayer,
    required this.onDragStart,
    required this.onOffsetChanged,
  });

  @override
  State<_InteractiveLedCanvas> createState() => _InteractiveLedCanvasState();
}

class _InteractiveLedCanvasState extends State<_InteractiveLedCanvas> {
  Offset? _dragStartMatrix;
  Offset? _dragStartLayerOffset;
  bool    _isDragging  = false;
  bool    _didSnapshot = false;

  bool get _canDrag => widget.selectedLayer != null;

  _DragAxis get _axis => _axisFor(widget.selectedLayer);

  /// Mouse cursor reflects the allowed drag axis.
  MouseCursor get _cursor {
    if (!_canDrag) return MouseCursor.defer;
    if (_isDragging) return SystemMouseCursors.grabbing;
    return switch (_axis) {
      _DragAxis.horizontal => SystemMouseCursors.resizeLeftRight,
      _DragAxis.vertical   => SystemMouseCursors.resizeUpDown,
      _DragAxis.free       => SystemMouseCursors.grab,
    };
  }

  Offset _toMatrix(Offset local, Size canvasSize) => Offset(
        local.dx / canvasSize.width  * 64,
        local.dy / canvasSize.height * 32,
      );

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    if (!_canDrag) return;
    setState(() {
      _dragStartMatrix      = _toMatrix(details.localPosition, canvasSize);
      _dragStartLayerOffset = widget.selectedLayer!.offset;
      _isDragging           = true;
      _didSnapshot          = false;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (!_canDrag || _dragStartMatrix == null || _dragStartLayerOffset == null) {
      return;
    }

    // Take a single undo snapshot at the start of each drag gesture.
    if (!_didSnapshot) {
      widget.onDragStart();
      _didSnapshot = true;
    }

    final current = _toMatrix(details.localPosition, canvasSize);
    final delta   = current - _dragStartMatrix!;

    // Apply axis constraint — freeze the locked axis at its drag-start value.
    final newOffset = switch (_axis) {
      _DragAxis.horizontal => Offset(
          _dragStartLayerOffset!.dx + delta.dx,
          _dragStartLayerOffset!.dy,            // Y frozen
        ),
      _DragAxis.vertical => Offset(
          _dragStartLayerOffset!.dx,             // X frozen
          _dragStartLayerOffset!.dy + delta.dy,
        ),
      _DragAxis.free => Offset(
          _dragStartLayerOffset!.dx + delta.dx,
          _dragStartLayerOffset!.dy + delta.dy,
        ),
    };

    widget.onOffsetChanged(newOffset);
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _isDragging           = false;
      _dragStartMatrix      = null;
      _dragStartLayerOffset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return MouseRegion(
          cursor: _cursor,
          child: GestureDetector(
            onPanStart:  (d) => _onPanStart(d, size),
            onPanUpdate: (d) => _onPanUpdate(d, size),
            onPanEnd:    _onPanEnd,
            child: Stack(
              children: [
                _LedCanvas(buffer: widget.buffer),

                // Selection border
                if (_canDrag)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(kRadiusSm),
                          border: Border.all(
                            color: kGreen.withOpacity(
                                _isDragging ? 0.9 : 0.35),
                            width: _isDragging ? 1.5 : 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Centre-line guides during drag — only on the active axis.
                if (_isDragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GuidePainter(axis: _axis),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Guide painter
//
//   horizontal → horizontal centre line only
//   vertical   → vertical centre line only
//   free       → both lines
// ─────────────────────────────────────────────────────────────────────────────

class _GuidePainter extends CustomPainter {
  final _DragAxis axis;
  const _GuidePainter({required this.axis});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = kGreen.withOpacity(0.20)
      ..strokeWidth = 0.5
      ..style       = PaintingStyle.stroke;

    // Horizontal centre line — shown for horizontal-only and free axes.
    if (axis == _DragAxis.horizontal || axis == _DragAxis.free) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }

    // Vertical centre line — shown for vertical-only and free axes.
    if (axis == _DragAxis.vertical || axis == _DragAxis.free) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.axis != axis;
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag hint — rendered inline in the info strip, no longer an overlay
// ─────────────────────────────────────────────────────────────────────────────

class _DragHint extends StatelessWidget {
  final Layer? layer;
  const _DragHint({required this.layer});

  String get _label => switch (_axisFor(layer)) {
        _DragAxis.horizontal => 'drag horizontally to reposition',
        _DragAxis.vertical   => 'drag vertically to reposition',
        _DragAxis.free       => 'drag on preview to reposition',
      };

  IconData get _icon => switch (_axisFor(layer)) {
        _DragAxis.horizontal => Icons.swap_horiz_rounded,
        _DragAxis.vertical   => Icons.swap_vert_rounded,
        _DragAxis.free       => Icons.open_with_rounded,
      };

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 10, color: kGreen.withOpacity(0.75)),
          const SizedBox(width: 4),
          Text(
            _label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: kGreen.withOpacity(0.75),
              letterSpacing: 0.04,
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot-grid background painter
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
// LED canvas wrapper
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
// ─────────────────────────────────────────────────────────────────────────────

class _LedPainter extends CustomPainter {
  final PixelBuffer buffer;

  static const int _cols = 64;
  static const int _rows = 32;

  const _LedPainter({required this.buffer});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0A0A0A));

    final double dW = size.width  / _cols;
    final double dH = size.height / _rows;
    final double r  = (dW < dH ? dW : dH) * 0.40;
    final paint = Paint()..isAntiAlias = true;

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final int argb = buffer.getPixel(col, row);

        final int r8 = (argb >> 16) & 0xFF;
        final int g8 = (argb >> 8)  & 0xFF;
        final int b8 =  argb        & 0xFF;
        final bool on = r8 > 8 || g8 > 8 || b8 > 8;

        paint.color = on
            ? Color(argb | 0xFF000000)
            : const Color(0xFF181818);

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
// Info strip
// ─────────────────────────────────────────────────────────────────────────────

class _InfoStrip extends StatelessWidget {
  final int    width, height;
  final double fps;
  final AsyncValue<Timeline> timelineAsync;
  final Layer? selectedLayer;

  const _InfoStrip({
    required this.width,
    required this.height,
    required this.fps,
    required this.timelineAsync,
    required this.selectedLayer,
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
            width: 7, height: 7,
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
          // When a layer is selected replace the frame stats with the drag hint.
          // When nothing is selected show the frame/size stats as normal.
          if (selectedLayer != null) ...[
            Container(
              width: 1, height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: context.tBorder,
            ),
            _DragHint(layer: selectedLayer),
          ] else ...[
            const SizedBox(width: 12),
            Text(
              right,
              style: TextStyle(fontSize: 11, color: context.tTextDim),
            ),
          ],
        ],
      ),
    );
  }
}