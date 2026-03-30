import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../widgets/gif_widget.dart';

/// Decodes GIF / PNG / JPEG bytes into a [GifAsset] for compositing.
///
/// ## Platform safety
/// This file has **no `dart:io` import** — it works on Web, Desktop, Mobile.
/// File loading is the caller's responsibility:
/// - Desktop/Mobile: read bytes via `dart:io` File then call [decodeBytes].
/// - Web: use `XFile.readAsBytes()` or the `file_picker` bytes field.
///
/// For a desktop convenience wrapper see `gif_decoder_io.dart`.
class GifDecoder {
  const GifDecoder();

  /// Decode raw [bytes] into a [GifAsset]. Returns null on failure.
  GifAsset? decodeBytes(Uint8List bytes) {
    try {
      if (_isGif(bytes)) {
        final img.Animation? anim = img.decodeAnimation(bytes);
        if (anim != null && anim.length > 1) return _fromAnimation(anim);
      }
      final img.Image? frame = img.decodeImage(bytes);
      if (frame == null) return null;
      return GifAsset(frames: [_frameFromImage(frame, durationMs: 100)]);
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  GifAsset _fromAnimation(img.Animation anim) {
    final List<DecodedFrame> frames = [];
    for (final img.Image f in anim) {
      final int ms = f.frameDuration > 0 ? f.frameDuration * 10 : 100;
      frames.add(_frameFromImage(f, durationMs: ms));
    }
    return GifAsset(frames: frames);
  }

  DecodedFrame _frameFromImage(img.Image image, {required int durationMs}) {
    // Normalise to RGBA8888
    final img.Image rgba =
        (image.format == img.Format.uint8 && image.numChannels == 4)
            ? image
            : image.convert(format: img.Format.uint8, numChannels: 4);

    final int n = rgba.width * rgba.height;
    final Uint32List argb = Uint32List(n);
    final Uint8List raw = rgba.toUint8List();
    // img: RGBA → PixelBuffer: ARGB
    for (int i = 0; i < n; i++) {
      argb[i] = (raw[i*4+3] << 24) | (raw[i*4] << 16) | (raw[i*4+1] << 8) | raw[i*4+2];
    }
    return DecodedFrame(pixels: argb, width: rgba.width, height: rgba.height, durationMs: durationMs);
  }

  bool _isGif(Uint8List b) =>
      b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;
}