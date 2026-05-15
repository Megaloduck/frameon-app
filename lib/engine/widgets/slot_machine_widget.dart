import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Runtime state — owned by SlotMachineService, read by SlotMachineWidget.
//
// Defined in this file (and not in the service file) so the engine layer
// stays free of service / Riverpod dependencies — same pattern used by
// pomodoro_widget.dart.
// ═════════════════════════════════════════════════════════════════════════════

enum SlotMachinePhase {
  /// No spin in flight. [SlotMachineRuntimeState.symbols] holds the most
  /// recently shown result (or the default starting symbols).
  idle,

  /// A spin is in flight — reels are visually scrolling. The locked-in
  /// result is already decided and stored in `symbols`.
  spinning,

  /// The spin has fully landed. If `isWin`, the frame flashes for
  /// `layer.winFlashDurationMs` ms after `resultRevealedAtEpochMs`.
  showing,
}

class SlotMachineRuntimeState {
  /// Current machine phase.
  final SlotMachinePhase phase;

  /// Indices into the widget's symbol palette. Always length 3.
  final List<int> symbols;

  /// Wall-clock ms (`DateTime.now().millisecondsSinceEpoch`) when the
  /// current/last spin started, or `-1` if the machine has never spun.
  final int spinStartedAtEpochMs;

  /// Wall-clock ms when the most recent spin finished landing. Drives the
  /// win-flash window.
  final int resultRevealedAtEpochMs;

  /// Lifetime spin count (since the last reset).
  final int spinsCount;

  /// Lifetime 3-of-a-kind count (since the last reset).
  final int winsCount;

  /// True when `symbols` is a 3-of-a-kind.
  final bool isWin;

  const SlotMachineRuntimeState({
    required this.phase,
    required this.symbols,
    required this.spinStartedAtEpochMs,
    required this.resultRevealedAtEpochMs,
    required this.spinsCount,
    required this.winsCount,
    required this.isWin,
  });

  /// Fresh machine — no spin yet, default visible symbols.
  static const SlotMachineRuntimeState initial = SlotMachineRuntimeState(
    phase: SlotMachinePhase.idle,
    symbols: <int>[0, 1, 2],
    spinStartedAtEpochMs: -1,
    resultRevealedAtEpochMs: -1,
    spinsCount: 0,
    winsCount: 0,
    isWin: false,
  );

  bool get canSpin =>
      phase == SlotMachinePhase.idle || phase == SlotMachinePhase.showing;

  SlotMachineRuntimeState copyWith({
    SlotMachinePhase? phase,
    List<int>? symbols,
    int? spinStartedAtEpochMs,
    int? resultRevealedAtEpochMs,
    int? spinsCount,
    int? winsCount,
    bool? isWin,
  }) =>
      SlotMachineRuntimeState(
        phase: phase ?? this.phase,
        symbols: symbols ?? this.symbols,
        spinStartedAtEpochMs:
            spinStartedAtEpochMs ?? this.spinStartedAtEpochMs,
        resultRevealedAtEpochMs:
            resultRevealedAtEpochMs ?? this.resultRevealedAtEpochMs,
        spinsCount: spinsCount ?? this.spinsCount,
        winsCount: winsCount ?? this.winsCount,
        isWin: isWin ?? this.isWin,
      );
}

/// Total number of symbols in [SlotMachineWidget]'s palette. Exposed so the
/// service can roll within range without importing widget internals.
const int kSlotMachineSymbolCount = 6;

// ═════════════════════════════════════════════════════════════════════════════
// SlotMachineWidget — renders a *playable* slot machine.
//
// Layout (centred on 64×32, then shifted by layer.offset):
//
//   ┌─────────────────────────────────────┐
//   │ ┌────────┐ ┌────────┐ ┌────────┐    │  ← 14 × 16 reel windows
//   │ │ reel 0 │ │ reel 1 │ │ reel 2 │    │
//   │ └────────┘ └────────┘ └────────┘    │
//   └─────────────────────────────────────┘
//   Total: 46 wide × 18 tall.
//
// Render path:
//   • idle / showing  → static symbols (+ win flash if applicable)
//   • spinning        → reel R is still scrolling while
//                       (now - spinStartedAt) < spinDurationMs + R * stagger
//
// Export bakes a single static frame of the current state (the spinning
// branch is skipped when isExport=true).
// ═════════════════════════════════════════════════════════════════════════════

class SlotMachineWidget extends MatrixWidget<SlotMachineLayer> {
  const SlotMachineWidget();

