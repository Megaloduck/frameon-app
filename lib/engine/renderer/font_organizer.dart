import 'dart:ui';

import 'pixel_buffer.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Font Organizer — bitmap font data + renderer for 64×32 LED matrix panels
// ═══════════════════════════════════════════════════════════════════════════
//
//  7 fonts, all 7 rows tall (charHeight = 7) to fit a 32-row panel.
//
//  Glyph format
//  ────────────
//  Each glyph stores rows as a List<int> of row bitmasks.
//    rows[0] = top row, rows[6] = bottom row.
//    MSB (leftmost bit) = leftmost pixel.
//    glyph.width = how many bits (columns) are meaningful per row.
//
//  Spacing rules
//  ─────────────
//    Letter gap  : 1 px  (_kCharGap, added after every glyph)
//    Word gap    : 4 px total = space glyph width(3) + 1 px letter gap
//                  → every font's space glyph must be width 3.
//
//  Usage
//  ─────
//    final font = LedFontLibrary.get(LedFontId.polymorph);
//    font.draw(buffer: buf, text: 'HI', color: Color(0xFF21C32C), x: 0, y: 12);
//    final w = font.textWidth('HI');
//    final cx = font.centeredX('HI');           // x offset for 64-wide panel
//
// ═══════════════════════════════════════════════════════════════════════════

part 'fonts/polymorph_font.dart';
part 'fonts/brickwork_font.dart';
part 'fonts/waterfox_font.dart';
part 'fonts/vandalism_font.dart';
part 'fonts/destroked_font.dart';
part 'fonts/stereotype_font.dart';
part 'fonts/phantasm_font.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal glyph record
// ─────────────────────────────────────────────────────────────────────────────

/// Raw bitmap data for a single glyph.
class _GlyphData {
  /// Pixel width of this glyph (number of meaningful bits per row).
  final int width;

  /// Row bitmasks. rows[0] = top row. MSB = leftmost pixel.
  final List<int> rows;

  const _GlyphData({required this.width, required this.rows});
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Identifier for each available LED font.
enum LedFontId {
  polymorph,
  brickwork,
  waterfox,
  vandalism,
  destroked,
  stereotype,
  phantasm,
}

/// A single LED bitmap font — glyph data + layout helpers + renderer.
class LedFont {
  final LedFontId id;
  final String    name;

  /// Height of every glyph in rows (always 7).
  final int charHeight;

  /// Gap added after every glyph in pixels (always 1).
  final int charGap;

  /// charHeight + charGap — vertical stride per text line.
  final int lineHeight;

  final Map<String, _GlyphData> _glyphs;

  const LedFont._({
    required this.id,
    required this.name,
    required this.charHeight,
    required this.charGap,
    required this.lineHeight,
    required Map<String, _GlyphData> glyphs,
  }) : _glyphs = glyphs;

  // ── Glyph lookup ──────────────────────────────────────────────────────────

  /// Returns the glyph for [char], falling back to space if unknown.
  _GlyphData glyphFor(String char) => _glyphs[char] ?? _glyphs[' ']!;

  // ── Measurement ───────────────────────────────────────────────────────────

  /// Total pixel width of [text] including 1 px inter-character gaps.
  /// Trailing gap after the last glyph is NOT included.
  int textWidth(String text) {
    if (text.isEmpty) return 0;
    int w = 0;
    for (int i = 0; i < text.length; i++) {
      w += glyphFor(text[i]).width;
      if (i < text.length - 1) w += charGap;
    }
    return w;
  }

  /// X offset to horizontally centre [text] in a panel of [panelWidth] pixels.
  int centeredX(String text, {int panelWidth = 64}) =>
      ((panelWidth - textWidth(text)) / 2).round().clamp(0, panelWidth - 1);

  // ── Rendering ─────────────────────────────────────────────────────────────

  /// Draw [text] into [buffer] with top-left at ([x], [y]).
  void draw({
    required PixelBuffer buffer,
    required String text,
    required Color color,
    required int x,
    required int y,
    double opacity = 1.0,
  }) {
    final int argb = _applyOpacity(color, opacity);
    int cx = x;
    for (int ci = 0; ci < text.length; ci++) {
      final glyph = glyphFor(text[ci]);
      _drawGlyph(buffer, glyph, cx, y, argb);
      cx += glyph.width + charGap;
    }
  }

  /// Draw [text] centred horizontally in [buffer].
  void drawCentered({
    required PixelBuffer buffer,
    required String text,
    required Color color,
    required int bufferWidth,
    required int y,
    double opacity = 1.0,
  }) {
    draw(
      buffer: buffer,
      text: text,
      color: color,
      x: (bufferWidth - textWidth(text)) ~/ 2,
      y: y,
      opacity: opacity,
    );
  }

