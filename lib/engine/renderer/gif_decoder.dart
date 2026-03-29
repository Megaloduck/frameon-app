import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../widgets/gif_widget.dart';

/// Decodes a GIF, PNG, or JPEG file from disk into a [GifAsset] ready for
/// compositing by [GifWidget].
///
/// For animated GIFs every frame is decoded and its display duration is
/// preserved. Static images produce a single-frame [GifAsset].
///
/// All pixel data is stored as ARGB32 [Uint32List] matching [PixelBuffer]'s
/// internal format so [GifWidget._blit] can read pixels directly.
class GifDecoder {
  const GifDecoder();

  /// Decode [file] and return a [GifAsset], or null on error.
  Future<GifAsset?> decode(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      return decodeBytes(bytes, path: file.path);
    } catch (e) {
      // Swallow decode errors — the renderer treats null as "not loaded yet".
      return null;
    }
  }

  /// Decode raw [bytes] (useful for web where there is no File API).
  GifAsset? decodeBytes(Uint8List bytes, {String path = ''}) {
    try {
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // img.decodeImage collapses animated GIFs to the first frame.
      // For animated GIFs we need decodeAnimation.
      if (_isGif(path, bytes)) {
        final img.Animation? anim = img.decodeAnimation(bytes);
        if (anim != null && anim.length > 1) {
          return _fromAnimation(anim);
        }
      }

      // Single frame (PNG, JPEG, or single-frame GIF).
      return GifAsset(frames: [_frameFromImage(decoded, durationMs: 100)]);
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  GifAsset _fromAnimation(img.Animation anim) {
    final List<DecodedFrame> frames = [];
    for (final img.Image frame in anim) {
      // GIF frame duration is stored in centiseconds; convert to ms.
      final int durationMs =
          frame.frameDuration > 0 ? frame.frameDuration * 10 : 100;
      frames.add(_frameFromImage(frame, durationMs: durationMs));
    }
    return GifAsset(frames: frames);
  }

  DecodedFrame _frameFromImage(img.Image image, {required int durationMs}) {
    // Ensure we have RGBA8888 — convert if the source uses a different format.
    final img.Image rgba = image.format == img.Format.uint8 && image.numChannels == 4
        ? image
        : image.convert(format: img.Format.uint8, numChannels: 4);

    final int pixelCount = rgba.width * rgba.height;
    final Uint32List argb = Uint32List(pixelCount);

    // img stores pixels as RGBA; PixelBuffer expects ARGB.
    final Uint8List raw = rgba.toUint8List();
    for (int i = 0; i < pixelCount; i++) {
      final int r = raw[i * 4];
      final int g = raw[i * 4 + 1];
      final int b = raw[i * 4 + 2];
      final int a = raw[i * 4 + 3];
      argb[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }

    return DecodedFrame(
      pixels: argb,
      width: rgba.width,
      height: rgba.height,
      durationMs: durationMs,
    );
  }

  bool _isGif(String path, Uint8List bytes) {
    if (path.toLowerCase().endsWith('.gif')) return true;
    // Check GIF magic bytes: GIF87a or GIF89a
    if (bytes.length < 6) return false;
    return bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
  }
}