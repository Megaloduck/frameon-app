import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../widgets/gif_widget.dart';

/// Decodes GIF / PNG / JPEG bytes into a [GifAsset] for compositing.
///
/// ## image package v4.x — animated GIF handling
///
/// In v4, `img.Image.frames` is a `List<img.Image>` where:
///   - For a **static** image (PNG, JPEG, non-animated GIF), `frames` has
///     exactly ONE entry and `hasAnimation` is false.
///   - For an **animated** GIF, `frames` has N entries, one per animation
///     frame, and `hasAnimation` is true.
///
/// Critical: GIF frames are typically **delta frames** — they only store the
/// pixels that changed relative to the previous frame, not the full composited
/// image.  Calling `toUint8List()` or reading `.data` on a raw delta frame
/// gives wrong/empty pixels.  The fix is to call `frame.convert(...)` which
/// forces the image library to composite and materialise each frame into a
/// standalone full-size RGBA image before we read the pixels.
///
/// ## Platform safety
/// No `dart:io` — works on Web, Desktop, and Mobile.
class GifDecoder {
  const GifDecoder();

  /// Decode raw [bytes] (PNG, JPEG, or GIF) into a [GifAsset].
  /// Returns null if the format is unrecognised or data is corrupt.
  GifAsset? decodeBytes(Uint8List bytes) {
    try {
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Use hasAnimation to correctly distinguish animated GIFs from statics.
      // image.frames.isNotEmpty is always true in v4 (even for single images),
      // so we must NOT use it as the branching condition.
      if (image.hasAnimation) {
        return _fromAnimatedGif(image);
      }

      // Static image (PNG, JPEG, non-animated GIF, single-frame WebP).
      return GifAsset(frames: [_frameFromImage(image, durationMs: 100)]);
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Build a [GifAsset] from an animated GIF.
  ///
  /// Each frame in [image.frames] is a **delta frame** — only the changed
  /// region is stored.  We call [img.Image.convert] to force the library to
  /// composite each frame into a full RGBA8888 image before reading pixels.
  GifAsset _fromAnimatedGif(img.Image image) {
    final List<DecodedFrame> frames = [];

    for (final img.Image rawFrame in image.frames) {
      final int durationMs =
          rawFrame.frameDuration > 0 ? rawFrame.frameDuration : 100;

      // Convert forces full materialisation of the composited frame.
      // Without this, delta-encoded GIF frames read as mostly transparent.
      final img.Image full = rawFrame.convert(
        format: img.Format.uint8,
        numChannels: 4,
      );

      frames.add(_frameFromImage(full, durationMs: durationMs));
    }

    if (frames.isEmpty) {
      // Fallback — should never happen for a valid animated GIF.
      return GifAsset(frames: [_frameFromImage(image, durationMs: 100)]);
    }

    return GifAsset(frames: frames);
  }

  /// Convert one [img.Image] (already in RGBA8888) into a [DecodedFrame].
  DecodedFrame _frameFromImage(img.Image image, {required int durationMs}) {
    // Normalise to RGBA8888 so pixel layout is always consistent.
    final img.Image rgba =
        (image.format == img.Format.uint8 && image.numChannels == 4)
            ? image
            : image.convert(format: img.Format.uint8, numChannels: 4);

    final int n      = rgba.width * rgba.height;
    final Uint32List argb = Uint32List(n);
    final Uint8List  raw  = rgba.toUint8List();

    // img stores pixels as RGBA; PixelBuffer expects ARGB (0xAARRGGBB).
    for (int i = 0; i < n; i++) {
      argb[i] = (raw[i * 4 + 3] << 24) // A
              | (raw[i * 4]     << 16)  // R
              | (raw[i * 4 + 1] <<  8)  // G
              |  raw[i * 4 + 2];        // B
    }

    return DecodedFrame(
      pixels:     argb,
      width:      rgba.width,
      height:     rgba.height,
      durationMs: durationMs,
    );
  }
}