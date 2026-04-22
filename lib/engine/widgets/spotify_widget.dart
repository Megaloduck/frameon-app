import 'dart:typed_data';
import 'dart:ui';

import '../renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
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

/// Album art scaling mode for art-only layout
enum ArtLayoutMode {
  stretch,
  letterbox,
  fill,
}

/// Text animation effect for Spotify text layers.
enum SpotifyTextEffect {
  scroll,
  static_,
  blink,
  pulse,
  fade,
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
    buffer.clear();
    switch (layer.layout) {
      case SpotifyLayout.artAndText:
        _renderArtAndText(layer, buffer, elapsedMs, track);
      case SpotifyLayout.textOnly:
        _renderTextOnly(layer, buffer, elapsedMs, track);
      case SpotifyLayout.artOnly:
        _renderArtOnly(layer, buffer, track);
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
    final font = LedFontLibrary.get(layer.fontId);

    final int artSize = buffer.height;
    _blitArt(buffer, track, 0, 0, artSize, artSize, ArtLayoutMode.stretch);

    final int textX = artSize + 1;
    final int textW = buffer.width - textX;

    final int fontH = font.charHeight;
    final int totalTextH = fontH * 2 + 2;
    final int titleY = (buffer.height - totalTextH) ~/ 2;
    final int artistY = titleY + fontH + 2;
    final int barY = buffer.height - 3;

    if (layer.showTitle && track.title.isNotEmpty) {
      _drawText(
        font,
        buffer,
        track.title,
        layer.titleColor,
        textX,
        titleY,
        textW,
        elapsedMs,
        layer.opacity,
        layer.textEffect,
        layer.textEffectSpeedMs,
      );
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _drawText(
        font,
        buffer,
        track.artist,
        layer.artistColor,
        textX,
        artistY,
        textW,
        elapsedMs + 300,
        layer.opacity,
        layer.textEffect,
        layer.textEffectSpeedMs,
      );
    }
    if (layer.showProgress) {
      _drawProgressBar(
        buffer,
        track.progress,
        textX,
        barY,
        buffer.width - textX - 1,
        layer.progressColor,
      );
    }
  }

  void _renderTextOnly(
    SpotifyLayer layer,
    PixelBuffer buffer,
    int elapsedMs,
    SpotifyTrack track,
  ) {
    final font = LedFontLibrary.get(layer.fontId);
    final int fontH = font.charHeight;
    final int titleY = (buffer.height - fontH * 2 - 2) ~/ 2;
    final int artistY = titleY + fontH + 2;

    if (layer.showTitle && track.title.isNotEmpty) {
      _drawText(
        font,
        buffer,
        track.title,
        layer.titleColor,
        0,
        titleY,
        buffer.width,
        elapsedMs,
        layer.opacity,
        layer.textEffect,
        layer.textEffectSpeedMs,
      );
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _drawText(
        font,
        buffer,
        track.artist,
        layer.artistColor,
        0,
        artistY,
        buffer.width,
        elapsedMs + 300,
        layer.opacity,
        layer.textEffect,
        layer.textEffectSpeedMs,
      );
    }
    if (layer.showProgress) {
      _drawProgressBar(
        buffer,
        track.progress,
        0,
        buffer.height - 2,
        buffer.width - 1,
        layer.progressColor,
      );
    }
  }

  void _renderArtOnly(
    SpotifyLayer layer,
    PixelBuffer buffer,
    SpotifyTrack track,
  ) {
    final mode = layer.artLayoutMode ?? ArtLayoutMode.stretch;
    _blitArt(buffer, track, 0, 0, buffer.width, buffer.height, mode);
  }

  // ── Text rendering ────────────────────────────────────────────────────────

  void _drawText(
    LedFont font,
    PixelBuffer buffer,
    String text,
    Color color,
    int startX,
    int y,
    int maxW,
    int elapsedMs,
    double baseOpacity,
    SpotifyTextEffect effect,
    int speedMs,
  ) {
    switch (effect) {
      case SpotifyTextEffect.scroll:
        _scrollText(
          font,
          buffer,
          text,
          color,
          startX,
          y,
          maxW,
          elapsedMs,
          baseOpacity,
          speedMs: speedMs,
        );

      case SpotifyTextEffect.static_:
        final int tw = font.textWidth(text);
        final int x = startX + ((maxW - tw) ~/ 2).clamp(0, maxW);
        font.draw(
          buffer: buffer,
          text: text,
          color: color,
          x: x,
          y: y,
          opacity: baseOpacity,
        );

      case SpotifyTextEffect.blink:
        final bool on = (elapsedMs ~/ 500) % 2 == 0;
        if (!on) return;
        _scrollText(
          font,
          buffer,
          text,
          color,
          startX,
          y,
          maxW,
          elapsedMs,
          baseOpacity,
          speedMs: speedMs,
        );

      case SpotifyTextEffect.pulse:
        final double phase = (elapsedMs % 2000) / 2000;
        final double op =
            (0.5 - 0.5 * _cos(phase * 2 * 3.14159)) * baseOpacity;
        _scrollText(
          font,
          buffer,
          text,
          color,
          startX,
          y,
          maxW,
          elapsedMs,
          op.clamp(0, 1),
          speedMs: speedMs,
        );

      case SpotifyTextEffect.fade:
        final int t = elapsedMs % 3000;
        final double op = t < 1500 ? baseOpacity : 0.0;
        _scrollText(
          font,
          buffer,
          text,
          color,
          startX,
          y,
          maxW,
          elapsedMs,
          op,
          speedMs: speedMs,
        );
    }
  }

