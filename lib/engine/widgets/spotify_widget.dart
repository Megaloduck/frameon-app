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
class SpotifyWidget extends MatrixWidget<SpotifyLayer> {
  const SpotifyWidget();

  void renderWithTrack(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    // Clear buffer first
    buffer.clear();
    
    switch (layer.layout) {
      case SpotifyLayout.artAndText:
        _renderArtAndText(layer, buffer, elapsedMs, track);
      case SpotifyLayout.textOnly:
        _renderTextOnly(layer, buffer, elapsedMs, track);
      case SpotifyLayout.artOnly:
        _renderArtOnly(buffer, track, layer.opacity);
    }
  }

  @override
  void render(SpotifyLayer layer, PixelBuffer buffer, int elapsedMs) {
    // No track available - show placeholder
    buffer.clear();
    PixelFont.draw(
      buffer: buffer,
      text: "No track",
      color: const Color(0xFF21C32C),
      x: (buffer.width - PixelFont.measureWidth("No track")) ~/ 2,
      y: buffer.height ~/ 2 - 4,
      opacity: layer.opacity,
    );
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  void _renderArtAndText(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    // Art occupies a square on the left equal to the canvas height
    final int artSize = buffer.height;
    _renderArtOnly(buffer, track, layer.opacity, 0, 0, artSize, artSize);

    final int textX = artSize + 1;
    final int textW = buffer.width - textX;
    
    // Position text rows
    final int titleY = 2;
    final int artistY = titleY + PixelFont.glyphHeight + 2;
    final int barY = buffer.height - 3;

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
    final int titleY = (buffer.height - PixelFont.glyphHeight * 2 - 2) ~/ 2;
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

  void _renderArtOnly(
    PixelBuffer buffer,
    SpotifyTrack track,
    double opacity, [
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  ]) {
    final w = width ?? buffer.width;
    final h = height ?? buffer.height;
    
    if (track.artPixels == null || track.artWidth == 0 || track.artHeight == 0) {
      // Show placeholder when no art is available
      buffer.fillRect(x, y, w, h, const Color(0xFF1E1E1E));
      return;
    }
    
    _blitArt(buffer, track, x, y, w, h, opacity);
  }

  // ── Drawing helpers ───────────────────────────────────────────────────────

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
    // Only scroll if text overflows the available width
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
    // Draw the wrap-around copy once the first copy has scrolled off
    if (offset > contentW) {
      PixelFont.draw(
        buffer: buffer, text: text, color: color,
        x: startX - offset + period, y: y, opacity: opacity,
      );
    }
  }

  void _blitArt(
    PixelBuffer dst,
    SpotifyTrack track,
    int x,
    int y,
    int w,
    int h,
    double opacity,
  ) {
    if (track.artPixels == null || track.artWidth == 0 || track.artHeight == 0) {
      dst.fillRect(x, y, w, h, const Color(0xFF1E1E1E));
      return;
    }
    
    // Calculate scaling factors
    final double scaleX = track.artWidth / w;
    final double scaleY = track.artHeight / h;
    
    for (int dy = 0; dy < h; dy++) {
      for (int dx = 0; dx < w; dx++) {
        final int srcX = (dx * scaleX).toInt().clamp(0, track.artWidth - 1);
        final int srcY = (dy * scaleY).toInt().clamp(0, track.artHeight - 1);
        
        int pixel = track.artPixels![srcY * track.artWidth + srcX];
        
        // Apply opacity if needed
        if (opacity < 1.0) {
          final int alpha = ((pixel >> 24) & 0xFF) * opacity.toInt();
          pixel = (alpha << 24) | (pixel & 0x00FFFFFF);
        }
        
        dst.setPixel(x + dx, y + dy, pixel);
      }
    }
  }

  void _drawProgressBar(PixelBuffer buffer, double progress, int x, int y, int w) {
    buffer.fillRect(x, y, w, 2, const Color(0xFF333333));
    final int filled = (w * progress.clamp(0.0, 1.0)).round();
    if (filled > 0) buffer.fillRect(x, y, filled, 2, const Color(0xFF1DB954));
  }
}