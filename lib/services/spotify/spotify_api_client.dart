import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyNowPlaying {
  final String  title;
  final String  artist;
  final String? albumArtUrl;
  final int     durationMs;
  final int     progressMs;
  final bool    isPlaying;
  final String? trackId;

  const SpotifyNowPlaying({
    required this.title,
    required this.artist,
    this.albumArtUrl,
    required this.durationMs,
    required this.progressMs,
    required this.isPlaying,
    this.trackId,
  });

  double get progress =>
      durationMs > 0 ? (progressMs / durationMs).clamp(0.0, 1.0) : 0.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// API client
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyApiClient {
  static const _base = 'https://api.spotify.com/v1';

  Map<String, String> _auth(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type':  'application/json',
      };

  // ── Now playing ───────────────────────────────────────────────────────────

  Future<SpotifyNowPlaying?> getNowPlaying(String token) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_base/me/player/currently-playing'),
            headers: _auth(token),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 204 || resp.body.isEmpty) return null;
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final item = json['item'] as Map<String, dynamic>?;
      if (item == null) return null;

      // Build artist string
      final artists = (item['artists'] as List<dynamic>)
          .map((a) => (a as Map<String, dynamic>)['name'] as String)
          .join(', ');

      // Pick smallest image ≥ 64 px to minimise download size
      final images =
          (item['album'] as Map<String, dynamic>?)?['images'] as List<dynamic>?;
      String? artUrl;
      if (images != null && images.isNotEmpty) {
        for (final image in images.reversed) {
          final w = (image as Map<String, dynamic>)['width'] as int? ?? 0;
          if (w >= 64) { artUrl = image['url'] as String?; break; }
        }
        artUrl ??= (images.last as Map<String, dynamic>)['url'] as String?;
      }

      return SpotifyNowPlaying(
        title:       item['name'] as String,
        artist:      artists,
        albumArtUrl: artUrl,
        durationMs:  item['duration_ms'] as int,
        progressMs:  json['progress_ms'] as int? ?? 0,
        isPlaying:   json['is_playing'] as bool? ?? false,
        trackId:     item['id'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Album art ─────────────────────────────────────────────────────────────

  /// Downloads [url], resizes to 32×32, converts to ARGB Uint32List.
  Future<({Uint32List pixels, int width, int height})?> fetchAlbumArt(
      String url) async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final decoded = img.decodeImage(resp.bodyBytes);
      if (decoded == null) return null;

      // Resize to exactly 32×32 (matrix height) for tight compositing
      const int artSize = 32;
      final resized = img.copyResize(decoded, width: artSize, height: artSize,
          interpolation: img.Interpolation.average);
      final rgba = resized.convert(format: img.Format.uint8, numChannels: 4);
      final raw  = rgba.toUint8List();
      final n    = artSize * artSize;
      final argb = Uint32List(n);

      for (int i = 0; i < n; i++) {
        argb[i] = (raw[i * 4 + 3] << 24) // A
                | (raw[i * 4    ] << 16)  // R
                | (raw[i * 4 + 1] <<  8)  // G
                |  raw[i * 4 + 2];        // B
      }

      return (pixels: argb, width: artSize, height: artSize);
    } catch (_) {
      return null;
    }
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  Future<bool> play(String token)         => _put(token, 'play');
  Future<bool> pause(String token)        => _put(token, 'pause');
  Future<bool> skipNext(String token)     => _post(token, 'next');
  Future<bool> skipPrevious(String token) => _post(token, 'previous');

  Future<bool> _put(String token, String action) async {
    try {
      final resp = await http
          .put(Uri.parse('$_base/me/player/$action'), headers: _auth(token))
          .timeout(const Duration(seconds: 8));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) { return false; }
  }

  Future<bool> _post(String token, String action) async {
    try {
      final resp = await http
          .post(Uri.parse('$_base/me/player/$action'), headers: _auth(token))
          .timeout(const Duration(seconds: 8));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) { return false; }
  }
}