import 'dart:typed_data';
import 'dart:ui';

import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';
import 'text_widget.dart';

/// Current track data fed into [SpotifyWidget] by the Spotify service.
class SpotifyTrack {
  final String title;
  final String artist;
  /// Album art as ARGB32 pixels (null if not yet loaded).
  final Uint32List? artPixels;
  final int artWidth;
  final int artHeight;
  /// Playback progress 0.0–1.0.
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
/// Three layout modes, matching the UI screenshot:
///
/// [SpotifyLayout.artAndText]  — left half = album art, right half = scrolling
///                               title + artist + progress bar.
/// [SpotifyLayout.textOnly]   — full width scrolling text + progress bar.
/// [SpotifyLayout.artOnly]    — full width album art scaled to fit.
///
/// Call [renderWithTrack] from [MatrixRenderer] after fetching the current
/// track from the Spotify service provider.
class SpotifyWidget extends MatrixWidget<SpotifyLayer> {
  const SpotifyWidget();

  static const _textWidget = TextWidget();

  /// Render with live track data.
  void renderWithTrack(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    switch (layer.layout) {
      case SpotifyLayout.artAndText:
        _renderArtAndText(layer, buffer, elapsedMs, track);
      case SpotifyLayout.textOnly:
        _renderTextOnly(layer, buffer, elapsedMs, track);
      case SpotifyLayout.artOnly:
        _renderArtOnly(buffer, track);
    }
  }

  @override
  void render(SpotifyLayer layer, PixelBuffer buffer, int elapsedMs) {
    // No-op without a live track — MatrixRenderer calls renderWithTrack().
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  void _renderArtAndText(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    final int artW = buffer.height; // square art on the left
    _blitArt(buffer, track, 0, 0, artW, buffer.height);

    final int textX = artW + 1;
    final int textW = buffer.width - textX;

    if (layer.showTitle && track.title.isNotEmpty) {
      _scrollText(buffer, track.title, layer.textColor, textX, 2, textW,
          elapsedMs, speedMs: 60);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _scrollText(buffer, track.artist, layer.textColor, textX, 12, textW,
          elapsedMs + 200, speedMs: 60);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progress, textX, buffer.height - 3, textW);
    }
  }

  void _renderTextOnly(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    if (layer.showTitle) {
      _scrollText(buffer, track.title, layer.textColor, 0, 4, buffer.width,
          elapsedMs, speedMs: 60);
    }
    if (layer.showArtist) {
      _scrollText(buffer, track.artist, layer.textColor, 0, 14, buffer.width,
          elapsedMs + 200, speedMs: 60);
    }
    if (layer.showProgress) {
      _drawProgressBar(
          buffer, track.progress, 0, buffer.height - 2, buffer.width);
    }
  }

  void _renderArtOnly(PixelBuffer buffer, SpotifyTrack track) {
    _blitArt(buffer, track, 0, 0, buffer.width, buffer.height);
  }

  // ── Drawing helpers ───────────────────────────────────────────────────────

  void _blitArt(PixelBuffer dst, SpotifyTrack track, int x, int y, int w, int h) {
    if (track.artPixels == null ||
        track.artWidth == 0 ||
        track.artHeight == 0) {
      // Placeholder: dark square.
      dst.fillRect(x, y, w, h, const Color(0xFF1E1E1E));
      return;
    }

    final double scaleX = track.artWidth / w;
    final double scaleY = track.artHeight / h;
    for (int dy = 0; dy < h; dy++) {
      for (int dx = 0; dx < w; dx++) {
        final int sx = (dx * scaleX).toInt().clamp(0, track.artWidth - 1);
        final int sy = (dy * scaleY).toInt().clamp(0, track.artHeight - 1);
        dst.setPixel(x + dx, y + dy,
            track.artPixels![sy * track.artWidth + sx]);
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
    int elapsedMs, {
    int speedMs = 60,
  }) {
    final int contentW = text.length * 6;
    final int period = contentW + maxW;
    final int offset = -(elapsedMs ~/ speedMs) % period;

    _textWidget.render(
      TextLayer(
        id: '',
        name: '',
        text: text,
        color: color,
        alignment: TextAlignment.left,
        offset: Offset((startX + offset).toDouble(), (y - 12).toDouble()),
      ),
      buffer,
      0,
    );
  }

  void _drawProgressBar(
      PixelBuffer buffer, double progress, int x, int y, int w) {
    // Background track.
    buffer.fillRect(x, y, w, 2, const Color(0xFF333333));
    // Filled portion (Spotify green).
    final int filled = (w * progress.clamp(0.0, 1.0)).round();
    if (filled > 0) {
      buffer.fillRect(x, y, filled, 2, const Color(0xFF1DB954));
    }
  }
}