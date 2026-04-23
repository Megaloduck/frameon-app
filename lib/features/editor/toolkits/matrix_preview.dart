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
    final buffer       = ref.watch(previewFrameProvider);
    final timelineAsync = ref.watch(timelineProvider);
    final scene        = ref.watch(sceneProvider);

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
// Canvas area — wraps the LED canvas, dot-grid background, and drag logic
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasArea extends ConsumerWidget {
  final PixelBuffer buffer;
  const _CanvasArea({required this.buffer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark        = context.isDark;
    final selectedLayer = ref.watch(selectedLayerProvider);
    final canDrag       = selectedLayer != null;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Dot-grid background
        Positioned.fill(
          child: CustomPaint(painter: _DotGridPainter(isDark: isDark)),
        ),

        // LED matrix canvas
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

        // "drag to reposition" hint — shown only when a layer is selected
        if (canDrag)
          Positioned(
            bottom: 12,
            child: _DragHint(isDark: isDark),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive LED canvas — handles pan gestures and converts them to matrix
// pixel offsets, then notifies the parent to persist the updated layer offset.
//
// Coordinate mapping:
//   screen px → matrix px:  matX = screenX / canvasW × 64
//                            matY = screenY / canvasH × 32
//
// The layer offset is in matrix pixels and is relative to each widget's
// default (usually centred) position. Dragging 1 matrix pixel in any direction
// moves the rendered element 1 pixel on the 64×32 grid.
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
  bool    _isDragging    = false;
  bool    _didSnapshot   = false;

  bool get _canDrag => widget.selectedLayer != null;

  /// Convert a local screen-space position to matrix-space (0..64, 0..32).
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
    if (!_canDrag || _dragStartMatrix == null || _dragStartLayerOffset == null) return;

    // Snapshot on the first movement so undo captures the pre-drag state.
    if (!_didSnapshot) {
      widget.onDragStart();
      _didSnapshot = true;
    }

    final currentMatrix = _toMatrix(details.localPosition, canvasSize);
    final delta         = currentMatrix - _dragStartMatrix!;

    widget.onOffsetChanged(
      Offset(
        _dragStartLayerOffset!.dx + delta.dx,
        _dragStartLayerOffset!.dy + delta.dy,
      ),
    );
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
          cursor: _canDrag
              ? (_isDragging
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab)
              : MouseCursor.defer,
          child: GestureDetector(
            onPanStart:  (d) => _onPanStart(d, size),
            onPanUpdate: (d) => _onPanUpdate(d, size),
            onPanEnd:    _onPanEnd,
            child: Stack(
              children: [
                // LED pixel grid
                _LedCanvas(buffer: widget.buffer),

                // Selection border — indicates the layer is draggable
                if (_canDrag)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(kRadiusSm),
                          border: Border.all(
                            color: kGreen.withOpacity(_isDragging ? 0.9 : 0.35),
                            width: _isDragging ? 1.5 : 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Crosshair indicator during active drag
                if (_isDragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CrosshairPainter(),
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
// Crosshair painter — drawn over the canvas during a drag to help the user
// align content to the matrix centre.
// ─────────────────────────────────────────────────────────────────────────────

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = kGreen.withOpacity(0.18)
      ..strokeWidth = 0.5
      ..style       = PaintingStyle.stroke;

    // Vertical centre line
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    // Horizontal centre line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CrosshairPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag hint chip — shown below the canvas when a layer is selected
// ─────────────────────────────────────────────────────────────────────────────

class _DragHint extends StatelessWidget {
  final bool isDark;
  const _DragHint({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF242424).withOpacity(0.85)
              : const Color(0xFFF8F7F3).withOpacity(0.85),
          borderRadius: const BorderRadius.all(kRadiusSm),
          border: Border.all(
            color: kGreen.withOpacity(0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_with_rounded,
              size: 10,
              color: kGreen.withOpacity(0.75),
            ),
            const SizedBox(width: 5),
            Text(
              'drag on preview to reposition',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: kGreen.withOpacity(0.75),
                letterSpacing: 0.04,
              ),
            ),
          ],
        ),
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
// Each pixel is checked per-channel so dim blues and greens render correctly.
// ─────────────────────────────────────────────────────────────────────────────

class _LedPainter extends CustomPainter {
  final PixelBuffer buffer;

  static const int _cols = 64;
  static const int _rows = 32;

  const _LedPainter({required this.buffer});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0A0A));

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
// Info strip — shows matrix dimensions and export stats
// ─────────────────────────────────────────────────────────────────────────────

class _InfoStrip extends StatelessWidget {
  final int   width, height;
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