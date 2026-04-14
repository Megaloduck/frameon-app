import 'dart:typed_data';
import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../renderer/fonts/pixel_font.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

/// Current track data fed into [SpotifyWidget] by the Spotify service.
class SpotifyTrack {
  final String title;
  final String artist;
  final Uint32List? artPixels;
  final int artWidth;
  final int artHeight;
  final double progress;
  final bool isPlaying;

  const SpotifyTrack({
    required this.title,
    required this.artist,
    this.artPixels,
    this.artWidth = 0,
    this.artHeight = 0,
    this.progress = 0,
    this.isPlaying = false,
  });

  static const SpotifyTrack empty = SpotifyTrack(title: '', artist: '');
}

/// Renders a [SpotifyLayer] into a [PixelBuffer].
///
/// Layout modes:
/// - artAndText — square album art on the left, scrolling text on the right
/// - textOnly   — full-width scrolling text + progress bar
/// - artOnly    — full-width scaled album art
class SpotifyWidget extends MatrixWidget<SpotifyLayer> {
  const SpotifyWidget();

  void renderWithTrack(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    buffer.clear();
    switch (layer.layout) {
      case SpotifyLayout.artAndText:
        _renderArtAndText(layer, buffer, elapsedMs, track);
      case SpotifyLayout.textOnly:
        _renderTextOnly(layer, buffer, elapsedMs, track);
      case SpotifyLayout.artOnly:
        _blitArt(buffer, track, 0, 0, buffer.width, buffer.height);
    }
  }

  @override
  void render(SpotifyLayer layer, PixelBuffer buffer, int elapsedMs) {
    buffer.clear();
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  void _renderArtAndText(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    // Art occupies a square on the left equal to the canvas height.
    final int artSize = buffer.height; // 32px
    _blitArt(buffer, track, 0, 0, artSize, artSize);

    final int textX  = artSize + 1;
    final int textW  = buffer.width - textX;
    final int titleY  = 2;
    final int artistY = titleY + PixelFont.glyphHeight + 2;
    final int barY    = buffer.height - 3;

    if (layer.showTitle && track.title.isNotEmpty) {
      _scrollText(buffer, track.title, layer.textColor, textX, titleY,
          textW, elapsedMs, layer.opacity);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _scrollText(buffer, track.artist, layer.textColor, textX, artistY,
          textW, elapsedMs + 300, layer.opacity);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progress, textX, barY, textW);
    }
  }

  void _renderTextOnly(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    final int titleY  = (buffer.height - PixelFont.glyphHeight * 2 - 2) ~/ 2;
    final int artistY = titleY + PixelFont.glyphHeight + 2;

    if (layer.showTitle && track.title.isNotEmpty) {
      _scrollText(buffer, track.title, layer.textColor, 0, titleY,
          buffer.width, elapsedMs, layer.opacity);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _scrollText(buffer, track.artist, layer.textColor, 0, artistY,
          buffer.width, elapsedMs + 300, layer.opacity);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progress, 0, buffer.height - 2, buffer.width);
    }
  }

  // ── Drawing helpers ───────────────────────────────────────────────────────

  /// Blit album art into the destination buffer.
  ///
  /// The art pixels arrive as ARGB (0xAARRGGBB) with A typically 0xFF.
  /// We force full opacity (OR with 0xFF000000) so the pixel is never
  /// treated as transparent during compositing.
  ///
  /// Previous bug: `opacity.toInt()` always returns 0 for 0.0 < opacity < 1.0,
  /// making every pixel transparent. Fixed by using integer multiply instead.
  void _blitArt(
    PixelBuffer dst,
    SpotifyTrack track,
    int x,
    int y,
    int w,
    int h,
  ) {
    if (track.artPixels == null ||
        track.artWidth == 0 ||
        track.artHeight == 0) {
      // Dark placeholder when no art is available yet
      dst.fillRect(x, y, w, h, const Color(0xFF1E1E1E));
      return;
    }

    final Uint32List src   = track.artPixels!;
    final int        srcW  = track.artWidth;
    final int        srcH  = track.artHeight;
    final double     scaleX = srcW / w;
    final double     scaleY = srcH / h;

    for (int dy = 0; dy < h; dy++) {
      final int srcY = (dy * scaleY).toInt().clamp(0, srcH - 1);
      for (int dx = 0; dx < w; dx++) {
        final int srcX = (dx * scaleX).toInt().clamp(0, srcW - 1);
        // Force alpha to 0xFF — art is always fully opaque on the matrix
        final int pixel = src[srcY * srcW + srcX] | 0xFF000000;
        dst.setPixel(x + dx, y + dy, pixel);
      }
    }
  }

  void _scrollText(
    PixelBuffer buffer,
    String text,
    Color color,
    int startX,
    int y,
    int maxW,
    int elapsedMs,
    double opacity, {
    int speedMs = 60,
  }) {
    final int contentW = PixelFont.measureWidth(text);
    if (contentW <= maxW) {
      PixelFont.draw(
        buffer: buffer, text: text, color: color,
        x: startX, y: y, opacity: opacity,
      );
      return;
    }
    final int period = contentW + maxW;
    final int offset = (elapsedMs ~/ speedMs) % period;
    PixelFont.draw(
      buffer: buffer, text: text, color: color,
      x: startX - offset, y: y, opacity: opacity,
    );
    if (offset > contentW) {
      PixelFont.draw(
        buffer: buffer, text: text, color: color,
        x: startX - offset + period, y: y, opacity: opacity,
      );
    }
  }

  void _drawProgressBar(PixelBuffer buffer, double progress, int x, int y, int w) {
    buffer.fillRect(x, y, w, 2, const Color(0xFF333333));
    final int filled = (w * progress.clamp(0.0, 1.0)).round();
    if (filled > 0) {
      buffer.fillRect(x, y, filled, 2, const Color(0xFF1DB954));
    }
  }
}