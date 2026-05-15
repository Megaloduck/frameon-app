import 'dart:math' as math;
import 'dart:ui';

import '../renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import '../../services/finance/finance_service.dart';
import 'matrix_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FinanceWidget
//
// Renders a FinanceLayer with three possible layouts on a 64×32 panel:
//
//   priceAndGraph (default)
//     Row  0–6  : "BTC 67500"   (label + price, polymorph font)
//     Row  7    : blank separator
//     Row  8–31 : sparkline (24 px tall) using 24h-direction color
//
//   priceOnly
//     Symbol on top row, large centered price below.
//
//   graphOnly
//     Sparkline fills the full 32-row panel.
//
// All rendering is "baked" into the buffer — no firmware-side overdraw is
// required, so this works exactly like the GIF/Text widgets.
// ─────────────────────────────────────────────────────────────────────────────

class FinanceWidget extends MatrixWidget<FinanceLayer> {
  const FinanceWidget();

  /// Render with live data. [data] may be null — we'll show a placeholder.
  void renderWithData(
    FinanceLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    FinanceData? data,
  ) {
    buffer.clear();
    final font = LedFontLibrary.get(layer.fontId);

    if (data == null || !data.hasData) {
      _drawPlaceholder(buffer, font, layer);
      return;
    }

    switch (layer.layout) {
      case FinanceLayout.priceAndGraph:
        _renderPriceAndGraph(buffer, font, layer, data);
      case FinanceLayout.priceOnly:
        _renderPriceOnly(buffer, font, layer, data);
      case FinanceLayout.graphOnly:
        _renderGraphOnly(buffer, layer, data);
    }
  }

