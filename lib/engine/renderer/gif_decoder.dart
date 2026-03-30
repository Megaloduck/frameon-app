import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../widgets/gif_widget.dart';

/// Decodes GIF / PNG / JPEG bytes into a [GifAsset] for compositing.
///
/// ## image package v4.x API
/// `img.Animation` and `img.decodeAnimation()` were removed in image 4.0.
/// Animated GIFs are now represented as `img.Image` with a `.frames` list.
/// Each `img.Frame` exposes `.image` (pixel data) and `.duration` (Duration).
///
/// ## Platform safety
/// No `dart:io` — works on Web, Desktop, Mobile.
/// File loading is the caller's responsibility; pass bytes to [decodeBytes].
class GifDecoder {
  const GifDecoder();

  /// Decode raw [bytes] (PNG, JPEG, or GIF) into a [GifAsset].
  /// Returns null if the format is unrecognised or data is corrupt.
  GifAsset? decodeBytes(Uint8List bytes) {
    try {
      // decodeImage handles all supported formats.
      // For animated GIFs the returned Image has a populated .frames list.
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Multi-frame animated GIF
      if (image.frames.isNotEmpty) {
        return _fromFrames(image);
      }

      // Single-frame image (PNG, JPEG, single-frame GIF)
      return GifAsset(frames: [_frameFromImage(image, durationMs: 100)]);
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Build a [GifAsset] from an animated [img.Image] whose `.frames` is populated.
  GifAsset _fromFrames(img.Image image) {
    final List<DecodedFrame> frames = [];

    for (final img.Frame f in image.frames) {
      // In image 4.x each Frame has a .duration (Duration) and .image (img.Image).
      final int ms = f.duration.inMilliseconds > 0 ? f.duration.inMilliseconds : 100;
      frames.add(_frameFromImage(f.image, durationMs: ms));
    }

    // Fallback: if frames list was empty (shouldn't happen here), render the root.
    if (frames.isEmpty) {
      return GifAsset(frames: [_frameFromImage(image, durationMs: 100)]);
    }

    return GifAsset(frames: frames);
  }

  /// Convert a single [img.Image] frame to [DecodedFrame] in ARGB32 format.
  DecodedFrame _frameFromImage(img.Image image, {required int durationMs}) {
    // Normalise to RGBA8888 for consistent pixel layout.
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
              | (raw[i * 4 + 1] << 8)   // G
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