  void _scrollText(
    LedFont font,
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
    final int contentW = font.textWidth(text);
    if (contentW <= maxW) {
      final int x = startX + ((maxW - contentW) ~/ 2).clamp(0, maxW);
      font.draw(
        buffer: buffer,
        text: text,
        color: color,
        x: x,
        y: y,
        opacity: opacity,
      );
      return;
    }
    final int period = contentW + maxW;
    final int offset = (elapsedMs ~/ speedMs) % period;
    font.draw(
      buffer: buffer,
      text: text,
      color: color,
      x: startX - offset,
      y: y,
      opacity: opacity,
    );
    if (offset > contentW) {
      font.draw(
        buffer: buffer,
        text: text,
        color: color,
        x: startX - offset + period,
        y: y,
        opacity: opacity,
      );
    }
  }

  double _cos(double x) {
    final double x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24;
  }

  // ── Album art ─────────────────────────────────────────────────────────────

  void _blitArt(
    PixelBuffer dst,
    SpotifyTrack track,
    int x,
    int y,
    int w,
    int h,
    ArtLayoutMode mode,
  ) {
    if (track.artPixels == null ||
        track.artWidth == 0 ||
        track.artHeight == 0) {
      dst.fillRect(x, y, w, h, const Color(0xFF1E1E1E));
      return;
    }

    final Uint32List src = track.artPixels!;
    final int srcW = track.artWidth;
    final int srcH = track.artHeight;

    int srcX = 0, srcY = 0;
    int srcWidth = srcW, srcHeight = srcH;
    int dstX = x, dstY = y;
    int dstWidth = w, dstHeight = h;

    switch (mode) {
      case ArtLayoutMode.stretch:
        break;

      case ArtLayoutMode.letterbox:
        final double srcAspect = srcW / srcH;
        final double dstAspect = w / h;
        if (srcAspect > dstAspect) {
          dstWidth = w;
          dstHeight = (w / srcAspect).round();
          dstY = y + ((h - dstHeight) ~/ 2);
        } else {
          dstHeight = h;
          dstWidth = (h * srcAspect).round();
          dstX = x + ((w - dstWidth) ~/ 2);
        }
        break;

      case ArtLayoutMode.fill:
        final double srcAspect = srcW / srcH;
        final double dstAspect = w / h;
        if (srcAspect > dstAspect) {
          srcWidth = (srcH * dstAspect).round();
          srcX = (srcW - srcWidth) ~/ 2;
        } else {
          srcHeight = (srcW / dstAspect).round();
          srcY = (srcH - srcHeight) ~/ 2;
        }
        break;
    }

    final double scaleX = srcWidth / dstWidth;
    final double scaleY = srcHeight / dstHeight;

    if (mode == ArtLayoutMode.letterbox) {
      if (dstY > y) dst.fillRect(x, y, w, dstY - y, const Color(0xFF000000));
      if (dstY + dstHeight < y + h) {
        dst.fillRect(
          x,
          dstY + dstHeight,
          w,
          y + h - (dstY + dstHeight),
          const Color(0xFF000000),
        );
      }
      if (dstX > x) {
        dst.fillRect(x, dstY, dstX - x, dstHeight, const Color(0xFF000000));
      }
      if (dstX + dstWidth < x + w) {
        dst.fillRect(
          dstX + dstWidth,
          dstY,
          x + w - (dstX + dstWidth),
          dstHeight,
          const Color(0xFF000000),
        );
      }
    }

    for (int dy = 0; dy < dstHeight; dy++) {
      final int srcYPos =
          srcY + (dy * scaleY).toInt().clamp(0, srcHeight - 1);
      for (int dx = 0; dx < dstWidth; dx++) {
        final int srcXPos =
            srcX + (dx * scaleX).toInt().clamp(0, srcWidth - 1);
        final int pixel = src[srcYPos * srcW + srcXPos] | 0xFF000000;
        dst.setPixel(dstX + dx, dstY + dy, pixel);
      }
    }
  }

  void _drawProgressBar(
    PixelBuffer buffer,
    double progress,
    int x,
    int y,
    int w,
    Color color,
  ) {
    buffer.fillRect(x, y, w, 2, const Color(0xFF333333));
    final int filled = (w * progress.clamp(0.0, 1.0)).round();
    if (filled > 0) {
      buffer.fillRect(x, y, filled, 2, color);
    }
  }
}