  @override
  void render(FinanceLayer layer, PixelBuffer buffer, int elapsedMs) {
    // No-op without data — MatrixRenderer calls renderWithData().
    _drawPlaceholder(
      buffer,
      LedFontLibrary.get(layer.fontId),
      layer,
    );
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  void _renderPriceAndGraph(
    PixelBuffer buf, LedFont font, FinanceLayer layer, FinanceData data) {
    final dxOff = layer.offset.dx.round();
    final dyOff = layer.offset.dy.round();

   final symbolStr = layer.showSymbol ? data.ticker.toUpperCase() : '';
    final priceStr  = _formatPrice(data.price, layer.decimals);

    // Row 0–6: header row.
    int x = dxOff;
    if (symbolStr.isNotEmpty) {
      font.draw(
        buffer:  buf,
        text:    symbolStr,
        color:   layer.symbolColor,
        x:       x,
        y:       dyOff,
        opacity: layer.opacity,
      );
      x += font.textWidth(symbolStr) + 2;
    }
    // Right-align price to the panel edge.
    final priceW = font.textWidth(priceStr);
    final priceX = math.max(x, buf.width - priceW + dxOff);
    font.draw(
      buffer:  buf,
      text:    priceStr,
      color:   data.isUp ? layer.upColor : layer.downColor,
      x:       priceX,
      y:       dyOff,
      opacity: layer.opacity,
    );

    // Row 8–31: sparkline.
    _drawSparkline(
      buf,
      data.sparkline,
      data.isUp ? layer.upColor : layer.downColor,
      top:    8 + dyOff,
      bottom: buf.height - 1 + dyOff,
      left:   0 + dxOff,
      right:  buf.width - 1 + dxOff,
      opacity: layer.opacity,
    );
  }

  void _renderPriceOnly(
    PixelBuffer buf, LedFont font, FinanceLayer layer, FinanceData data) {
    final dxOff = layer.offset.dx.round();
    final dyOff = layer.offset.dy.round();

    final symbolStr = layer.showSymbol ? data.ticker.toUpperCase() : '';
    final priceStr  = _formatPrice(data.price, layer.decimals);
    final changeStr = layer.showChangePercent
        ? '${data.isUp ? '+' : ''}${data.change24hPct.toStringAsFixed(1)}%'
        : '';

    // Center vertically: each row is 7 px tall.
    final rows = <(String, Color)>[
      if (symbolStr.isNotEmpty) (symbolStr, layer.symbolColor),
      (priceStr, data.isUp ? layer.upColor : layer.downColor),
      if (changeStr.isNotEmpty)
        (changeStr, data.isUp ? layer.upColor : layer.downColor),
    ];
    final totalH = rows.length * 7 + (rows.length - 1) * 2;
    int y = ((buf.height - totalH) ~/ 2) + dyOff;

    for (final (text, color) in rows) {
      final w = font.textWidth(text);
      font.draw(
        buffer:  buf,
        text:    text,
        color:   color,
        x:       ((buf.width - w) ~/ 2) + dxOff,
        y:       y,
        opacity: layer.opacity,
      );
      y += 9;
    }
  }

  void _renderGraphOnly(PixelBuffer buf, FinanceLayer layer, FinanceData data) {
    final dxOff = layer.offset.dx.round();
    final dyOff = layer.offset.dy.round();
    _drawSparkline(
      buf,
      data.sparkline,
      data.isUp ? layer.upColor : layer.downColor,
      top:     0 + dyOff,
      bottom:  buf.height - 1 + dyOff,
      left:    0 + dxOff,
      right:   buf.width - 1 + dxOff,
      opacity: layer.opacity,
    );
  }

  void _drawPlaceholder(PixelBuffer buf, LedFont font, FinanceLayer layer) {
    const msg = '...';
    final w = font.textWidth(msg);
    font.draw(
      buffer: buf,
      text:   msg,
      color:  layer.symbolColor,
      x:      (buf.width - w) ~/ 2,
      y:      (buf.height - font.charHeight) ~/ 2,
    );
  }

  // ── Sparkline ────────────────────────────────────────────────────────────

  /// Draws a sparkline of [pts] inside the rectangle (left,top)-(right,bottom)
  /// using [color]. Resamples [pts] to fit the column count.
  void _drawSparkline(
    PixelBuffer buf,
    List<double> pts,
    Color color, {
    required int top,
    required int bottom,
    required int left,
    required int right,
    double opacity = 1.0,
  }) {
    if (pts.length < 2) return;
    final cols = right - left + 1;
    if (cols < 2) return;

    final rows = bottom - top + 1;
    if (rows < 2) return;

    double minV = pts.first, maxV = pts.first;
    for (final v in pts) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    // Add 5% padding so peaks aren't pinned to the edges.
    final span = (maxV - minV).abs();
    final pad  = span < 1e-9 ? 1.0 : span * 0.05;
    minV -= pad;
    maxV += pad;
    final range = maxV - minV;

    int yFor(double v) {
      if (range <= 0) return ((top + bottom) ~/ 2);
      final norm = (v - minV) / range;
      return (bottom - norm * (rows - 1)).round().clamp(top, bottom);
    }

    int xFor(int i) {
      // Map sample index 0..pts.length-1 to column 0..cols-1.
      return left + ((i * (cols - 1)) ~/ (pts.length - 1));
    }

    final argb = _applyOpacity(color, opacity);

    // Bresenham line from each sample to the next.
    int prevX = xFor(0);
    int prevY = yFor(pts[0]);
    for (int i = 1; i < pts.length; i++) {
      final cx = xFor(i);
      final cy = yFor(pts[i]);
      _line(buf, prevX, prevY, cx, cy, argb);
      prevX = cx;
      prevY = cy;
    }
  }

  // Bresenham's line algorithm.
  void _line(PixelBuffer buf, int x0, int y0, int x1, int y1, int argb) {
    int dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    int x = x0, y = y0;
    while (true) {
      buf.setPixel(x, y, argb);
      if (x == x1 && y == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) { err += dy; x += sx; }
      if (e2 <= dx) { err += dx; y += sy; }
    }
  }

  static int _applyOpacity(Color color, double opacity) {
    if (opacity >= 1.0) return color.value;
    final a = (((color.value >> 24) & 0xFF) * opacity).round();
    return (color.value & 0x00FFFFFF) | (a << 24);
  }

  // ── Formatting ───────────────────────────────────────────────────────────

  /// Compact price formatter that keeps the string short enough for 64 px:
  ///   ≥10000 → no decimals          (e.g. 67500)
  ///   ≥100   → up to 1 decimal      (e.g. 234.5)
  ///   <100   → up to [decimals]     (e.g. 1.23)
  String _formatPrice(double v, int decimals) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100)   return v.toStringAsFixed(decimals.clamp(0, 1));
    return v.toStringAsFixed(decimals.clamp(0, 4));
  }
}