  /// Draw [text] right-aligned so its last pixel lands at [rightEdge] - 1.
  void drawRight({
    required PixelBuffer buffer,
    required String text,
    required Color color,
    required int rightEdge,
    required int y,
    double opacity = 1.0,
  }) {
    draw(
      buffer: buffer,
      text: text,
      color: color,
      x: rightEdge - textWidth(text),
      y: y,
      opacity: opacity,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _drawGlyph(PixelBuffer buffer, _GlyphData glyph, int x, int y, int argb) {
    final int w = glyph.width;
    for (int row = 0; row < glyph.rows.length; row++) {
      final int bits = glyph.rows[row];
      for (int col = 0; col < w; col++) {
        // MSB = leftmost pixel, so test bit (w-1-col)
        if ((bits >> (w - 1 - col)) & 1 == 1) {
          buffer.setPixel(x + col, y + row, argb);
        }
      }
    }
  }
  /// Draw [text] into [buffer] with each source pixel expanded to a
  /// [scale]×[scale] block, starting at ([x], [y]).
  ///
  /// Used by the Double Pixel rendering mode (scale = 2).
  /// Glyph advance = (glyph.width + charGap) * scale, keeping proportions
  /// identical to [draw] but at double (or any integer) resolution.
  void drawScaled({
    required PixelBuffer buffer,
    required String text,
    required Color color,
    required int x,
    required int y,
    required int scale,
    double opacity = 1.0,
  }) {
    assert(scale >= 1, 'scale must be ≥ 1');
    if (scale == 1) {
      draw(buffer: buffer, text: text, color: color, x: x, y: y, opacity: opacity);
      return;
    }
    final int argb = _applyOpacity(color, opacity);
    int cx = x;
    for (int ci = 0; ci < text.length; ci++) {
      final glyph = glyphFor(text[ci]);
      _drawGlyphScaled(buffer, glyph, cx, y, argb, scale);
      cx += (glyph.width + charGap) * scale;
    }
  }

  void _drawGlyphScaled(
      PixelBuffer buffer, _GlyphData glyph, int x, int y, int argb, int scale) {
    final int w = glyph.width;
    for (int row = 0; row < glyph.rows.length; row++) {
      final int bits = glyph.rows[row];
      for (int col = 0; col < w; col++) {
        if ((bits >> (w - 1 - col)) & 1 == 1) {
          // Expand each source pixel to a scale×scale block.
          for (int sy = 0; sy < scale; sy++) {
            for (int sx = 0; sx < scale; sx++) {
              buffer.setPixel(x + col * scale + sx, y + row * scale + sy, argb);
            }
          }
        }
      }
    }
  }

  static int _applyOpacity(Color color, double opacity) {
    if (opacity >= 1.0) return color.value;
    final int a = (((color.value >> 24) & 0xFF) * opacity).round();
    return (color.value & 0x00FFFFFF) | (a << 24);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library registry
// ─────────────────────────────────────────────────────────────────────────────

/// Registry of all available LED fonts.
class LedFontLibrary {
  LedFontLibrary._();

  static const List<LedFont> all = [
    LedFont._(
      id:         LedFontId.polymorph,
      name:       'Polymorph',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _polymorphGlyphs,
    ),
    LedFont._(
      id:         LedFontId.brickwork,
      name:       'Brickwork',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _brickworkGlyphs,
    ),
    LedFont._(
      id:         LedFontId.waterfox,
      name:       'Waterfox',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _waterfoxGlyphs,
    ),
    LedFont._(
      id:         LedFontId.vandalism,
      name:       'Vandalism',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _vandalismGlyphs,
    ),
    LedFont._(
      id:         LedFontId.destroked,
      name:       'Destroked',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _destrokedGlyphs,
    ),
    LedFont._(
      id:         LedFontId.stereotype,
      name:       'Stereotype',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _stereotypeGlyphs,
    ),
    LedFont._(
      id:         LedFontId.phantasm,
      name:       'Phantasm',
      charHeight: 7,
      charGap:    1,
      lineHeight: 8,
      glyphs:     _phantasmGlyphs,
    ),
  ];

  static final Map<LedFontId, LedFont> _byId = {
    for (final f in all) f.id: f,
  };

  /// Look up a font by its [LedFontId].
  static LedFont get(LedFontId id) => _byId[id]!;

  /// All font IDs, in library order.
  static List<LedFontId> get ids => all.map((f) => f.id).toList();
}