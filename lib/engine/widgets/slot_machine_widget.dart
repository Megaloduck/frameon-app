import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SlotMachineWidget
// ─────────────────────────────────────────────────────────────────────────────
//
// Renders a 3-reel slot-machine simulation into a [PixelBuffer].
//
// Layout (centred on 64×32, then shifted by layer.offset):
//
//   ┌─────────────────────────────────────┐  ← y0 (top frame, 1 px)
//   │ ┌────────┐ ┌────────┐ ┌────────┐    │
//   │ │ reel 0 │ │ reel 1 │ │ reel 2 │    │  ← 16-px reel window
//   │ └────────┘ └────────┘ └────────┘    │
//   └─────────────────────────────────────┘  ← y0 + 17 (bottom frame, 1 px)
//      14 wide    14 wide    14 wide
//        ↑ 1 px reel divider between reels
//
//   Total: 46 wide × 18 tall.
//
// Cycle (driven entirely by elapsedMs, so the baked loop is deterministic):
//
//   PHASE 0  IDLE         — all reels static, showing this cycle's result.
//   PHASE 1  SPIN_ALL     — all three reels scrolling.
//   PHASE 2  STOP_R1      — reel 0 locks in, reels 1+2 still spinning.
//   PHASE 3  STOP_R2      — reels 0+1 locked, reel 2 still spinning.
//   PHASE 4  SHOW_RESULT  — all locked, frame flashes if 3-of-a-kind.
//
// Per-cycle results are derived from a deterministic hash of the cycle index,
// so the same elapsedMs always produces the same frame — required for the
// frame-baking export pipeline to produce a clean N-frame loop.
// ─────────────────────────────────────────────────────────────────────────────

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
  static const int kSpinStride  = kSymbolSize + 2; // vertical spacing per symbol on a spinning reel

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

  // ── Phase durations (cycle = sum of all five) ───────────────────────────

  int _phaseDuration(SlotMachineLayer layer, int phase) {
    switch (phase) {
      case 0: return layer.idleMs;
      case 1: return layer.spinDurationMs;
      case 2: return layer.reelStopStaggerMs;
      case 3: return layer.reelStopStaggerMs;
      case 4: return layer.resultHoldMs;
      default: return 0;
    }
  }

  int _totalCycleMs(SlotMachineLayer layer) =>
      layer.idleMs +
      layer.spinDurationMs +
      2 * layer.reelStopStaggerMs +
      layer.resultHoldMs;

  // ── Deterministic per-cycle result ──────────────────────────────────────

  /// 32-bit xorshift-style integer hash. Output is non-negative.
  int _hash(int x) {
    x = (x ^ (x >> 16)) & 0xFFFFFFFF;
    x = (x * 0x85ebca6b) & 0xFFFFFFFF;
    x = (x ^ (x >> 13)) & 0xFFFFFFFF;
    x = (x * 0xc2b2ae35) & 0xFFFFFFFF;
    x = (x ^ (x >> 16)) & 0xFFFFFFFF;
    return x;
  }

  /// Decide which symbol reel [reelIdx] lands on for cycle [cycle].
  ///
  /// Roughly one in [winOdds] cycles is a 3-of-a-kind jackpot. The chosen
  /// jackpot symbol is itself randomised per cycle so the win isn't always
  /// the same icon.
  int _resultSymbol(int cycle, int reelIdx, int winOdds) {
    final int h = _hash(cycle * 2654435761);
    if (winOdds > 0 && h % winOdds == 0) {
      // Jackpot — all reels land on the same symbol.
      return _hash(cycle * 31 + 17) % _symbols.length;
    }
    return _hash(cycle * 7919 + reelIdx * 131) % _symbols.length;
  }

  // ── Entry point ─────────────────────────────────────────────────────────

  @override
  void render(SlotMachineLayer layer, PixelBuffer buffer, int elapsedMs) {
    buffer.clear();

    final int ox = layer.offset.dx.round();
    final int oy = layer.offset.dy.round();

    // Centre the slot machine on the canvas, then apply the drag offset.
    final int x0 = ((buffer.width  - kTotalWidth)  ~/ 2) + ox;
    final int y0 = ((buffer.height - kTotalHeight) ~/ 2) + oy;

    // Resolve which phase we're in within the current cycle.
    final int cycleMs = _totalCycleMs(layer);
    if (cycleMs <= 0) return; // Defensive: silly config, just bail.

    final int cycle      = elapsedMs ~/ cycleMs;
    int       phaseT     = elapsedMs - cycle * cycleMs;
    int       phase      = 0;
    int       phaseDur   = _phaseDuration(layer, 0);
    while (phaseT >= phaseDur && phase < 4) {
      phaseT  -= phaseDur;
      phase   += 1;
      phaseDur = _phaseDuration(layer, phase);
    }

    // Symbols this cycle will reveal.
    final List<int> finalSymbols = List<int>.generate(
      kReelCount,
      (i) => _resultSymbol(cycle, i, layer.winOddsDenominator),
    );
    final bool isWin = finalSymbols[0] == finalSymbols[1] &&
                       finalSymbols[1] == finalSymbols[2];

    // ── Frame ─────────────────────────────────────────────────────────────
    if (layer.showFrame) {
      _drawFrame(buffer, x0, y0, layer.frameColor);
    }

    // ── Reels ─────────────────────────────────────────────────────────────
    for (int r = 0; r < kReelCount; r++) {
      final int rx = x0 + kFramePad + r * (kReelWidth + kReelGap);
      final int ry = y0 + kFramePad;

      if (_isSpinning(phase, r)) {
        _drawSpinningReel(buffer, rx, ry, elapsedMs, layer.spinSpeedMs,
            seed: r * 1009 + cycle);
      } else {
        _drawStaticSymbol(buffer, rx, ry, finalSymbols[r]);
      }
    }

    // ── Win flash on the frame during SHOW_RESULT ─────────────────────────
    if (phase == 4 && isWin && layer.showFrame) {
      // Flash 3× per second.
      final bool flashOn = (phaseT ~/ 160) % 2 == 0;
      if (flashOn) {
        _drawFrame(buffer, x0, y0, layer.winFlashColor);
      }
    }
  }

  // ── Reel state ──────────────────────────────────────────────────────────

  bool _isSpinning(int phase, int reelIdx) {
    switch (phase) {
      case 0: return false;          // IDLE
      case 1: return true;           // SPIN_ALL
      case 2: return reelIdx >= 1;   // STOP_R1 — reels 1, 2 still spinning
      case 3: return reelIdx >= 2;   // STOP_R2 — only reel 2 still spinning
      case 4: return false;          // SHOW_RESULT
    }
    return false;
  }

  // ── Drawing primitives ──────────────────────────────────────────────────

  /// Draw the outer frame plus inter-reel vertical dividers.
  void _drawFrame(PixelBuffer buf, int x0, int y0, Color color) {
    final int argb = color.value;

    // Top + bottom edges.
    for (int x = 0; x < kTotalWidth; x++) {
      buf.setPixel(x0 + x, y0,                       argb);
      buf.setPixel(x0 + x, y0 + kTotalHeight - 1,    argb);
    }
    // Left + right edges.
    for (int y = 0; y < kTotalHeight; y++) {
      buf.setPixel(x0,                       y0 + y, argb);
      buf.setPixel(x0 + kTotalWidth - 1,     y0 + y, argb);
    }
    // Reel dividers (1 px columns between adjacent reels).
    for (int r = 1; r < kReelCount; r++) {
      final int dx = x0 + kFramePad + r * kReelWidth + (r - 1) * kReelGap;
      for (int y = 1; y < kTotalHeight - 1; y++) {
        buf.setPixel(dx, y0 + y, argb);
      }
    }
  }

  /// Draw a single 10×10 symbol centred inside a 14×16 reel window
  /// whose top-left corner is at (rx, ry).
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

  /// Draw a vertically-scrolling reel inside a 14×16 window. Symbols loop
  /// through the entire palette in a fixed (reel-specific) order so each
  /// reel appears uncorrelated with the others.
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

    // Pixels travelled by this reel so far.
    final int totalOffset = (elapsedMs * stride) ~/ speedMs.clamp(1, 1000);
    final int o = ((totalOffset + seed) % loop + loop) % loop;

    // For each pixel row visible in the reel window, work out which symbol
    // and which row of that symbol we are looking at.
    final int sxOffset = (kReelWidth - kSymbolSize) ~/ 2;

    for (int y = 0; y < kReelHeight; y++) {
      final int stripY = (y + o) % loop;
      final int yIn    = stripY % stride;
      if (yIn >= kSymbolSize) continue; // 2-px gap between consecutive symbols

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

const int _kCharX = 0x58; // 'X'.codeUnitAt(0) — cached to avoid per-pixel work.

class _Symbol {
  final String name;
  final Color color;
  final List<String> bitmap;
  const _Symbol(this.name, this.color, this.bitmap);
}