  // ── Layout constants ────────────────────────────────────────────────────
  static const int kReelCount   = 3;
  static const int kReelWidth   = 14;
  static const int kReelHeight  = 16;
  static const int kSymbolSize  = 10;
  static const int kFramePad    = 1;
  static const int kReelGap     = 1;
  static const int kTotalWidth  =
      kFramePad * 2 + kReelWidth * kReelCount + kReelGap * (kReelCount - 1);
  static const int kTotalHeight = kFramePad * 2 + kReelHeight;
  static const int kSpinStride  = kSymbolSize + 2;

  // ── Symbol palette ──────────────────────────────────────────────────────
  // 10×10 pixel-art icons. 'X' = lit pixel in the symbol's tint, '.' = off.
  static const List<_Symbol> _symbols = <_Symbol>[
    _Symbol('SEVEN', Color(0xFFE63946), <String>[
      '.XXXXXXXX.',
      'XXXXXXXXXX',
      'XX......XX',
      '........X.',
      '.......X..',
      '......XX..',
      '.....XX...',
      '....XX....',
      '...XX.....',
      '...XX.....',
    ]),
    _Symbol('BAR', Color(0xFFEFEFEF), <String>[
      '..........',
      '.XXXXXXXX.',
      'X........X',
      'X.XXXXXX.X',
      'X.XXXXXX.X',
      'X.XXXXXX.X',
      'X.XXXXXX.X',
      'X........X',
      '.XXXXXXXX.',
      '..........',
    ]),
    _Symbol('BELL', Color(0xFFFFC107), <String>[
      '....XX....',
      '...XXXX...',
      '..XXXXXX..',
      '.XXXXXXXX.',
      '.XXXXXXXX.',
      'XXXXXXXXXX',
      'XXXXXXXXXX',
      'XXXXXXXXXX',
      '....XX....',
      '...XXXX...',
    ]),
    _Symbol('CHERRY', Color(0xFFD7263D), <String>[
      '......XX..',
      '.....XX...',
      '....XX....',
      '...XX.XX..',
      '..XX.XXXX.',
      '.XXXXXXXXX',
      'XX.XXX.XXX',
      'XXXXXXXXXX',
      '.XXXXXXXX.',
      '..XXXXXX..',
    ]),
    _Symbol('LEMON', Color(0xFFFFE066), <String>[
      '..XX..XX..',
      '.XXXXXXXX.',
      'XXXXXXXXXX',
      'XX.XXXX.XX',
      'XXXXXXXXXX',
      'XXXXXXXXXX',
      'XX.XXXX.XX',
      'XXXXXXXXXX',
      '.XXXXXXXX.',
      '..XXXXXX..',
    ]),
    _Symbol('DIAMOND', Color(0xFF4DD0E1), <String>[
      '....XX....',
      '...XXXX...',
      '..XXXXXX..',
      '.XXXXXXXX.',
      'XXXXXXXXXX',
      'XXXXXXXXXX',
      '.XXXXXXXX.',
      '..XXXXXX..',
      '...XXXX...',
      '....XX....',
    ]),
  ];

  // ── Render entry points ─────────────────────────────────────────────────

  /// Stateless render — only used when the service hasn't published a state
  /// yet (effectively just the brief moment between app start and the first
  /// listener tick). Falls back to the initial state.
  @override
  void render(SlotMachineLayer layer, PixelBuffer buffer, int elapsedMs) {
    renderWithState(layer, buffer, elapsedMs, SlotMachineRuntimeState.initial);
  }

  /// State-driven render — the real path used in live preview and export.
  void renderWithState(
    SlotMachineLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SlotMachineRuntimeState state, {
    bool isExport = false,
  }) {
    buffer.clear();

    final int ox = layer.offset.dx.round();
    final int oy = layer.offset.dy.round();
    final int x0 = ((buffer.width  - kTotalWidth)  ~/ 2) + ox;
    final int y0 = ((buffer.height - kTotalHeight) ~/ 2) + oy;

    // Frame.
    if (layer.showFrame) {
      _drawFrame(buffer, x0, y0, layer.frameColor);
    }

    // Export and non-spinning phases share the same static-symbol render.
    final bool spinning =
        !isExport && state.phase == SlotMachinePhase.spinning;

    if (!spinning) {
      _drawStaticResult(buffer, x0, y0, state.symbols);

      // Win flash — only during `showing`, only inside the flash window.
      if (state.phase == SlotMachinePhase.showing &&
          state.isWin &&
          layer.showFrame &&
          state.resultRevealedAtEpochMs > 0) {
        final int sinceReveal =
            DateTime.now().millisecondsSinceEpoch -
                state.resultRevealedAtEpochMs;
        if (sinceReveal >= 0 && sinceReveal < layer.winFlashDurationMs) {
          final bool flashOn = (sinceReveal ~/ 160) % 2 == 0;
          if (flashOn) {
            _drawFrame(buffer, x0, y0, layer.winFlashColor);
          }
        }
      }
      return;
    }

    // ── Spinning ──────────────────────────────────────────────────────────
    // Reel R locks in at `spinDurationMs + R * stagger` ms after the spin
    // started — first reel first, then a staggered cascade.
    final int sinceSpin =
        DateTime.now().millisecondsSinceEpoch - state.spinStartedAtEpochMs;

    for (int r = 0; r < kReelCount; r++) {
      final int rx = x0 + kFramePad + r * (kReelWidth + kReelGap);
      final int ry = y0 + kFramePad;
      final int stopAt =
          layer.spinDurationMs + r * layer.reelStopStaggerMs;

      if (sinceSpin >= stopAt) {
        _drawStaticSymbol(buffer, rx, ry, state.symbols[r]);
      } else {
        _drawSpinningReel(
          buffer, rx, ry,
          elapsedMs, layer.spinSpeedMs,
          seed: r * 1009,
        );
      }
    }
  }

