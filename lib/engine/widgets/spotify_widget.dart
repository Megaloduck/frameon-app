import 'dart:typed_data';
import 'dart:ui';

import '../animation/font_effects/base_fonteffect.dart';
import '../animation/font_effects/blink_fonteffect.dart';
import '../animation/font_effects/burst_fonteffect.dart';
import '../animation/font_effects/fade_fonteffect.dart';
import '../animation/font_effects/leftscroll_fonteffect.dart';
import '../animation/font_effects/pulse_fonteffect.dart';
import '../animation/font_effects/rightscroll_fonteffect.dart';
import '../renderer/font_organizer.dart';
import '../renderer/pixel_buffer.dart';
import '../scene/layer.dart';
import 'matrix_widget.dart';

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

enum ArtLayoutMode { stretch, letterbox, fill }

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
  void render(SpotifyLayer layer, PixelBuffer buffer, int elapsedMs) =>
      buffer.clear();

  // ── Layouts ───────────────────────────────────────────────────────────────

  void _renderArtAndText(SpotifyLayer layer, PixelBuffer buffer,
      int elapsedMs, SpotifyTrack track) {
    final font = LedFontLibrary.get(layer.fontId);
    final int artSize = buffer.height;
    _blitArt(buffer, track, 0, 0, artSize, artSize, ArtLayoutMode.stretch);

    final int textX = artSize + 1;
    final int textW = buffer.width - textX;
    final int fontH = font.charHeight;
    final int titleY = (buffer.height - fontH * 2 - 2) ~/ 2;
    final int artistY = titleY + fontH + 2;

    if (layer.showTitle && track.title.isNotEmpty) {
      _drawText(font, buffer, track.title, layer.titleColor,
          textX, titleY, textW, elapsedMs, layer.opacity,
          layer.titleEffect, layer.titleEffectSpeedMs);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _drawText(font, buffer, track.artist, layer.artistColor,
          textX, artistY, textW, elapsedMs + 300, layer.opacity,
          layer.artistEffect, layer.artistEffectSpeedMs);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progress, textX,
          buffer.height - 3, buffer.width - textX - 1, layer.progressColor);
    }
  }

  void _renderTextOnly(SpotifyLayer layer, PixelBuffer buffer,
      int elapsedMs, SpotifyTrack track) {
    final font = LedFontLibrary.get(layer.fontId);
    final int fontH = font.charHeight;
    final int titleY = (buffer.height - fontH * 2 - 2) ~/ 2;
    final int artistY = titleY + fontH + 2;

    if (layer.showTitle && track.title.isNotEmpty) {
      _drawText(font, buffer, track.title, layer.titleColor,
          0, titleY, buffer.width, elapsedMs, layer.opacity,
          layer.titleEffect, layer.titleEffectSpeedMs);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _drawText(font, buffer, track.artist, layer.artistColor,
          0, artistY, buffer.width, elapsedMs + 300, layer.opacity,
          layer.artistEffect, layer.artistEffectSpeedMs);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progress, 0,
          buffer.height - 2, buffer.width - 1, layer.progressColor);
    }
  }

  void _renderArtOnly(SpotifyLayer layer, PixelBuffer buffer,
      SpotifyTrack track) {
    _blitArt(buffer, track, 0, 0, buffer.width, buffer.height,
        layer.artLayoutMode ?? ArtLayoutMode.stretch);
  }

  // ── Text rendering ────────────────────────────────────────────────────────

  /// Renders [text] into a temporary [PixelBuffer], applies the engine's
  /// [AnimationEffectProcessor] for [effect], then blits the result into
  /// [buffer] at ([startX], 0). The main buffer's right edge acts as the
  /// natural viewport clip, so no extra cropping is needed.
  ///
  /// For scroll effects the temp buffer is [contentW + maxW] wide, which
  /// gives the wrap-around gap for free — the processor loops within that
  /// width and [blit] clips to [maxW] visible columns automatically.
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
  AnimationEffect effect,
  int speedMs,
) {
  final int contentW = font.textWidth(text);
  final bool isScroll = effect == AnimationEffect.scrollLeft ||
                        effect == AnimationEffect.scrollRight;
  // Only perform a marquee when text is actually wider than the viewport.
  // Short text that fits should be shown centered and static, regardless of
  // the scroll setting — same behaviour as the original _scrollText helper.
  final bool needsScroll = isScroll && contentW > maxW;

  final int bufW = needsScroll ? contentW + maxW : maxW;
  final srcBuf = PixelBuffer(width: bufW, height: buffer.height);

  if (needsScroll) {
    // Text starts at x=0 so the scroll processor can sweep it across bufW.
    font.draw(buffer: srcBuf, text: text, color: color,
        x: 0, y: y, opacity: baseOpacity);
  } else {
    // Centre text in the viewport (short text, or a non-scroll effect).
    final int x = ((maxW - contentW) ~/ 2).clamp(0, maxW - 1);
    font.draw(buffer: srcBuf, text: text, color: color,
        x: x, y: y, opacity: baseOpacity);
  }

  // Scroll processor is only meaningful when needsScroll is true.
  // For short text with a scroll setting, skip the processor so the
  // centred text is shown statically instead of looping within maxW.
  final bool applyProcessor = needsScroll || !isScroll;
  final processor =
      applyProcessor ? _resolveTextEffect(effect, speedMs) : null;

  if (processor == null) {
    buffer.blit(srcBuf, dx: startX);
  } else {
    final dstBuf = PixelBuffer(width: bufW, height: buffer.height);
    processor.apply(srcBuf, dstBuf, elapsedMs);
    buffer.blit(dstBuf, dx: startX);
  }
}

  /// Maps [AnimationEffect] → the same [AnimationEffectProcessor] the engine
  /// uses for [TextLayer], parameterised by [speedMs] (ms per scroll pixel).
  AnimationEffectProcessor? _resolveTextEffect(
      AnimationEffect effect, int speedMs) {
    final double pps = 1000.0 / speedMs.clamp(10, 500);
    return switch (effect) {
      AnimationEffect.none        => null,
      AnimationEffect.blink       => const BlinkEffect(periodMs: 1000),
      AnimationEffect.scrollLeft  => ScrollLeftEffect(pixelsPerSecond: pps),
      AnimationEffect.scrollRight => ScrollRightEffect(pixelsPerSecond: pps),
      AnimationEffect.pulse       => const PulseEffect(periodMs: 2000, minOpacity: 0.08),
      AnimationEffect.fade        => const FadeEffect(holdMs: 1200, fadeMs: 600),
      AnimationEffect.burst       => const BurstEffect(periodMs: 1500, flashMs: 400, dimOpacity: 0.12),
    };
  }

  // ── Album art ─────────────────────────────────────────────────────────────

  void _blitArt(PixelBuffer dst, SpotifyTrack track,
      int x, int y, int w, int h, ArtLayoutMode mode) {
    if (track.artPixels == null ||
        track.artWidth == 0 ||
        track.artHeight == 0) {
      dst.fillRect(x, y, w, h, const Color(0xFF1E1E1E));
      return;
    }
    final src = track.artPixels!;
    final int srcW = track.artWidth, srcH = track.artHeight;
    int srcX = 0, srcY = 0, srcWidth = srcW, srcHeight = srcH;
    int dstX = x, dstY = y, dstWidth = w, dstHeight = h;

    switch (mode) {
      case ArtLayoutMode.stretch:
        break;
      case ArtLayoutMode.letterbox:
        final double sa = srcW / srcH, da = w / h;
        if (sa > da) {
          dstHeight = (w / sa).round();
          dstY = y + ((h - dstHeight) ~/ 2);
        } else {
          dstWidth = (h * sa).round();
          dstX = x + ((w - dstWidth) ~/ 2);
        }
      case ArtLayoutMode.fill:
        final double sa = srcW / srcH, da = w / h;
        if (sa > da) {
          srcWidth = (srcH * da).round();
          srcX = (srcW - srcWidth) ~/ 2;
        } else {
          srcHeight = (srcW / da).round();
          srcY = (srcH - srcHeight) ~/ 2;
        }
    }

    final double scaleX = srcWidth / dstWidth, scaleY = srcHeight / dstHeight;
    if (mode == ArtLayoutMode.letterbox) {
      if (dstY > y) dst.fillRect(x, y, w, dstY - y, const Color(0xFF000000));
      if (dstY + dstHeight < y + h)
        dst.fillRect(x, dstY + dstHeight, w, y + h - dstY - dstHeight, const Color(0xFF000000));
      if (dstX > x) dst.fillRect(x, dstY, dstX - x, dstHeight, const Color(0xFF000000));
      if (dstX + dstWidth < x + w)
        dst.fillRect(dstX + dstWidth, dstY, x + w - dstX - dstWidth, dstHeight, const Color(0xFF000000));
    }
    for (int dy = 0; dy < dstHeight; dy++) {
      final int sy = srcY + (dy * scaleY).toInt().clamp(0, srcHeight - 1);
      for (int dx = 0; dx < dstWidth; dx++) {
        final int sx = srcX + (dx * scaleX).toInt().clamp(0, srcWidth - 1);
        dst.setPixel(dstX + dx, dstY + dy, src[sy * srcW + sx] | 0xFF000000);
      }
    }
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  void _drawProgressBar(PixelBuffer buffer, double progress,
      int x, int y, int w, Color color) {
    buffer.fillRect(x, y, w, 2, const Color(0xFF333333));
    final int filled = (w * progress.clamp(0.0, 1.0)).round();
    if (filled > 0) buffer.fillRect(x, y, filled, 2, color);
  }
}