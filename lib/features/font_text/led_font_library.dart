// ═══════════════════════════════════════════════════════════════════════════
//  LED Font Library — bitmap_font_data for 64×32 LED matrix panels
// ═══════════════════════════════════════════════════════════════════════════
//
//  9 fonts, all extracted from .ttf/.otf files at the optimal point size
//  to achieve the best cap height fit for a 32-row panel.
//
//  Each font stores every printable ASCII character (32–126) as a list of
//  row bitmasks:  rows[0] = top row,  MSB = leftmost pixel.
//
//  Usage:
//    final font   = LedFontLibrary.get(LedFontId.matrixtype);
//    final glyph  = font.glyphFor('A');
//    final width  = font.textWidth('Hello');
//    final startX = font.centeredX('Hello');
//
// ═══════════════════════════════════════════════════════════════════════════

part 'fonts/font_matrixtype.dart';
part 'fonts/font_minecraftia.dart';
part 'fonts/font_pixelero.dart';
part 'fonts/font_monodrawn.dart';
part 'fonts/font_psygen.dart';
part 'fonts/font_pixelquest.dart';
part 'fonts/font_groutpix.dart';
part 'fonts/font_pixerator.dart';
part 'fonts/font_rainyhearts.dart';

/// Raw bitmap data for a single glyph.
class _GlyphData {
  /// Pixel width of this glyph.
  final int width;

  /// Bitmask per row. rows[0] = top row. MSB = leftmost pixel.
  final List<int> rows;

  const _GlyphData({required this.width, required this.rows});
}

/// Identifier for each available LED font.
enum LedFontId {
  /// Classic 5×7 dot-matrix. Clean, tight, authentic scoreboard feel.
  matrixtype,
  /// Minecraft-style pixel font. Chunky, bold, very readable.
  minecraftia,
  /// Smooth pixel serif. Elegant proportions for display text.
  pixelero,
  /// Hand-drawn monospace. Friendly, casual vibe.
  monodrawn,
  /// Geometric sci-fi. Angular, futuristic lettering.
  psygen,
  /// RPG adventure pixel font. Bold and characterful.
  pixelquest,
  /// Wide bitmap font. 8px cap — fits fewer chars per row, very legible.
  groutpix,
  /// Tall pixel font. 8px cap — strong presence on the matrix.
  pixerator,
  /// Decorative pixel font. 8px cap — playful, expressive style.
  rainyhearts,
}

/// A single LED bitmap font with layout helpers.
class LedFont {
  final LedFontId id;
  final String    name;
  final String    description;

  /// Height of capital letters in pixels.
  final int charHeight;

  /// Gap between glyphs in pixels (always 1).
  final int charGap;

  /// charHeight + charGap — vertical stride per text line.
  final int lineHeight;

  /// How many lines of this font fit in a 32-row panel.
  final int maxLines;

  /// Y coordinate of the top pixel for each line in a 32-row panel.
  final List<int> rowY;

  final Map<String, _GlyphData> _glyphs;

  const LedFont._({
    required this.id,
    required this.name,
    required this.description,
    required this.charHeight,
    required this.charGap,
    required this.lineHeight,
    required this.maxLines,
    required this.rowY,
    required Map<String, _GlyphData> glyphs,
  }) : _glyphs = glyphs;

  /// Returns the glyph for [char], falling back to space.
  _GlyphData glyphFor(String char) => _glyphs[char] ?? _glyphs[' ']!;

  /// Total pixel width of [text] including inter-character gaps.
  int textWidth(String text) {
    if (text.isEmpty) return 0;
    int w = 0;
    for (int i = 0; i < text.length; i++) {
      w += glyphFor(text[i]).width;
      if (i < text.length - 1) w += charGap;
    }
    return w;
  }

  /// X offset to horizontally center [text] in [panelWidth] pixels.
  int centeredX(String text, {int panelWidth = 64}) =>
      ((panelWidth - textWidth(text)) / 2).round().clamp(0, panelWidth - 1);
}

/// Registry of all available LED fonts.
///
/// Example:
/// ```dart
/// final font = LedFontLibrary.get(LedFontId.minecraftia);
/// final bytes = renderBitmapText(font, lines: [
///   BitmapLine(text: 'HELLO', rowSlot: 0, color: Color(0xFF00FF41)),
/// ]);
/// ```
class LedFontLibrary {
  LedFontLibrary._();

  static const List<LedFont> all = [
    LedFont._(
      id:          LedFontId.matrixtype,
      name:        'matrixtype',
      description: 'Classic 5×7 dot-matrix. Clean, tight, authentic scoreboard feel.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 9, 17, 25],
      glyphs:      _matrixtypeGlyphs,
    ),
    LedFont._(
      id:          LedFontId.minecraftia,
      name:        'minecraftia',
      description: 'Minecraft-style pixel font. Chunky, bold, very readable.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 9, 17, 25],
      glyphs:      _minecraftiaGlyphs,
    ),
    LedFont._(
      id:          LedFontId.pixelero,
      name:        'pixelero',
      description: 'Smooth pixel serif. Elegant proportions for display text.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 9, 17, 25],
      glyphs:      _pixeleroGlyphs,
    ),
    LedFont._(
      id:          LedFontId.monodrawn,
      name:        'monodrawn',
      description: 'Hand-drawn monospace. Friendly, casual vibe.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 9, 17, 25],
      glyphs:      _monodrawnGlyphs,
    ),
    LedFont._(
      id:          LedFontId.psygen,
      name:        'psygen',
      description: 'Geometric sci-fi. Angular, futuristic lettering.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 9, 17, 25],
      glyphs:      _psygenGlyphs,
    ),
    LedFont._(
      id:          LedFontId.pixelquest,
      name:        'pixelquest',
      description: 'RPG adventure pixel font. Bold and characterful.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 9, 17, 25],
      glyphs:      _pixelquestGlyphs,
    ),
    LedFont._(
      id:          LedFontId.groutpix,
      name:        'groutpix',
      description: 'Wide bitmap font. 8px cap — fits fewer chars per row, very legible.',
      charHeight:  8,
      charGap:     1,
      lineHeight:  9,
      maxLines:    3,
      rowY:        [1, 10, 19],
      glyphs:      _groutpixGlyphs,
    ),
    LedFont._(
      id:          LedFontId.pixerator,
      name:        'pixerator',
      description: 'Tall pixel font. 8px cap — strong presence on the matrix.',
      charHeight:  7,
      charGap:     1,
      lineHeight:  8,
      maxLines:    4,
      rowY:        [1, 19, 17, 25],
      glyphs:      _pixeratorGlyphs,
    ),
    LedFont._(
      id:          LedFontId.rainyhearts,
      name:        'rainyhearts',
      description: 'Decorative pixel font. 8px cap — playful, expressive style.',
      charHeight:  8,
      charGap:     1,
      lineHeight:  9,
      maxLines:    3,
      rowY:        [1, 10, 19],
      glyphs:      _rainyheartsGlyphs,
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