  // ── Drawing primitives ──────────────────────────────────────────────────

  void _drawStaticResult(PixelBuffer buf, int x0, int y0, List<int> symbols) {
    for (int r = 0; r < kReelCount; r++) {
      final int rx = x0 + kFramePad + r * (kReelWidth + kReelGap);
      final int ry = y0 + kFramePad;
      _drawStaticSymbol(buf, rx, ry, symbols[r]);
    }
  }

  /// Outer frame plus inter-reel vertical dividers.
  void _drawFrame(PixelBuffer buf, int x0, int y0, Color color) {
    final int argb = color.value;

    for (int x = 0; x < kTotalWidth; x++) {
      buf.setPixel(x0 + x, y0,                       argb);
      buf.setPixel(x0 + x, y0 + kTotalHeight - 1,    argb);
    }
    for (int y = 0; y < kTotalHeight; y++) {
      buf.setPixel(x0,                       y0 + y, argb);
      buf.setPixel(x0 + kTotalWidth - 1,     y0 + y, argb);
    }
    for (int r = 1; r < kReelCount; r++) {
      final int dx = x0 + kFramePad + r * kReelWidth + (r - 1) * kReelGap;
      for (int y = 1; y < kTotalHeight - 1; y++) {
        buf.setPixel(dx, y0 + y, argb);
      }
    }
  }

  /// A single 10×10 symbol centred inside a 14×16 reel window at (rx, ry).
  void _drawStaticSymbol(PixelBuffer buf, int rx, int ry, int symIdx) {
    final _Symbol sym = _symbols[symIdx];
    final int sx = rx + (kReelWidth  - kSymbolSize) ~/ 2;
    final int sy = ry + (kReelHeight - kSymbolSize) ~/ 2;
    final int argb = sym.color.value;

    for (int y = 0; y < kSymbolSize; y++) {
      final String row = sym.bitmap[y];
      for (int x = 0; x < kSymbolSize; x++) {
        if (row.codeUnitAt(x) == _kCharX) {
          buf.setPixel(sx + x, sy + y, argb);
        }
      }
    }
  }

  /// Vertically scrolling reel inside a 14×16 window. Each reel uses a
  /// distinct phase offset (`seed`) so the three reels look uncorrelated.
  void _drawSpinningReel(
    PixelBuffer buf,
    int rx,
    int ry,
    int elapsedMs,
    int speedMs, {
    required int seed,
  }) {
    final int n      = _symbols.length;
    final int stride = kSpinStride;
    final int loop   = n * stride;

    final int totalOffset =
        (elapsedMs * stride) ~/ speedMs.clamp(1, 1000);
    final int o = ((totalOffset + seed) % loop + loop) % loop;

    final int sxOffset = (kReelWidth - kSymbolSize) ~/ 2;

    for (int y = 0; y < kReelHeight; y++) {
      final int stripY = (y + o) % loop;
      final int yIn    = stripY % stride;
      if (yIn >= kSymbolSize) continue;

      final _Symbol sym = _symbols[(stripY ~/ stride) % n];
      final int argb = sym.color.value;
      final String row = sym.bitmap[yIn];
      for (int x = 0; x < kSymbolSize; x++) {
        if (row.codeUnitAt(x) == _kCharX) {
          buf.setPixel(rx + sxOffset + x, ry + y, argb);
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────────────

const int _kCharX = 0x58; // 'X'.codeUnitAt(0)

class _Symbol {
  final String name;
  final Color color;
  final List<String> bitmap;
  const _Symbol(this.name, this.color, this.bitmap);
}