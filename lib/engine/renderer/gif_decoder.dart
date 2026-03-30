import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../widgets/gif_widget.dart';

/// Decodes GIF / PNG / JPEG bytes into a [GifAsset] for compositing.
///
/// ## image package v4.x API notes
/// - `img.Animation` and `img.decodeAnimation()` were removed in v4.
/// - `img.Frame` does not exist in v4.
/// - [img.Image.frames] is `List<img.Image>` — each element IS the frame.
/// - [img.Image.frameDuration] is an `int` (milliseconds).
/// - [img.Image.hasAnimation] is a `bool` convenience getter.
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

      // Animated GIF: .frames contains all frames as img.Image objects.
      if (image.frames.isNotEmpty) {
        return _fromFrames(image);
      }

      // Single-frame (PNG, JPEG, non-animated GIF).
      return GifAsset(frames: [_frameFromImage(image, durationMs: 100)]);
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Build a multi-frame [GifAsset].
  /// In image 4.x, [img.Image.frames] is `List<img.Image>`.
  /// Each frame's display time is [img.Image.frameDuration] (int, ms).
  GifAsset _fromFrames(img.Image image) {
    final List<DecodedFrame> frames = [];

    for (final img.Image frame in image.frames) {
      final int ms = frame.frameDuration > 0 ? frame.frameDuration : 100;
      frames.add(_frameFromImage(frame, durationMs: ms));
    }

    // Fallback: should not happen, but guard anyway.
    if (frames.isEmpty) {
      return GifAsset(frames: [_frameFromImage(image, durationMs: 100)]);
    }

    return GifAsset(frames: frames);
  }

  /// Convert one [img.Image] to a [DecodedFrame] in ARGB32 format.
  DecodedFrame _frameFromImage(img.Image image, {required int durationMs}) {
    // Normalise to RGBA8888 so pixel layout is always consistent.
    final img.Image rgba =
        (image.format == img.Format.uint8 && image.numChannels == 4)
            ? image
            : image.convert(format: img.Format.uint8, numChannels: 4);

    final int n = rgba.width * rgba.height;
    final Uint32List argb = Uint32List(n);
    final Uint8List raw = rgba.toUint8List();

    // img stores RGBA; PixelBuffer expects ARGB (0xAARRGGBB).
    for (int i = 0; i < n; i++) {
      argb[i] = (raw[i * 4 + 3] << 24) // A
              | (raw[i * 4]     << 16)  // R
              | (raw[i * 4 + 1] <<  8)  // G
              |  raw[i * 4 + 2];        // B
    }

    return DecodedFrame(
      pixels: argb,
      width: rgba.width,
      height: rgba.height,
      durationMs: durationMs,
    );
  }
}