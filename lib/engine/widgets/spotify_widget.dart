import 'dart:math' as math;
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

// ─────────────────────────────────────────────────────────────────────────────
// SpotifyTrack
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyTrack {
  final String      title;
  final String      artist;
  final Uint32List? artPixels;
  final int         artWidth;
  final int         artHeight;
  final int         startPositionMs;
  final int         durationMs;
  final double      progress;
  final bool        isPlaying;

  const SpotifyTrack({
    required this.title,
    required this.artist,
    this.artPixels,
    this.artWidth        = 0,
    this.artHeight       = 0,
    this.startPositionMs = 0,
    this.durationMs      = 0,
    this.progress        = 0,
    this.isPlaying       = false,
  });

  static const SpotifyTrack empty = SpotifyTrack(title: '', artist: '');

  double progressAt(int elapsedMs) {
    if (durationMs <= 0) return progress;
    return ((startPositionMs + elapsedMs) / durationMs).clamp(0.0, 1.0);
  }
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
        _renderArtOnly(layer, buffer, elapsedMs, track);
    }
  }

  /// Called when no Spotify track is available (not connected / not playing).
  ///
  /// Renders an idle animation:
  ///   Left  20 px — pixel-art music note icon, pulsing in Spotify green.
  ///   Right 44 px — "SPOTIFY" scrolling top line, "NOT CONNECTED" scrolling
  ///                 bottom line, both in a dimmed green.
  ///
  /// The pulse is a smooth sine wave so the icon breathes naturally.
  /// The text lines scroll continuously using [ScrollLeftEffect] so the
  /// animation stays alive even when the matrix preview is running.
  @override
  void render(SpotifyLayer layer, PixelBuffer buffer, int elapsedMs) {
    buffer.clear();
    _renderIdle(buffer, elapsedMs);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Idle animation
  // ─────────────────────────────────────────────────────────────────────────

  /// Spotify brand green: #1DB954
  static const _kSpotifyGreen = Color(0xFF1DB954);

  /// Dimmed green for the text lines so the icon stands out.
  static const _kTextWhite = Color.fromARGB(255, 250, 250, 250);

  /// Pixel-art music note bitmap (11 wide × 14 tall).
  ///
  /// Each int is a row bitmask; bit 10 (MSB) = leftmost pixel.
  /// Shape: filled note head (oval) bottom-left + stem + two flags top-right.
  static const List<int> _kNote = [
    // row 0–13, 11 bits wide (bit 10 = left). Values in hex (Dart has no 0b).
    0x00C, // 0  — stem top         00000001100
    0x00E, // 1  — stem + flag 1    00000001110
    0x00F, // 2  — stem + flag 2    00000001111
    0x00C, // 3  — stem             00000001100
    0x00C, // 4  — stem             00000001100
    0x00C, // 5  — stem             00000001100
    0x00C, // 6  — stem             00000001100
    0x00C, // 7  — stem             00000001100
    0x06C, // 8  — head top-left    00001101100
    0x0FC, // 9  — head upper       00011111100
    0x1FC, // 10 — head full        00111111100
    0x1FC, // 11 — head full        00111111100
    0x0FC, // 12 — head lower       00011111100
    0x078, // 13 — head base        00001111000
  ];
  static const int _kNoteW = 11;
  static const int _kNoteH = 14;

  void _renderIdle(PixelBuffer buffer, int elapsedMs) {
    final font = LedFontLibrary.get(LedFontId.polymorph);

    // ── Pulsing note icon ────────────────────────────────────────────────────
    // Pulse: sine wave with period 2 s, amplitude 0.4 → brightness 0.6..1.0
    final double pulse =
        0.6 + 0.4 * (math.sin(elapsedMs * 2 * math.pi / 2000) * 0.5 + 0.5);

    // Centre the note inside the left 20-pixel column, vertically centred.
    final int noteX = (20 - _kNoteW) ~/ 2;           // = 4
    final int noteY = (buffer.height - _kNoteH) ~/ 2; // = 9 for 32-row panel

    final int baseR = 0x1D, baseG = 0xB9, baseB = 0x54; // #1DB954
    final int r = (baseR * pulse).round().clamp(0, 255);
    final int g = (baseG * pulse).round().clamp(0, 255);
    final int b = (baseB * pulse).round().clamp(0, 255);
    final int argb = (0xFF << 24) | (r << 16) | (g << 8) | b;

    for (int row = 0; row < _kNoteH; row++) {
      final int bits = _kNote[row];
      for (int col = 0; col < _kNoteW; col++) {
        if ((bits >> (_kNoteW - 1 - col)) & 1 == 1) {
          buffer.setPixel(noteX + col, noteY + row, argb);
        }
      }
    }

    // Thin separator line between icon and text area.
    for (int row = 4; row < buffer.height - 4; row++) {
      buffer.setPixel(20, row, 0xFF1A4020); // very dim green line
    }

    // ── Text area (x = 22 .. 63, w = 42) ────────────────────────────────────
    const int textX = 22;
    const int textW = 42; // 64 − 22
    final int fontH = font.charHeight; // 7
    // Two lines centred vertically: total height = fontH*2 + 3
    final int topY    = (buffer.height - fontH * 2 - 3) ~/ 2;
    final int bottomY = topY + fontH + 3;

    // "SPOTIFY" — scrolls left if wider than textW (it isn't, 42 px > ~40 px
    // at polymorph, but scroll looks nice as idle motion).
    _drawIdleText(font, buffer, 'SPOTIFY', _kSpotifyGreen,
        textX, topY, textW, elapsedMs, speedMs: 120);

    // "NOT CONNECTED" — longer, will definitely scroll.
    _drawIdleText(font, buffer, 'NOT CONNECTED', _kTextWhite,
        textX, bottomY, textW, elapsedMs, speedMs: 90);
  }

  /// Draw a single line of idle text that scrolls left if it overflows [maxW].
  /// Uses [ScrollLeftEffect] directly — no overlay effect.
  void _drawIdleText(
    LedFont font,
    PixelBuffer buffer,
    String text,
    Color color,
    int startX,
    int y,
    int maxW,
    int elapsedMs, {
    int speedMs = 100,
  }) {
    final int contentW = font.textWidth(text);
    final bool needsScroll = contentW > maxW;
    final int bufW = needsScroll ? contentW + maxW : maxW;

    final src = PixelBuffer(width: bufW, height: buffer.height);
    if (needsScroll) {
      font.draw(buffer: src, text: text, color: color, x: 0, y: y);
    } else {
      final int cx = ((maxW - contentW) ~/ 2).clamp(0, maxW - 1);
      font.draw(buffer: src, text: text, color: color, x: cx, y: y);
    }

    PixelBuffer finalBuf = src;
    if (needsScroll) {
      final double pps = 1000.0 / speedMs.clamp(10, 500);
      final effect = ScrollLeftEffect(pixelsPerSecond: pps);
      final scrolled = PixelBuffer(width: bufW, height: buffer.height);
      effect.apply(src, scrolled, elapsedMs);
      finalBuf = scrolled;
    }

    buffer.blit(finalBuf, dx: startX);
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  void _renderArtAndText(SpotifyLayer layer, PixelBuffer buffer,
      int elapsedMs, SpotifyTrack track) {
    final font = LedFontLibrary.get(layer.fontId);
    final int artSize = buffer.height;
    _blitArt(buffer, track, 0, 0, artSize, artSize, ArtLayoutMode.stretch);

    final int textX = artSize + 1;
    final int textW = buffer.width - textX;
    final int fontH = font.charHeight;
    final int titleY  = (buffer.height - fontH * 2 - 2) ~/ 2;
    final int artistY = titleY + fontH + 2;

    if (layer.showTitle && track.title.isNotEmpty) {
      _drawText(font, buffer, track.title, layer.titleColor,
          textX, titleY, textW, elapsedMs, layer.opacity,
          layer.titleEffect, layer.titleOverlayEffect,
          layer.titleEffectSpeedMs);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _drawText(font, buffer, track.artist, layer.artistColor,
          textX, artistY, textW, elapsedMs + 300, layer.opacity,
          layer.artistEffect, layer.artistOverlayEffect,
          layer.artistEffectSpeedMs);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progressAt(elapsedMs), textX,
          buffer.height - 3, buffer.width - textX - 1, layer.progressColor);
    }
  }

  void _renderTextOnly(SpotifyLayer layer, PixelBuffer buffer,
      int elapsedMs, SpotifyTrack track) {
    final font = LedFontLibrary.get(layer.fontId);
    final int fontH = font.charHeight;
    final int titleY  = (buffer.height - fontH * 2 - 2) ~/ 2;
    final int artistY = titleY + fontH + 2;

    if (layer.showTitle && track.title.isNotEmpty) {
      _drawText(font, buffer, track.title, layer.titleColor,
          0, titleY, buffer.width, elapsedMs, layer.opacity,
          layer.titleEffect, layer.titleOverlayEffect,
          layer.titleEffectSpeedMs);
    }
    if (layer.showArtist && track.artist.isNotEmpty) {
      _drawText(font, buffer, track.artist, layer.artistColor,
          0, artistY, buffer.width, elapsedMs + 300, layer.opacity,
          layer.artistEffect, layer.artistOverlayEffect,
          layer.artistEffectSpeedMs);
    }
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progressAt(elapsedMs), 0,
          buffer.height - 2, buffer.width, layer.progressColor);
    }
  }

  void _renderArtOnly(SpotifyLayer layer, PixelBuffer buffer,
      int elapsedMs, SpotifyTrack track) {
    _blitArt(buffer, track, 0, 0, buffer.width, buffer.height,
        layer.artLayoutMode ?? ArtLayoutMode.stretch);
    if (layer.showProgress) {
      _drawProgressBar(buffer, track.progressAt(elapsedMs), 0,
          buffer.height - 2, buffer.width, layer.progressColor);
    }
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
    AnimationEffect scrollEffect,
    AnimationEffect overlayEffect,
    int speedMs,
  ) {
    final int contentW = font.textWidth(text);
    final bool isScroll = scrollEffect == AnimationEffect.scrollLeft ||
                          scrollEffect == AnimationEffect.scrollRight;
    final bool needsScroll = isScroll && contentW > maxW;

    final int bufW = needsScroll ? contentW + maxW : maxW;
    final srcBuf = PixelBuffer(width: bufW, height: buffer.height);

    if (needsScroll) {
      font.draw(buffer: srcBuf, text: text, color: color,
          x: 0, y: y, opacity: baseOpacity);
    } else {
      final int x = ((maxW - contentW) ~/ 2).clamp(0, maxW - 1);
      font.draw(buffer: srcBuf, text: text, color: color,
          x: x, y: y, opacity: baseOpacity);
    }

    PixelBuffer scrolledBuf;
    if (needsScroll) {
      final scrollProcessor = _resolveTextEffect(scrollEffect, speedMs);
      if (scrollProcessor != null) {
        scrolledBuf = PixelBuffer(width: bufW, height: buffer.height);
        scrollProcessor.apply(srcBuf, scrolledBuf, elapsedMs);
      } else {
        scrolledBuf = srcBuf;
      }
    } else {
      scrolledBuf = srcBuf;
    }

    PixelBuffer finalBuf;
    if (overlayEffect != AnimationEffect.none) {
      final overlayProcessor = _resolveTextEffect(overlayEffect, speedMs);
      if (overlayProcessor != null) {
        finalBuf = PixelBuffer(width: bufW, height: buffer.height);
        overlayProcessor.apply(scrolledBuf, finalBuf, elapsedMs);
      } else {
        finalBuf = scrolledBuf;
      }
    } else {
      finalBuf = scrolledBuf;
    }

    buffer.blit(finalBuf, dx: startX);
  }

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
    final src    = track.artPixels!;
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
      if (dstY > y)
        dst.fillRect(x, y, w, dstY - y, const Color(0xFF000000));
      if (dstY + dstHeight < y + h)
        dst.fillRect(x, dstY + dstHeight, w, y + h - dstY - dstHeight,
            const Color(0xFF000000));
      if (dstX > x)
        dst.fillRect(x, dstY, dstX - x, dstHeight, const Color(0xFF000000));
      if (dstX + dstWidth < x + w)
        dst.fillRect(dstX + dstWidth, dstY, x + w - dstX - dstWidth,
            dstHeight, const Color(0xFF000000));
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